#!/usr/bin/env bash
# Fleet audit: does every repo's `verify` actually meet the golden CI floor?
#
# templates/ci/README.md defines "verified" as ONE script, identical in every
# repo:  verify = lint && typecheck && test.  That contract was written down
# and never enforced, so it drifted: repos ship a `verify` that silently omits
# a gate, and "verify is green" quietly means something different in each one.
# Every other guarantee in the fleet (the merge train, auto-merge, "green
# locally ⇒ green CI") is built on top of that sentence being true.
#
# This is deliberately ONE script that reads every repo remotely, NOT a check
# copied into each repo. The auto-merge sweep was copied into 17 repos and now
# has at least 5 live variants; a fix landed in one reaches none of the others.
# Central auditor = no drift by construction.
#
# SCOPE — what this does NOT prove. It audits the CONTRACT (does `verify` run
# all three gates), not whether each gate is EFFECTIVE. A repo whose `lint`
# script exists but silently does nothing passes here. sbb-lost-found is the
# live example: `next lint` prompts interactively because the repo has a flat
# config Next 14 cannot read, so lint has never actually run — and this audit
# would have called it satisfied had verify referenced it. Contract first;
# effectiveness is a separate check.
#
# ONE effectiveness hole is checked, because the fleet has already fallen down
# it: a CI step that RUNS a floor gate and then throws the result away with
# `continue-on-error: true`. evig's unit-test job carried that flag from the
# day it was added ("non-blocking while the suite matures"); the suite matured
# to 7,769 tests, the 2026-07-28 token sweep broke 25 assertions, and every PR
# for three weeks reported the job green. A discarded gate is worse than an
# absent one — it is an absent gate that produces a ✓. The check is narrow on
# purpose: only steps running lint/typecheck/test/verify count, so a
# best-effort step with a real fallback (orangecat's cd.yml artifact download)
# is correctly ignored.
#
# Usage:
#   scripts/ci/verify-floor-audit.sh              # audit, exit 1 on violations
#   scripts/ci/verify-floor-audit.sh --warn-only  # report, always exit 0
#
# Env:
#   GH_OWNER   GitHub owner to enumerate (default: maonakamoto)
#   GH_LIMIT   max repos to inspect (default: 100)

set -uo pipefail   # NOT -e: nearly every step below asks a QUESTION about a
                   # remote repo, and a 404 is an answer, not a crash.

OWNER="${GH_OWNER:-maonakamoto}"
LIMIT="${GH_LIMIT:-100}"
WARN_ONLY=0
[ "${1:-}" = "--warn-only" ] && WARN_ONLY=1

# Declared before any branch that could skip the assignment — under `set -u` a
# later reference would otherwise kill the whole run instead of one repo.
ok_list=""
weak_list=""
missing_list=""
skipped_list=""
unreadable_list=""
discarded_list=""
total=0

