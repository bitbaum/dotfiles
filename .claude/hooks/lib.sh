#!/bin/bash
# Shared utilities for Claude Code hooks.
# Source this file — do not execute directly.

_CONF="${CLAUDE_PROJECTS_CONF:-$HOME/.config/claude-projects.conf}"
_PROMPTS="${CLAUDE_PROMPTS:-$HOME/.config/claude-prompts.json}"
_DBUS="unix:path=/run/user/$(id -u)/bus"

# resolve_tab <cwd>
# Sets TAB_NAME to the exact Zellij tab name for the calling Claude process.
#
# Strategy 1 (primary) — process-tree via ZELLIJ_PANE_ID:
#   Walk: stop/notification hook ($$) → claude ($PPID) → shell (grandparent).
#   Read ZELLIJ_PANE_ID from the shell's /proc environ.
#   Collect all terminal-pane shell PIDs under the Zellij server, sort by pane ID.
#   The sorted index of our pane ID = 1-based position in query-tab-names output.
#   This correctly handles multiple tabs sharing the same CWD and renamed tabs.
#
# Strategy 2 (fallback) — CWD exact match from conf:
#   Used only when the process-tree walk fails (e.g., running outside Zellij).
#   Exact name match only — no starts-with fuzzy matching, which causes
#   "Cockpit" to accidentally resolve to "Cockpit Openclaw" instead of the
#   intended tab. Ambiguous (multiple conf entries for same CWD with different
#   tab names) → TAB_NAME left empty, inject is skipped.
resolve_tab() {
  TAB_NAME=""
  local cwd
  cwd=$(realpath "$1" 2>/dev/null)

  local actual_tabs
  actual_tabs=$(zellij action query-tab-names 2>/dev/null)
  [ -z "$actual_tabs" ] && return

  # ── Strategy 1: ZELLIJ_PANE_ID → sorted index → tab name ───────────────────
  local shell_pid zellij_pid our_pane_id
  shell_pid=$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')
  if [ -n "$shell_pid" ]; then
    zellij_pid=$(ps -o ppid= -p "$shell_pid" 2>/dev/null | tr -d ' ')
    our_pane_id=$(tr '\0' '\n' < /proc/"$shell_pid"/environ 2>/dev/null \
                  | grep '^ZELLIJ_PANE_ID=' | cut -d= -f2)

    if [ -n "$our_pane_id" ] && [ -n "$zellij_pid" ]; then
      # Build sorted list of all terminal pane IDs under the Zellij server.
      # These are created in tab-open order, so sorted index = tab position.
      local tab_idx
      tab_idx=$(
        ps -o pid= --ppid "$zellij_pid" 2>/dev/null | while read -r p; do
          local pid_pane
          pid_pane=$(tr '\0' '\n' < /proc/"$p"/environ 2>/dev/null \
                     | grep '^ZELLIJ_PANE_ID=' | cut -d= -f2)
          [ -n "$pid_pane" ] && printf '%s\n' "$pid_pane"
        done | sort -n | grep -n "^${our_pane_id}$" | cut -d: -f1
      )

      if [ -n "$tab_idx" ]; then
        local name
        name=$(printf '%s\n' "$actual_tabs" | sed -n "${tab_idx}p")
        if [ -n "$name" ]; then
          TAB_NAME="$name"
          return
        fi
      fi
    fi
  fi

  # ── Strategy 2: CWD exact match from conf (fallback) ────────────────────────
  [ -z "$cwd" ] && return
  [ -f "$_CONF" ] || return

  local exact_count=0 exact_match="" sw_count=0 sw_match=""
  while IFS='|' read -r tab dir; do
    [[ "$tab" =~ ^#.*$ || -z "$tab" ]] && continue
    local rdir
    rdir=$(realpath "$dir" 2>/dev/null) || continue
    [ "$rdir" != "$cwd" ] && continue

    local tab_lower="${tab,,}"
    # Exact match against actual tab names (case-insensitive)
    local actual
    actual=$(printf '%s\n' "$actual_tabs" | while IFS= read -r t; do
      [ "${t,,}" = "$tab_lower" ] && printf '%s' "$t" && break
    done)
    if [ -n "$actual" ]; then
      exact_count=$(( exact_count + 1 ))
      exact_match="$actual"
      continue
    fi
    # Count starts-with matches — only safe when there is exactly one
    local sw
    sw=$(printf '%s\n' "$actual_tabs" | while IFS= read -r t; do
      [[ "${t,,}" == "${tab_lower} "* ]] && printf '%s' "$t" && break
    done)
    if [ -n "$sw" ]; then
      sw_count=$(( sw_count + 1 ))
      sw_match="$sw"
    fi
  done < "$_CONF"

  if [ "$exact_count" -eq 1 ]; then
    TAB_NAME="$exact_match"
  elif [ "$exact_count" -eq 0 ] && [ "$sw_count" -eq 1 ]; then
    TAB_NAME="$sw_match"
  fi
  # exact_count > 1 or sw_count > 1: ambiguous — leave TAB_NAME="" so inject_prompt refuses
}

# get_prompt <key>
# Prints the prompt text for <key> from claude-prompts.json (array format).
get_prompt() {
  jq -r --arg k "$1" '.[] | select(.key == $k) | .prompt' "$_PROMPTS" 2>/dev/null
}

# inject_prompt <tab_name> <prompt>
# Switches to the Zellij tab, writes the prompt, then sends Enter.
# Returns 1 (and does nothing) if tab_name is empty — never injects blind.
inject_prompt() {
  local tab="$1"
  local prompt="$2"
  [ -z "$tab" ] && return 1  # no confirmed tab → refuse to inject
  zellij action go-to-tab-name "$tab" 2>/dev/null
  sleep 0.3
  zellij action write-chars "$prompt" 2>/dev/null
  sleep 0.1
  zellij action write 13 2>/dev/null  # byte 13 = CR (what Enter sends in raw-mode TUIs)
}

# play_sound <name>
play_sound() {
  DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS="$_DBUS" \
    paplay "/usr/share/sounds/freedesktop/stereo/$1.oga" 2>/dev/null &
}
