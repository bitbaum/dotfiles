#!/bin/bash
# Tests for the PreToolUse hook's leading-cd guard.
#
# Why this exists: on 2026-09-20 a session at ~/ ran `cd ~/.claude/hooks`
# (a symlink into this repo) in the same second the background daemon was
# spawned. The daemon recorded the shell's live cwd as the spawner's location,
# and every background session minted afterwards was re-homed to
# ~/dev/dotfiles/.claude/hooks -- wrong project in the UI, wrong transcript
# directory, and wrong MEMORY SILO, which is the one that costs real work.
#
# The guard must be exact in both directions. Blocking a remote `ssh host
# "cd /opt/app && ..."` or a heredoc body would break the fleet; letting a bare
# `cd` through re-opens the leak. Both directions are asserted here.

set -uo pipefail

HOOK="${1:-$(dirname "$0")/../pre-tool-use.sh}"
[ -f "$HOOK" ] || { echo "hook not found: $HOOK" >&2; exit 1; }

fail=0

run() {  # $1 = expected BLOCK|ALLOW, $2 = command string
  local json rc got
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$2")
  printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1
  rc=$?
  if [ "$rc" = "2" ]; then got=BLOCK; else got=ALLOW; fi
  if [ "$got" = "$1" ]; then
    echo "  ok   $got  ${2%%$'\n'*}"
  else
    echo "  FAIL expected=$1 got=$got (rc=$rc)  ${2%%$'\n'*}" >&2
    fail=1
  fi
}

echo "leading cd must be blocked:"
run BLOCK 'cd /home/g/dev/loki && ls'
run BLOCK '   cd /tmp'
run BLOCK 'cd'
run BLOCK 'cd -'
run BLOCK 'pushd /tmp && ls'
run BLOCK 'ls && cd /tmp'
run BLOCK 'echo hi; cd /tmp'

echo "everything else must pass through:"
run ALLOW '(cd /home/g/dev/loki && ls)'          # subshell: cannot escape
run ALLOW 'x=$(cd /tmp && pwd); echo $x'         # command substitution: same
run ALLOW 'ssh ubuntu@1.2.3.4 "cd /opt/app && ls"'  # remote directory
run ALLOW "$(printf 'ssh host <<EOF\ncd /opt/app\nEOF')"  # heredoc body
run ALLOW 'cdk deploy --all'                     # word starting with "cd"
run ALLOW 'grep -rn "cd " .'
run ALLOW 'echo "cd /tmp"'
run ALLOW 'ls -la /home/g/dev/dotfiles'

echo "destructive commands are still allowed (audited, never blocked):"
run ALLOW 'rm -rf /tmp/nothing-here-xyz'

if [ "$fail" -eq 0 ]; then
  echo "pre-tool-use guard: ok"
else
  echo "pre-tool-use guard: FAILED" >&2
fi
exit "$fail"
