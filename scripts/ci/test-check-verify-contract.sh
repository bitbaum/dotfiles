#!/usr/bin/env bash
#
# Negative tests for check-verify-contract.sh.
#
# The checker reported "all 21 repos conform" the first time it ran clean, and a
# checker that has never gone red is indistinguishable from one that CANNOT.
# That is the exact failure it exists to catch, so every rule is proved to bite
# against a fixture that violates it — and, just as important, a conforming
# fixture is proved NOT to trip it, because a checker that cries wolf gets
# ignored and then it may as well not exist.
#
# The fixtures use plain directories containing an empty `.git` dir rather than
# real git repos: the checker only tests for `-d .git`, and running `git` inside
# a throwaway tree has already destroyed a repository in this fleet once (git
# walks UP out of a non-repo directory). No git, no blast radius.

set -uo pipefail

CHECKER="$(cd "$(dirname "$0")" && pwd)/check-verify-contract.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

# make_repo <name> <verify-script-json-or-empty> <workflow-body-or-empty>
make_repo() {
  local name="$1" verify="$2" wf="$3"
  local d="$TMP/$name"
  mkdir -p "$d/.git"
  if [ -n "$verify" ]; then
    printf '{"name":"%s","scripts":{"verify":%s}}\n' "$name" "$verify" > "$d/package.json"
  else
    printf '{"name":"%s","scripts":{}}\n' "$name" > "$d/package.json"
  fi
  if [ -n "$wf" ]; then
    mkdir -p "$d/.github/workflows"
    printf '%s\n' "$wf" > "$d/.github/workflows/ci.yml"
  fi
}

# expect <fixture> <pass|fail> <description>
expect() {
  local name="$1" want="$2" desc="$3"
  local out rc
  out="$(bash "$CHECKER" --all "$TMP" 2>&1)"
  # Re-run scoped to just this fixture by checking its section of the output.
  local section
  section="$(printf '%s\n' "$out" | awk -v n="$name" '$0==n{f=1;next} /^[a-zA-Z0-9._-]+$/{f=0} f')"
  if printf '%s' "$section" | grep -q '✗'; then rc=fail; else rc=pass; fi
  if [ "$rc" = "$want" ]; then
    printf '  ✓ %s\n' "$desc"
    PASS=$((PASS + 1))
  else
    printf '  ✗ %s — expected %s, got %s\n' "$desc" "$want" "$rc"
    printf '%s\n' "$section" | sed 's/^/      /'
    FAIL=$((FAIL + 1))
  fi
}

GOOD_WF='jobs:
  verify:
    steps:
      - name: Verify
        run: npm run verify'

# ── the closed side: each rule must actually bite ────────────────────────────

make_repo a-no-verify '' "$GOOD_WF"
expect a-no-verify fail 'a repo with no `verify` script is caught'

make_repo b-softened-inside '"eslint . || true"' "$GOOD_WF"
expect b-softened-inside fail '`verify` softened from the inside (|| true) is caught'

make_repo c-softened-ifpresent '"npm run lint --if-present"' "$GOOD_WF"
expect c-softened-ifpresent fail '`verify` softened with --if-present is caught'

make_repo d-no-workflows '"eslint ."' ''
expect d-no-workflows fail 'a verify nothing runs on push/PR is caught'

make_repo e-ci-ignores '"eslint ."' 'jobs:
  verify:
    steps:
      - name: Lint
        run: npm run lint
      - name: Test
        run: npm run test'
expect e-ci-ignores fail 'CI hand-copying the steps instead of calling verify is caught'

make_repo f-ifpresent-in-ci '"eslint ."' 'jobs:
  verify:
    steps:
      - name: Verify
        run: npm run verify --if-present'
expect f-ifpresent-in-ci fail 'CI running verify with --if-present is caught'

make_repo g-continue-on-error '"eslint ."' 'jobs:
  verify:
    steps:
      - name: Verify
        continue-on-error: true
        run: npm run verify'
expect g-continue-on-error fail 'continue-on-error on the verify step is caught'

# ── the open side: conforming shapes must NOT be flagged ─────────────────────

make_repo h-conforming '"eslint . && tsc --noEmit && vitest run"' "$GOOD_WF"
expect h-conforming pass 'a conforming npm repo passes'

make_repo i-pnpm-implicit-run '"eslint ."' 'jobs:
  verify:
    steps:
      - name: Verify
        run: pnpm verify'
expect i-pnpm-implicit-run pass 'pnpm implicit-run (`pnpm verify`) is accepted'

make_repo j-benign-continue '"eslint ."' 'jobs:
  verify:
    steps:
      - name: Optional artifact
        continue-on-error: true
        uses: actions/download-artifact@v8
      - name: Verify
        run: npm run verify'
expect j-benign-continue pass 'continue-on-error on a DIFFERENT step is not flagged'

make_repo k-benign-or-true '"eslint ."' 'jobs:
  verify:
    steps:
      - name: Cleanup
        run: docker stop x || true
      - name: Verify
        run: npm run verify'
expect k-benign-or-true pass '|| true elsewhere in CI is not flagged'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
