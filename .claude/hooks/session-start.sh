#!/usr/bin/env bash
# Show every agent what the others are doing, at the start of every session.
#
# THIS DELIBERATELY OWNS NO LOGIC. `scripts/fleet-status.sh` already reads the
# session registry, groups it by project and adds recent git activity; a second
# implementation would be exactly the duplication fleet/SHARED.md exists to
# stop. This file's whole job is to make that script UNAVOIDABLE rather than
# something a session has to remember to run.
#
# The gap it closes is adherence, not capability. CLAUDE.md has long said to
# check the registry before wide-blast-radius work. On 2026-09-08 an
# aoz-housing session deleted 40 production rows and ran a schema migration
# without opening it once — and got away with it only because that repo
# happened to hold one session. Worktrees isolate FILES; what collides is
# intent, and nothing was making anyone look.
#
# Never fails a session start: a missing script, a slow script or bad JSON all
# degrade to a note or to silence, never to an error the user has to clear.

set -uo pipefail

STATUS_SCRIPT="${HOME}/dev/dotfiles/scripts/fleet-status.sh"

emit() {
  jq -n --arg ctx "$1" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
}

if [ ! -x "$STATUS_SCRIPT" ]; then
  # Say so rather than going quiet. A hook that silently does nothing is
  # indistinguishable from a hook that is working and has nothing to report,
  # and that ambiguity is how this whole class of bug survives.
  emit "Fleet status unavailable: ${STATUS_SCRIPT} is missing or not executable.
Run 'git -C ~/dev/dotfiles pull' — the script ships there. Until then you are
starting without knowing what other sessions are doing."
  exit 0
fi

out=$(timeout 15s "$STATUS_SCRIPT" 2>/dev/null) || true

if [ -z "$out" ]; then
  emit "Fleet status returned nothing (script present but produced no output)."
  exit 0
fi

emit "Other Claude sessions and recent fleet activity, at session start.
Worktrees isolate files, NOT decisions — scan this for semantic collisions
before wide-blast-radius work (a shared type layer, a migration, a config every
project reads). Run 'fleet-status.sh --prs --days 3' for a wider picture.

${out}"
