#!/bin/bash
# Shared utilities for Claude Code hooks.
# Source this file — do not execute directly.

_CONF="${CLAUDE_PROJECTS_CONF:-$HOME/.config/claude-projects.conf}"
_PROMPTS="${CLAUDE_PROMPTS:-$HOME/.config/claude-prompts.json}"
_DBUS="unix:path=/run/user/$(id -u)/bus"

# resolve_tab <cwd>
# Sets TAB_NAME to the exact Zellij tab name for the given directory.
# Matches case-insensitively against conf, then resolves to the actual
# cased name from Zellij so go-to-tab-name always gets an exact match.
resolve_tab() {
  TAB_NAME=""
  [ -f "$_CONF" ] || return
  local cwd
  cwd=$(realpath "$1" 2>/dev/null) || return

  # Snapshot of actual open tab names (used for exact-case resolution)
  local actual_tabs
  actual_tabs=$(zellij action query-tab-names 2>/dev/null)

  while IFS='|' read -r tab dir; do
    [[ "$tab" =~ ^#.*$ || -z "$tab" ]] && continue
    local rdir
    rdir=$(realpath "$dir" 2>/dev/null) || continue
    if [ "$rdir" = "$cwd" ]; then
      # Find the real tab name with case-insensitive lookup
      local tab_lower="${tab,,}"
      local actual
      actual=$(printf '%s\n' "$actual_tabs" | while IFS= read -r t; do
        [ "${t,,}" = "$tab_lower" ] && printf '%s' "$t" && break
      done)
      TAB_NAME="${actual:-$tab}"
      return
    fi
  done < "$_CONF"
}

# get_prompt <key>
# Prints the prompt text for <key> from claude-prompts.json.
get_prompt() {
  jq -r --arg key "$1" '.[$key] // empty' "$_PROMPTS" 2>/dev/null
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
