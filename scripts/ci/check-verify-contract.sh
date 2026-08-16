#!/usr/bin/env bash
#
# Does this repo actually honour the Golden CI Floor?
#
# templates/ci/README.md has stated the rule for a while: "verified" is defined
# ONCE, in package.json `verify`, and run identically in CI and locally. Stating
# a rule is not enforcing one — the previous fleet audit checked whether repos
# *declared* a verify script and found 21 of 21 did, which reads like success
# and is not: a repo can declare a perfect `verify` that CI never calls, or call
# it in a way that cannot go red.
#
# Both have happened here. One repo hand-copied verify's steps into CI with
# `--if-present` on each, so renaming a script would have made CI pass silently.
# Another ran `continue-on-error: true` over its tests and reported green for
# three weeks across 7,769 tests. The failure is never "no gate" — it is a gate
# that cannot go red, which is strictly worse than no gate because it is
# believed.
#
# So this checks the contract END TO END:
#
#   1. `verify` exists.
#   2. CI actually invokes it (`npm|pnpm|yarn run verify`).
#   3. That invocation is not softened with `--if-present`.
#   4. The step running it does not carry `continue-on-error: true`.
#   5. `verify` itself is not softened from the inside (`|| true`).
#
# WHAT IT DELIBERATELY DOES NOT CHECK, so nobody reads a pass as more than it is:
#   - whether the checks inside `verify` are any good, or cover anything;
#   - whether the tests it runs actually assert;
#   - `|| true` elsewhere in CI. That is usually legitimate (cleanup, optional
#     copies, `jq` parses with a fallback) and flagging it produced nine false
#     alarms out of nine in this fleet. A checker that cries wolf gets ignored,
#     which is the same failure mode it exists to prevent.
#
# Usage:
#   check-verify-contract.sh                # current repo
#   check-verify-contract.sh --all [DIR]    # every git repo under DIR (~/dev)
#
# Exit 0 = conforms. Exit 1 = at least one violation.

set -uo pipefail

FAILURES=0
CHECKED=0
SKIPPED=0

red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n' "$*"; }

fail() {
  red "  ✗ $1"
  FAILURES=$((FAILURES + 1))
}

# Which package manager does this repo speak? The verify invocation must match,
# or the grep for it misses and every repo looks broken.
detect_pm() {
  local dir="$1"
  [ -f "$dir/pnpm-lock.yaml" ] && { echo pnpm; return; }
  [ -f "$dir/yarn.lock" ] && { echo yarn; return; }
  echo npm
}

check_repo() {
  local dir="$1"
  local name
  name="$(basename "$dir")"

  if [ ! -f "$dir/package.json" ]; then
    SKIPPED=$((SKIPPED + 1))
    return 0
  fi

  CHECKED=$((CHECKED + 1))
  local before=$FAILURES
  printf '%s\n' "$name"

  local verify
  verify="$(jq -r '.scripts.verify // ""' "$dir/package.json" 2>/dev/null)"

  # 1. The SSOT must exist.
  if [ -z "$verify" ]; then
    fail "no \`verify\` script — there is no single definition of 'verified' to run"
    return 0
  fi

  # 5. …and must not be softened from the inside. A `|| true` here defeats every
  # other check in this script, because CI would faithfully run a gate that
  # cannot fail.
  case "$verify" in
    *"|| true"*|*"--if-present"*)
      fail "\`verify\` is softened from the inside: ${verify}"
      ;;
  esac

  local wfdir="$dir/.github/workflows"
  if [ ! -d "$wfdir" ]; then
    fail "no .github/workflows — \`verify\` exists but nothing runs it on push/PR"
    return 0
  fi

  local pm
  pm="$(detect_pm "$dir")"

  # 2. CI must call it. Accept every package manager's spelling, INCLUDING the
  # implicit-run forms (`pnpm verify`, `yarn verify`) which are idiomatic and
  # were a false positive in the first version of this check — a checker that
  # reports a conforming repo as broken burns exactly the trust it needs.
  # `\b` keeps it from matching a longer script name like `verify-deploy`.
  local hits
  hits="$(grep -rnE "(npm|pnpm|yarn) (run )?verify\b" "$wfdir" 2>/dev/null)"
  if [ -z "$hits" ]; then
    fail "CI never runs \`$pm run verify\` — the local gate and the CI gate are two different things, and only one of them blocks a merge"
    dim "      verify = $verify"
    return 0
  fi

  # 3. `--if-present` turns a missing script into a pass. In CI that is a gate
  # that cannot go red: rename the script, keep the green tick.
  if printf '%s\n' "$hits" | grep -q -- '--if-present'; then
    fail "CI runs verify with \`--if-present\` — a renamed or deleted script would pass silently"
  fi

  # 4. `continue-on-error` on the verify step discards the result. Scoped to the
  # step block containing the invocation rather than the whole file, because
  # elsewhere it is often correct (see the header).
  local file line
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    file="${hit%%:*}"
    line="$(printf '%s' "$hit" | cut -d: -f2)"
    # A step block runs from its own "- " marker to the next one. Find the start,
    # then look only inside it.
    local start end block
    start="$(awk -v L="$line" 'NR<=L && /^[[:space:]]*-[[:space:]]/ {n=NR} END{print n+0}' "$file")"
    [ "$start" -eq 0 ] && start=1
    end="$(awk -v S="$start" 'NR>S && /^[[:space:]]*-[[:space:]]/ {print NR-1; exit}' "$file")"
    [ -z "$end" ] && end="$(wc -l < "$file")"
    block="$(sed -n "${start},${end}p" "$file")"
    if printf '%s\n' "$block" | grep -qE 'continue-on-error:[[:space:]]*true'; then
      fail "the CI step running verify carries \`continue-on-error: true\` ($(basename "$file"):$line) — its result is discarded"
    fi
  done <<< "$hits"

  if [ "$FAILURES" -eq "$before" ]; then
    green "  ✓ verify is the SSOT, and CI runs it unsoftened"
  fi
}

main() {
  if [ "${1:-}" = "--all" ]; then
    local root="${2:-$HOME/dev}"
    printf 'Verify-contract conformance under %s\n\n' "$root"
    local d
    for d in "$root"/*/; do
      [ -d "$d/.git" ] || continue
      check_repo "${d%/}"
    done
  else
    local dir
    dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    check_repo "$dir"
  fi

  printf '\n'
  if [ "$FAILURES" -gt 0 ]; then
    red "$FAILURES violation(s) across $CHECKED repo(s) ($SKIPPED without package.json skipped)"
    printf 'Fix: make CI run `<pm> run verify` verbatim. Template: templates/ci/\n'
    return 1
  fi
  green "All $CHECKED repo(s) conform ($SKIPPED without package.json skipped)"
  return 0
}

main "$@"
