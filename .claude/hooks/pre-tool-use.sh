#!/bin/bash
# Claude Code PreToolUse hook
# - Auto-approves almost everything silently
# - Only asks for genuinely destructive operations
# - Enter = Yes in the dialog

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

ALLOW='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
DENY='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Denied via dialog"}}'

# Read-only tools: no permission needed, pass through
case "$TOOL_NAME" in
  Read|Glob|Grep|WebFetch|WebSearch|ListMcpResourcesTool|ToolSearch|ExitPlanMode|AskUserQuestion)
    exit 0
    ;;
esac

# Bash: auto-approve safe commands, only ask for destructive ones
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

  DANGEROUS_PATTERN='(rm\s+-[rRfF]{1,3}\b|git\s+(push\s+[^|&;]*(-f|--force)|reset\s+--hard|clean\s+-[fdxX])|DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE|dd\s+if=|mkfs\b|:\(\)\{.*\}|chmod\s+-R\s+777)'

  if echo "$COMMAND" | grep -qEi "$DANGEROUS_PATTERN"; then
    _DBUS="unix:path=/run/user/$(id -u)/bus"
    DISPLAY="${DISPLAY:-:1}" DBUS_SESSION_BUS_ADDRESS="$_DBUS" \
      paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga 2>/dev/null &

    # Write command to temp file so Python receives it safely (no quoting issues)
    TMPFILE=$(mktemp /tmp/claude-confirm-XXXXXX)
    echo "$COMMAND" > "$TMPFILE"

    CHOICE=$(DISPLAY="${DISPLAY:-:1}" DBUS_SESSION_BUS_ADDRESS="$_DBUS" \
      python3 ~/.claude/hooks/claude-popup.py confirm "Bash" "$TMPFILE" 2>/dev/null)
    rm -f "$TMPFILE"

    [ "$CHOICE" = "allow" ] && echo "$ALLOW" || echo "$DENY"
    exit 0
  fi

  echo "$ALLOW"
  exit 0
fi

# Write, Edit, Task, and everything else: auto-approve
echo "$ALLOW"
exit 0
