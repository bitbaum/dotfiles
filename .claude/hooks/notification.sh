#!/bin/bash
# Claude Code Notification hook — Claude is waiting for input.
# Auto-injects "use your best judgment and continue" without showing a popup.
# Plays a sound so you're aware something happened.

source ~/.claude/hooks/lib.sh

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

resolve_tab "$CWD"
[ -z "$TAB_NAME" ] && exit 0

# Don't inject while the Stop popup is open for this project — user is deciding.
# If the lock is older than 5 minutes the popup crashed without cleanup; treat as gone.
LOCK="/tmp/claude-stop-active-${TAB_NAME}"
if [ -f "$LOCK" ]; then
  age=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
  if [ "$age" -lt 300 ]; then
    exit 0
  fi
  rm -f "$LOCK"
fi

# Don't inject if a close_session is in flight or just finished:
#   SENTINEL  = close_session was chosen, prompt not yet started
#   CLOSING   = close_session prompt is running
#   CLOSED    = close_session just finished (stop.sh consumed sentinel and wrote this)
# All three mean: do not restart the session.
SENTINEL="/tmp/claude-session-closed-${TAB_NAME}"
CLOSING="/tmp/claude-closing-${TAB_NAME}"
CLOSED="/tmp/claude-closed-${TAB_NAME}"
[ -f "$SENTINEL" ] && exit 0
[ -f "$CLOSING"  ] && exit 0
[ -f "$CLOSED"   ] && exit 0

play_sound "window-attention"

PROMPT=$(get_prompt "continue")
[ -z "$PROMPT" ] && exit 0

inject_prompt "$TAB_NAME" "$PROMPT"
