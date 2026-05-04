#!/bin/bash
# Shared utilities for Claude Code hooks.
# Source this file — do not execute directly.

_CONF="${CLAUDE_PROJECTS_CONF:-$HOME/.config/claude-projects.conf}"
_PROMPTS="${CLAUDE_PROMPTS:-$HOME/.config/claude-prompts.json}"
_DBUS="unix:path=/run/user/$(id -u)/bus"

# resolve_tab <cwd>
# Sets TAB_NAME to the exact Zellij tab name for the calling Claude process.
#
# Strategy 0 (fastest) — PID file:
#   The claude() bash wrapper writes /tmp/claude-tab-$$ before exec'ing claude.
#   Hook reads shell_pid = ps -o ppid= -p $PPID, then cat /tmp/claude-tab-$shell_pid.
#   Zero process-tree walking. Falls through to Strategy 1 if file is absent.
#
# Strategy 1 (primary) — CWD-group pane sort:
#   Walk: hook ($$) → claude ($PPID) → shell (grandparent).
#   Read ZELLIJ_PANE_ID from the shell's /proc environ.
#   Among all zellij-server children, keep only those whose /proc/PID/cwd
#   matches ours. Sort those pane IDs → our 1-based rank within the subgroup.
#   Collect conf-mapped tab names that exist in query-tab-names (in tab order).
#   The N-th matching tab = our tab.
#   Robust: unrelated shells dying/living don't affect the same-CWD subgroup,
#   so unnamed or extra tabs never offset the index.
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

  # ── Strategy 0: PID file written by claude() wrapper at launch time ──────────
  # The claude() bash function writes /tmp/claude-tab-$$ before exec'ing claude.
  # $$ in the shell = shell_pid here. This is the cheapest and most reliable path.
  local shell_pid
  shell_pid=$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')
  if [ -n "$shell_pid" ] && [ -f "/tmp/claude-tab-${shell_pid}" ]; then
    local s0_name
    s0_name=$(cat "/tmp/claude-tab-${shell_pid}" 2>/dev/null)
    if [ -n "$s0_name" ]; then
      TAB_NAME="$s0_name"
      return
    fi
  fi

  # ── Strategy 1: CWD-group pane sort → tab name ──────────────────────────────
  local zellij_pid our_pane_id
  if [ -n "$shell_pid" ] && [ -n "$cwd" ]; then
    zellij_pid=$(ps -o ppid= -p "$shell_pid" 2>/dev/null | tr -d ' ')
    our_pane_id=$(tr '\0' '\n' < /proc/"$shell_pid"/environ 2>/dev/null \
                  | grep '^ZELLIJ_PANE_ID=' | cut -d= -f2)

    if [ -n "$our_pane_id" ] && [ -n "$zellij_pid" ]; then
      # Rank our pane among shells sharing our CWD (unrelated shells excluded)
      local group_idx
      group_idx=$(
        ps -o pid= --ppid "$zellij_pid" 2>/dev/null | while read -r p; do
          local pid_pane pid_cwd
          pid_pane=$(tr '\0' '\n' < /proc/"$p"/environ 2>/dev/null \
                     | grep '^ZELLIJ_PANE_ID=' | cut -d= -f2)
          [ -z "$pid_pane" ] && continue
          pid_cwd=$(realpath "$(readlink /proc/"$p"/cwd 2>/dev/null)" 2>/dev/null)
          [ "$pid_cwd" = "$cwd" ] || continue
          printf '%s\n' "$pid_pane"
        done | sort -n | grep -n "^${our_pane_id}$" | cut -d: -f1
      )

      if [ -n "$group_idx" ]; then
        # Tabs in query-tab-names order that conf maps to our CWD
        local same_cwd_tabs
        same_cwd_tabs=$(
          printf '%s\n' "$actual_tabs" | while IFS= read -r t; do
            local t_lower="${t,,}" found=0
            while IFS='|' read -r ctab cdir; do
              [[ "$ctab" =~ ^#.*$ || -z "$ctab" ]] && continue
              [ "${ctab,,}" = "$t_lower" ] || continue
              local rdir
              rdir=$(realpath "$cdir" 2>/dev/null) || continue
              if [ "$rdir" = "$cwd" ]; then found=1; break; fi
            done < "$_CONF"
            [ "$found" -eq 1 ] && printf '%s\n' "$t"
          done
        )

        local name
        name=$(printf '%s\n' "$same_cwd_tabs" | sed -n "${group_idx}p")
        if [ -n "$name" ]; then
          TAB_NAME="$name"
          return
        fi
      fi

      # Strategy 1b: global pane-rank fallback.
      # Used when shell CWD ≠ project CWD (e.g., claude was launched from ~ not the project dir).
      # Each tab has exactly one shell process; their pane IDs sort in the same order as tab names.
      # Fragile if unrelated shells have died, but that can only happen when Strategy 1 also fails.
      local global_idx
      global_idx=$(
        ps -o pid= --ppid "$zellij_pid" 2>/dev/null | while read -r p; do
          local pid_pane
          pid_pane=$(tr '\0' '\n' < /proc/"$p"/environ 2>/dev/null \
                     | grep '^ZELLIJ_PANE_ID=' | cut -d= -f2)
          [ -z "$pid_pane" ] && continue
          printf '%s\n' "$pid_pane"
        done | sort -n | grep -n "^${our_pane_id}$" | cut -d: -f1
      )
      if [ -n "$global_idx" ]; then
        local name
        name=$(printf '%s\n' "$actual_tabs" | sed -n "${global_idx}p")
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
  else
    # All strategies failed (ambiguous or no match) — warn so the skip is visible in logs
    echo "claude-hook: could not resolve tab for cwd=$1 (exact=$exact_count sw=$sw_count) — skipping state write" >&2
  fi
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
  DISPLAY="${DISPLAY:-:1}" DBUS_SESSION_BUS_ADDRESS="$_DBUS" \
    paplay "/usr/share/sounds/freedesktop/stereo/$1.oga" 2>/dev/null &
}
