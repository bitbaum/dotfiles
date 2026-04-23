#!/bin/bash
# Claude Code Stop hook — Claude finished.
# Shows a countdown popup; auto-injects a context-aware prompt unless dismissed.

source ~/.claude/hooks/lib.sh

LOG=/tmp/claude-hooks.log
log() { echo "[$(date '+%H:%M:%S')] stop: $*" >> "$LOG"; }

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

resolve_tab "$CWD"
LABEL="${TAB_NAME:-$(basename "$CWD")}"
log "fired — label=$LABEL"

# Block notification.sh from auto-injecting while this popup is open
LOCK="/tmp/claude-stop-active-${TAB_NAME:-default}"
touch "$LOCK"
trap "rm -f '$LOCK'" EXIT

play_sound "complete"

SESSION_FILE="$HOME/.claude/sessions/${TAB_NAME}.md"

CHOICE=$(DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$_DBUS" \
  python3 ~/.claude/hooks/claude-popup.py stop "$LABEL" "$SESSION_FILE" 2>>"$LOG")
log "popup choice=$CHOICE"

[ -z "$CHOICE" ] && exit 0

# ── Build the prompt ───────────────────────────────────────────────────────────

if [[ "$CHOICE" == custom:* ]]; then
  PROMPT="${CHOICE#custom:}"
  log "using custom prompt"
else
  case "$CHOICE" in
    1)  KEY="next_best"    ;;  # core
    2)  KEY="test_and_fix" ;;  # core
    3)  KEY="commit_push"  ;;  # core
    4)  KEY="quality"      ;;  # core
    5)  KEY="full_audit"   ;;  # core
    6)  KEY="mission"      ;;  # core
    7)  KEY="browser_test" ;;  # more
    8)  KEY="deploy_check" ;;  # more
    9)  KEY="product"      ;;  # more
    10) KEY="ux_review"    ;;  # more
    11) KEY="marketing"    ;;  # more
    12) KEY="social"       ;;  # more
    *)  exit 0 ;;
  esac

  BASE=$(get_prompt "$KEY")
  [ -z "$BASE" ] && log "prompt not found for key=$KEY" && exit 0

  # Wrap with session context if available
  if [ -n "$TAB_NAME" ] && [ -f "$SESSION_FILE" ]; then
    SESSION=$(cat "$SESSION_FILE")
    PROMPT=$(printf '%s\n\nSession state from last run:\n%s\n\nUpdate %s when done: what you completed and what remains.' \
      "$BASE" "$SESSION" "$SESSION_FILE")
    log "injecting with session context from $SESSION_FILE"
  else
    # No session file yet — ask Claude to create one
    PROMPT=$(printf '%s\n\nBefore stopping, create %s with two lines: "done: <what you completed>" and "next: <what remains>".' \
      "$BASE" "$HOME/.claude/sessions/${TAB_NAME}.md")
    log "injecting without session context (no file yet)"
  fi
fi

# ── Inject ─────────────────────────────────────────────────────────────────────

if inject_prompt "$TAB_NAME" "$PROMPT"; then
  log "injected into tab=$TAB_NAME"
else
  log "skipped — $LABEL not in claude-projects.conf"
fi
