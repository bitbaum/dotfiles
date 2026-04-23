#!/bin/bash
# Claude Code Notification hook — Claude is waiting for input.
# Auto-injects "use your best judgment and continue" without showing a popup.
# Plays a sound so you're aware something happened.

source ~/.claude/hooks/lib.sh

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

resolve_tab "$CWD"

# Don't inject while the Stop popup is open for this project — user is deciding
LOCK="/tmp/claude-stop-active-${TAB_NAME:-default}"
[ -f "$LOCK" ] && exit 0

play_sound "window-attention"

PROMPT=$(get_prompt "continue")
[ -z "$PROMPT" ] && exit 0

inject_prompt "$TAB_NAME" "$PROMPT"
