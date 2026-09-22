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


# --- unbounded wait loops -----------------------------------------------
#
# A polling loop with no deadline cannot report a problem, only hang. The case
# that produced this guard spun 26 minutes waiting for a MERGED pull request's
# headRefOid to change -- a field that freezes on merge, so the exit condition
# was impossible rather than slow.
#
# Both directions matter as much as they do for the cd guard: block the
# unbounded poll, but never a loop that is genuinely bounded, or the fleet's
# deploy waits all start failing.

echo "unbounded until/while + sleep must be blocked:"
run BLOCK 'until [ "$(gh pr view 860 --json headRefOid --jq .headRefOid)" = "50f9647a" ]; do sleep 10; done'
run BLOCK 'until curl -fsS https://loki.orangecat.ch/api/health | grep -q abc123; do sleep 45; done'
run BLOCK 'while ! gh run view 123 --json status --jq .status | grep -q completed; do sleep 30; done'
run BLOCK 'until pgrep -f "run verify" >/dev/null; do sleep 20; done; echo done'

echo "bounded or non-polling loops must be allowed:"
run ALLOW 'for i in $(seq 1 40); do s=$(gh pr view 1 --json state --jq .state); case "$s" in MERGED|CLOSED) break;; esac; sleep 15; done'
run ALLOW 'i=0; while [ $i -lt 20 ]; do i=$((i+1)); sleep 5; done'
run ALLOW 'timeout 300 bash -c "until curl -fsS http://x/health; do sleep 10; done"'
run ALLOW 'while read -r line; do echo "$line"; done < /etc/hosts'
run ALLOW 'until git diff --quiet; do break; done'
run ALLOW 'sleep 5'
run ALLOW 'gh pr checks 860 --repo bitbaum/loki --watch --fail-fast'


if [ "$fail" -eq 0 ]; then
  echo "pre-tool-use guard: ok"
else
  echo "pre-tool-use guard: FAILED" >&2
fi
exit "$fail"
