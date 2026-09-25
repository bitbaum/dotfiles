#!/bin/bash
# Tests for the PermissionRequest hook's EnterWorktree auto-approval.
# Exact in both directions: a real sibling worktree is approved, and anything
# that merely LOOKS like one (.., a deeper path, another home) still prompts.

set -uo pipefail

HOOK="${1:-$(dirname "$0")/../permission-request.sh}"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK" >&2; exit 1; }

fail=0

run() {  # $1 = expected ALLOW|ASK, $2 = tool, $3 = path
  local json out got
  json=$(jq -nc --arg t "$2" --arg p "$3" '{tool_name:$t, tool_input:{path:$p}}')
  out=$(printf '%s' "$json" | bash "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.decision.behavior == "allow"' >/dev/null 2>&1; then
    got=ALLOW; else got=ASK; fi
  if [ "$got" = "$1" ]; then echo "  ok   $got  $2 $3"
  else echo "  FAIL want $1 got $got  $2 $3"; fail=1; fi
}

run ALLOW EnterWorktree "$HOME/dev/heidi/.claude/worktrees/speech-wired"
run ALLOW EnterWorktree "$HOME/dev/loki/.claude/worktrees/x/"
run ASK   EnterWorktree "$HOME/dev/heidi/.claude/worktrees/../../../../etc"
run ASK   EnterWorktree "$HOME/dev/heidi/.claude/worktrees"
run ASK   EnterWorktree "$HOME/dev/heidi/.claude/worktrees/a/b"
run ASK   EnterWorktree "$HOME/dev/heidi/src"
run ASK   EnterWorktree "/tmp/dev/heidi/.claude/worktrees/x"
run ASK   EnterWorktree "/home/other/dev/heidi/.claude/worktrees/x"
run ASK   EnterWorktree ""
run ASK   Bash          "$HOME/dev/heidi/.claude/worktrees/x"

exit $fail
