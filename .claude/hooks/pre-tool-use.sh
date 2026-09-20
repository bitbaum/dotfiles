#!/bin/bash
# Claude Code PreToolUse hook
# - Auto-approves everything (user policy 2026-06-12: "I allow you everything,
#   I want automatic development")
# - Destructive-looking commands are still ALLOWED, but get an audible ping and
#   an audit line in ~/.claude/hooks/dangerous-commands.log
#
# History: this hook used to pop a PyQt confirm dialog via
# ~/dev/cockpit/scripts/beacon.py for rm -rf / force-push / DROP TABLE etc.
# That script was deleted when the repo became loki and the beacon popup
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

  # A leading `cd` buys nothing in this harness: the Bash tool resets the shell
  # back to the session's cwd after every call, so the directory never persists.
  # What it CAN do is leak. Claude Code samples the shell's live cwd when it
  # records a spawner's location, and on 2026-09-20 a `cd ~/.claude/hooks`
  # (a symlink into this repo) happened in the same second the background
  # daemon was spawned: every bg session minted afterwards was re-homed to
  # ~/dev/dotfiles/.claude/hooks and filed its transcript -- and therefore its
  # MEMORY SILO -- under the wrong project. A subshell cannot do this, because
  # it changes only its own cwd. So: absolute paths, or `(cd DIR && ...)`.
  # Only the FIRST line, and only an UNPARENTHESISED cd: a subshell `(cd ...)`
  # or `$(cd ...)` changes nothing outside itself, a heredoc body belongs to
  # some other machine or interpreter, and `ssh host "cd /opt && ..."` is a
  # remote directory. Blocking those would be a fleet-wide false positive.
  _FIRST=$(printf '%s' "$COMMAND" | head -n1 | sed 's/(cd/(SUBSHELL_CD/g')
  if printf '%s' "$_FIRST" | grep -qE '(^|&&|\|\||;)[[:space:]]*(cd|pushd)([[:space:]]|;|$)'; then
    echo "Leading 'cd' is blocked: the Bash tool resets the working directory after every call, so it gains you nothing, and a spawn landing in the same instant inherits it and re-homes background sessions to the wrong project (wrong transcript, wrong memory silo). Use absolute paths, the -C flag, or a subshell: (cd DIR && ...)" >&2
    exit 2
  fi

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
