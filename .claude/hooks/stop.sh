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

  # ── Gather ground-truth context ─────────────────────────────────────────────
  GIT_CTX=""
  if [ -d "${CWD}/.git" ]; then
    GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
    GIT_STATUS=$(git -C "$CWD" status --short 2>/dev/null | head -8)
    GIT_LOG=$(git -C "$CWD" log --oneline -5 2>/dev/null)
    GIT_AHEAD=$(git -C "$CWD" rev-list --count @{upstream}..HEAD 2>/dev/null || echo "")

    GIT_CTX="Git context:
branch: ${GIT_BRANCH}$([ -n "$GIT_AHEAD" ] && echo " ($GIT_AHEAD ahead of origin)")"
    [ -n "$GIT_STATUS" ] && GIT_CTX="${GIT_CTX}
uncommitted:
${GIT_STATUS}"
    GIT_CTX="${GIT_CTX}
recent commits:
${GIT_LOG}"
  fi

  # ── Wrap with session + git context ─────────────────────────────────────────
  if [ -n "$TAB_NAME" ] && [ -f "$SESSION_FILE" ]; then
    SESSION=$(cat "$SESSION_FILE")
    if [ -n "$GIT_CTX" ]; then
      PROMPT=$(printf '%s\n\nProject: %s\n%s\n\nSession state from last run:\n%s\n\nUpdate %s when done.' \
        "$BASE" "$LABEL" "$GIT_CTX" "$SESSION" "$SESSION_FILE")
    else
      PROMPT=$(printf '%s\n\nProject: %s\nSession state from last run:\n%s\n\nUpdate %s when done.' \
        "$BASE" "$LABEL" "$SESSION" "$SESSION_FILE")
    fi
    log "injecting with session + git context"
  else
    # No session file yet — ask Claude to create one
    if [ -n "$GIT_CTX" ]; then
      PROMPT=$(printf '%s\n\nProject: %s\n%s\n\nCreate %s when done with: done/next/tests/todos/health lines.' \
        "$BASE" "$LABEL" "$GIT_CTX" "$HOME/.claude/sessions/${TAB_NAME}.md")
    else
      PROMPT=$(printf '%s\n\nProject: %s\nCreate %s when done with: done/next/tests/todos/health lines.' \
        "$BASE" "$LABEL" "$HOME/.claude/sessions/${TAB_NAME}.md")
    fi
    log "injecting without session context (no file yet)"
  fi
fi

# ── Inject ─────────────────────────────────────────────────────────────────────

if inject_prompt "$TAB_NAME" "$PROMPT"; then
  log "injected into tab=$TAB_NAME"
else
  log "skipped — $LABEL not in claude-projects.conf"
fi
