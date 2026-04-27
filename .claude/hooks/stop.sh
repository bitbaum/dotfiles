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

# clear current-prompt tracking — Claude just finished whatever it was doing
rm -f "/tmp/claude-current-prompt-${TAB_NAME:-default}"

# close_session sentinel means: "don't show popup; mark session as closed"
SENTINEL="/tmp/claude-session-closed-${TAB_NAME:-default}"
if [ -f "$SENTINEL" ]; then
  log "close-session sentinel found — writing closed file and exiting without popup"
  rm -f "$SENTINEL"
  # Write closed timestamp (Claude actually finished the close_session prompt now)
  echo "$(date +%s)" > "/tmp/claude-closed-${TAB_NAME:-default}"
  rm -f "/tmp/claude-ready-${TAB_NAME:-default}"
  rm -f "/tmp/claude-closing-${TAB_NAME:-default}"
  exit 0
fi

# Signal to Cockpit /control that this project just finished (phone remote control)
READY="/tmp/claude-ready-${TAB_NAME:-default}"
echo "$(date +%s)" > "$READY"

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
  # Look up prompt key from slot number — SSOT is claude-prompts-meta.json
  _META="${CLAUDE_PROMPTS_META:-$HOME/.config/claude-prompts-meta.json}"
  KEY=$(jq -r --argjson slot "$CHOICE" '.[] | select(.slot == $slot) | .key' "$_META" 2>/dev/null)
  [ -z "$KEY" ] && log "no key for slot=$CHOICE" && exit 0

  BASE=$(get_prompt "$KEY")
  [ -z "$BASE" ] && log "prompt not found for key=$KEY" && exit 0

  # close_session means "stop here" — write sentinel now so the NEXT stop hook
  # (after Claude finishes the close_session prompt) skips the popup and writes closed file.
  if [ "$KEY" = "close_session" ] && [ -n "$TAB_NAME" ]; then
    touch "/tmp/claude-session-closed-${TAB_NAME}"
    echo "$(date +%s)" > "/tmp/claude-closing-${TAB_NAME}"
    rm -f "/tmp/claude-ready-${TAB_NAME}"
    log "close_session chosen — sentinel + closing file written; closed file deferred to next stop"
  fi

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
