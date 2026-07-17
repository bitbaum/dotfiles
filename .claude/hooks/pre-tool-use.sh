#!/bin/bash
# Claude Code PreToolUse hook
# - Auto-approves everything (user policy 2026-06-12: "I allow you everything,
#   I want automatic development")
# - Destructive-looking commands are still ALLOWED, but get an audible ping and
#   an audit line in ~/.claude/hooks/dangerous-commands.log
#
# History: this hook used to pop a PyQt confirm dialog via
# ~/dev/cockpit/scripts/beacon.py for rm -rf / force-push / DROP TABLE etc.
# That script was deleted when the repo became fleetcrown and the beacon popup
# was removed from the product (commit 2391c6f), so the dialog could never
# render — the empty result was treated as "deny", and every rm-containing
# command was silently rejected with the misleading reason "Denied via dialog".
# Diagnosed 2026-06-12; the dialog branch is gone, the audit trail remains.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

ALLOW='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'

# Read-only tools: no permission needed, pass through
case "$TOOL_NAME" in
  Read|Glob|Grep|WebFetch|WebSearch|ListMcpResourcesTool|ToolSearch|ExitPlanMode|AskUserQuestion)
    exit 0
    ;;
esac

# Bash: allow everything; log + ping on destructive-looking patterns so there
# is still a human-auditable trail of the risky ones.
if [ "$TOOL_NAME" = "Bash" ]; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

  DANGEROUS_PATTERN='(rm\s+-[rRfF]{1,3}\b|git\s+(push\s+[^|&;]*(-f|--force)|reset\s+--hard|clean\s+-[fdxX])|DROP\s+(TABLE|DATABASE|SCHEMA)|TRUNCATE\s+TABLE|dd\s+if=|mkfs\b|:\(\)\{.*\}|chmod\s+-R\s+777)'

  if echo "$COMMAND" | grep -qEi "$DANGEROUS_PATTERN"; then
    printf '%s\t%s\n' "$(date -Iseconds)" "$COMMAND" >> ~/.claude/hooks/dangerous-commands.log
    _DBUS="unix:path=/run/user/$(id -u)/bus"
    DISPLAY="${DISPLAY:-:1}" DBUS_SESSION_BUS_ADDRESS="$_DBUS" \
      paplay /usr/share/sounds/freedesktop/stereo/dialog-warning.oga 2>/dev/null &
  fi

  echo "$ALLOW"
  exit 0
fi

# Write, Edit, Task, and everything else: auto-approve
echo "$ALLOW"
exit 0
