#!/usr/bin/env bash
#
# Predicates for the WIRING half of the verify contract.
#
# verify-floor-audit.sh already answers "does `verify` run all three gates?" —
# a question about the CONTENT of the script. These answer the other half, which
# that audit could not see and which let a real violation sit undetected:
#
#     botsmann's `verify` was perfect — format:check + lint + test + build — so
#     the content audit correctly reported it AT FLOOR. Its CI never called it.
#     CI hand-copied the same four steps and put `--if-present` on each, so a
#     renamed script would have become a silent pass. A repo can satisfy every
#     rule about what `verify` CONTAINS while nothing on the branch runs it.
#
# Kept in their own file, sourced by the audit, so the rules can be tested
# against fixtures without reaching GitHub. The audit itself is remote-only by
# design (it reads every repo's own default branch), and a rule that can only be
# exercised by a live API call is a rule nobody re-tests after changing it.

# Does any workflow actually invoke the verify SSOT?
#
# Accepts every package manager AND the implicit-run spellings (`pnpm verify`,
# `yarn verify`) which are idiomatic — an earlier version demanded the literal
# `run` and reported a conforming repo as broken, which is how a checker earns
# being ignored. `\b` stops it matching a longer name like `verify-deploy`.
ci_invokes_verify() {
  printf '%s\n' "$1" | grep -qE '(npm|pnpm|yarn|bun)([[:space:]]+run)?[[:space:]]+verify([[:space:]]|$)'
}

# Is that invocation softened with --if-present?
#
# `--if-present` turns a missing script into a PASS. On the verify step that is
# the gate-that-cannot-go-red shape: delete or rename `verify` and CI stays
# green while nothing is checked. Only lines that actually invoke verify are
# tested, so `--if-present` on some unrelated optional step is not flagged.
ci_verify_softened() {
  printf '%s\n' "$1" \
    | grep -E '(npm|pnpm|yarn|bun)([[:space:]]+run)?[[:space:]]+verify([[:space:]]|$)' \
    | grep -q -- '--if-present'
}

# Does `verify` disarm itself from the inside?
#
# This one defeats every other rule: CI can faithfully run a gate that has been
# told never to fail. sbb-lost-found shipped
# `npm run typecheck --workspaces --if-present`, which silently passes any
# workspace without a typecheck script.
verify_softens_itself() {
  case "$1" in
    *"|| true"*|*"--if-present"*) return 0 ;;
    *) return 1 ;;
  esac
}
