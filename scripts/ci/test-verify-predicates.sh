#!/usr/bin/env bash
#
# Negative tests for the verify-contract WIRING rules.
#
# The rules live in verify-predicates.sh precisely so they can be tested without
# reaching GitHub — the audit that uses them is remote-only, and a rule that can
# only be exercised by a live API call is a rule nobody re-tests after changing
# one of its regexes.
#
# Both directions are tested on purpose. Proving a rule BITES is half the job;
# proving it stays quiet on a conforming repo is the other half, and skipping it
# is how a checker starts crying wolf and gets ignored — the same end state as
# having no checker, reached more expensively.

set -uo pipefail

# shellcheck source=scripts/ci/verify-predicates.sh
. "$(cd "$(dirname "$0")" && pwd)/verify-predicates.sh"

PASS=0
FAIL=0

ok() { printf '  ✓ %s\n' "$1"; PASS=$((PASS + 1)); }
no() { printf '  ✗ %s\n' "$1"; FAIL=$((FAIL + 1)); }

# assert <expected pass|fail> <predicate> <input> <description>
assert() {
  local want="$1" pred="$2" input="$3" desc="$4"
  if "$pred" "$input"; then got=pass; else got=fail; fi
  [ "$got" = "$want" ] && ok "$desc" || no "$desc (expected $want, got $got)"
}

CALLS='jobs:
  verify:
    steps:
      - name: Verify
        run: npm run verify'

HANDCOPIED='jobs:
  verify:
    steps:
      - name: Lint
        run: npm run lint --if-present
      - name: Test
        run: npm run test --if-present'

SOFTENED='jobs:
  verify:
    steps:
      - name: Verify
        run: npm run verify --if-present'

BENIGN_IFPRESENT='jobs:
  verify:
    steps:
      - name: Optional docs
        run: npm run docs --if-present
      - name: Verify
        run: npm run verify'

echo "ci_invokes_verify"
assert pass ci_invokes_verify "$CALLS"        'npm run verify is detected'
assert pass ci_invokes_verify 'run: pnpm verify'  'pnpm implicit-run is accepted (was a false positive once)'
assert pass ci_invokes_verify 'run: yarn verify'  'yarn implicit-run is accepted'
assert pass ci_invokes_verify 'run: bun run verify' 'bun is accepted'
assert fail ci_invokes_verify "$HANDCOPIED"   'hand-copied steps do NOT count as calling verify'
assert fail ci_invokes_verify 'run: npm run verify-deploy' 'a longer script name is not mistaken for verify'
assert fail ci_invokes_verify ''              'an empty workflow body is not a call'

echo "ci_verify_softened"
assert pass ci_verify_softened "$SOFTENED"          '--if-present ON the verify step is caught'
assert fail ci_verify_softened "$CALLS"             'a clean verify step is not flagged'
assert fail ci_verify_softened "$BENIGN_IFPRESENT"  '--if-present on an UNRELATED step is not flagged'

echo "verify_softens_itself"
assert pass verify_softens_itself 'eslint . || true'                   '|| true inside verify is caught'
assert pass verify_softens_itself 'npm run typecheck --workspaces --if-present' '--if-present inside verify is caught'
assert fail verify_softens_itself 'pnpm lint && pnpm typecheck && pnpm test' 'a clean verify is not flagged'
assert fail verify_softens_itself ''                                   'an empty verify is not flagged here — absence is the audit job'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