command -v gh >/dev/null 2>&1 || { echo "gh CLI not found" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq not found" >&2; exit 2; }

# Report every step that both runs a floor gate and discards its result.
#
# Scoped to STEP blocks (a list item, `^\s*- `), not whole jobs: a step is the
# unit `continue-on-error` attaches to in the common case, and correlating a
# job-level flag with the gate it silences needs a real YAML parser. That is a
# known blind spot, stated rather than papered over — a job-level flag on a
# gate job would be missed here.
#
# A `run: |` block puts the command on LATER lines than the `run:` key, so any
# line inside the block is tested, not just the key line.
scan_discarded_gates() {
  awk -v wf="$1" '
    function flush() {
      if (has_gate && has_coe) printf "%s (%s)\n", wf, gate
      has_gate = 0; has_coe = 0; gate = ""
    }
    /^[[:space:]]*-[[:space:]]/ { flush() }
    {
      if ($0 ~ /(npm|pnpm|yarn|bun)([[:space:]]+run)?[[:space:]]+(test|lint|typecheck|type-check|verify)([[:space:]]|$)/ ||
          $0 ~ /(eslint|vitest|jest|mocha|playwright test|tsc[[:space:]]+--noEmit|vue-tsc|svelte-check)/) {
        has_gate = 1
        if (gate == "") { gate = $0; sub(/^[[:space:]]*(-[[:space:]]*)?(run:[[:space:]]*)?/, "", gate) }
      }
      if ($0 ~ /continue-on-error:[[:space:]]*true/) has_coe = 1
    }
    END { flush() }
  '
}

echo "verify-floor audit — owner: $OWNER"
echo "floor: verify must run lint AND typecheck AND test"
echo

repos=$(gh repo list "$OWNER" --limit "$LIMIT" --no-archived \
          --json name,defaultBranchRef \
          --jq '.[] | "\(.name)\t\(.defaultBranchRef.name // "")"' 2>/dev/null)

if [ -z "$repos" ]; then
  echo "could not list repos for $OWNER" >&2
  exit 2
fi

while IFS=$'\t' read -r name branch; do
  [ -n "$name" ] || continue
  # A repo with no default branch ref is empty — nothing to audit, say so.
  if [ -z "$branch" ]; then
    skipped_list="${skipped_list}  $name (empty repo)\n"
    continue
  fi

  # Resolve package.json ON THE REPO'S OWN DEFAULT BRANCH. Asking for ?ref=main
  # on a master repo 404s, which means "wrong ref", not "no package.json" —
  # that mistake previously produced a confidently wrong fleet survey.
  pkg=$(gh api "repos/$OWNER/$name/contents/package.json?ref=$branch" \
          --jq '.content' 2>/dev/null | tr -d '\n' | base64 -d 2>/dev/null)

  if [ -z "$pkg" ]; then
    skipped_list="${skipped_list}  $name (no package.json on $branch)\n"
    continue
  fi

  total=$((total + 1))

  scripts=$(printf '%s' "$pkg" | jq -r '.scripts // {}' 2>/dev/null)
  if [ -z "$scripts" ] || [ "$scripts" = "null" ]; then
    unreadable_list="${unreadable_list}  $name (package.json did not parse)\n"
    continue
  fi

  verify=$(printf '%s' "$scripts" | jq -r '.verify // ""')

  gaps=""       # gates the repo COULD run but verify does not
  absent=""     # gates the repo has no script for at all

  # Expand `npm run X` / `pnpm X` inside verify two levels deep, so a gate
  # counts whether it is reached via a named script or run directly. Matching
  # only script NAMES would flag fleetcrown (which calls `tsc --noEmit`
  # inline) and orangecat (whose script is `type-check`, hyphenated) as
  # having no typecheck — both false. A gate is satisfied by the TOOL that
  # runs, not by the name someone gave it.
  expand_once() {
    # Each `local` on its own line: under `set -u`, `local a="$1" b="$a"`
    # reads $a before the same statement assigns it, so the function aborts
    # and silently returns empty — which reads as "no gate found" and marks
    # every healthy repo as failing.
    local cmd="$1"
    local out="$cmd"
    local ref
    local body
    for ref in $(printf '%s' "$cmd" | grep -oE '(npm|pnpm|yarn)( run)? [a-zA-Z0-9:_-]+' \
                   | awk '{print $NF}' | sort -u); do
      body=$(printf '%s' "$scripts" | jq -r --arg k "$ref" '.[$k] // ""')
      [ -n "$body" ] && out="$out ; $body"
    done
    printf '%s' "$out"
  }
  expanded=$(expand_once "$verify")
  expanded=$(expand_once "$expanded")

  # Same expansion over ALL scripts, to answer the different question of
  # whether the repo owns such a gate anywhere.
  all_bodies=$(printf '%s' "$scripts" | jq -r 'to_entries[] | "\(.key) \(.value)"')

  gate_re_lint='eslint|biome (lint|check)|next lint|oxlint|standard'
  gate_re_type='tsc |tsc$|vue-tsc|type-?check|svelte-check|astro check'
  gate_re_test='vitest|jest|playwright|node --test|mocha|ava |bun test|\btest\b'

  for gate in lint typecheck test; do
    case "$gate" in
      lint)      re="$gate_re_lint" ;;
      typecheck) re="$gate_re_type" ;;
      test)      re="$gate_re_test" ;;
    esac

    # A gate is satisfied two ways, and both are needed:
    #  1. verify CALLS a script named for it (`npm run lint`, `pnpm test`,
    #     `type-check`). Then the repo asserts the gate, and we take its word —
    #     which is what lets `turbo lint` and `cd frontend && npm run lint`
    #     count without this script having to see through them.
    #  2. verify runs the TOOL inline with no named script — fleetcrown calls
    #     `tsc --noEmit` straight from verify.
    if printf '%s' "$verify" | grep -qE "(^|[^a-z:_-])(${gate}|type-check)([^a-z:_-]|$)"; then
      continue
    fi
    if printf '%s' "$expanded" | grep -qE "$re"; then
      continue
    fi

    # Not reached by verify. Does the repo own the gate anywhere?
    named=$(printf '%s' "$scripts" | jq -r --arg g "$gate" \
              'if (.[$g] // "") != "" or ($g == "typecheck" and (."type-check" // "") != "")
               then "yes" else "no" end')

    if [ "$named" = yes ] || printf '%s' "$all_bodies" | grep -qE "$re"; then
      gaps="$gaps $gate"            # repo owns it, verify just skips it
    else
      absent="$absent $gate"        # nothing in the repo runs this gate
    fi
  done

  # Effectiveness probe: a gate CI runs and then ignores. Costs one listing
  # plus one fetch per workflow file, which is why it lives in a weekly cron
  # and not a per-push hook.
  for wf in $(gh api "repos/$OWNER/$name/contents/.github/workflows?ref=$branch" \
                --jq '.[] | select(.name | test("\\.ya?ml$")) | .name' 2>/dev/null); do
    wf_body=$(gh api "repos/$OWNER/$name/contents/.github/workflows/$wf?ref=$branch" \
                --jq '.content' 2>/dev/null | tr -d '\n' | base64 -d 2>/dev/null)
    [ -n "$wf_body" ] || continue
    hits=$(printf '%s\n' "$wf_body" | scan_discarded_gates "$wf")
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      discarded_list="${discarded_list}  $name — $hit\n"
    done <<< "$hits"
  done

  if [ -z "$verify" ]; then
    missing_list="${missing_list}  $name — no \`verify\` script at all\n"
  elif [ -n "$absent" ]; then
    # Not fixable by editing verify: the repo has no such script. Adding a
    # no-op to satisfy the floor would be theatre, so this is reported as work.
    missing_list="${missing_list}  $name — no script for:$absent${gaps:+ (also missing from verify:$gaps)}\n"
  elif [ -n "$gaps" ]; then
    weak_list="${weak_list}  $name — has the script but verify skips:$gaps\n"
  else
    ok_list="${ok_list}  $name\n"
  fi
done <<< "$repos"

printf '✓ AT FLOOR (%s)\n' "$(printf '%b' "$ok_list" | grep -c . || true)"
printf '%b' "${ok_list:-  (none)\n}"

echo
printf '▲ FIXABLE — verify omits a gate the repo already has\n'
printf '%b' "${weak_list:-  (none)\n}"

echo
printf '✗ NEEDS REAL WORK — no script exists for a required gate\n'
printf '%b' "${missing_list:-  (none)\n}"

echo
printf '⊘ DISCARDED — CI runs a floor gate and throws the result away\n'
printf '%b' "${discarded_list:-  (none)\n}"


if [ -n "$skipped_list" ]; then
  echo
  echo "· skipped (not a JS repo / empty)"
  printf '%b' "$skipped_list"
fi

if [ -n "$unreadable_list" ]; then
  echo
  echo "· unreadable"
  printf '%b' "$unreadable_list"
fi

echo
echo "inspected $total JS repo(s)"
echo "note: this checks that verify RUNS each gate, not that each gate works —"
echo "      with one exception, the discarded-gate check above."

violations=$(( $(printf '%b' "$weak_list" | grep -c . || true) + \
               $(printf '%b' "$missing_list" | grep -c . || true) + \
               $(printf '%b' "$discarded_list" | grep -c . || true) ))

if [ "$violations" -gt 0 ] && [ "$WARN_ONLY" -eq 0 ]; then
  echo "verify-floor: $violations repo(s) below the floor" >&2
  exit 1
fi

echo "verify-floor: $violations repo(s) below the floor"
