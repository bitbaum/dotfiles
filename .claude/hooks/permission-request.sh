#!/bin/bash
# PermissionRequest hook: answer the prompts George always approves.
#
# Why this exists: EnterWorktree(path=...) into a sibling repo's worktree
# (session at ~, target ~/dev/heidi/.claude/worktrees/x) raises a
# "permission-root relocation" prompt that an allow rule does NOT silence --
# "EnterWorktree" was already in permissions.allow and it still asked. Every
# background job that isolates itself hits it, and the answer is always yes.
#
# Only a target that resolves (symlinks and .. included) to exactly
# $HOME/dev/<repo>/.claude/worktrees/<name> is approved. Anything else prints
# nothing, which falls through to the normal prompt.

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty')

allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\n'
  exit 0
}

case "$tool" in
  EnterWorktree)
    path=$(printf '%s' "$input" | jq -r '.tool_input.path // empty')
    [ -n "$path" ] || exit 0
    real=$(realpath -m -- "$path" 2>/dev/null) || exit 0
    [[ "$real" =~ ^"$HOME"/dev/[^/]+/\.claude/worktrees/[^/]+$ ]] && allow
    ;;
esac
exit 0
