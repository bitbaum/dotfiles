#!/usr/bin/env bash
# keep-awake-acquire.sh — UserPromptSubmit hook.
#
# Prevents the machine from auto-suspending / idle-powering-off ONLY while Claude
# is actively working on a turn (same concept as a video player holding an idle
# inhibitor while playing). The lock is taken when a turn starts and dropped by
# keep-awake-release.sh when the turn ends, so when Claude is idle at the prompt
# the system behaves normally.
#
# Robustness: a detached "holder" process owns the systemd-inhibit lock. A built-in
# watchdog drops the lock if the Claude process dies (covers hard kills / closed
# terminal), so the lock can never leak. No-op if systemd-inhibit is unavailable.
# Always exits 0 — a power hook must never block or fail a turn.

command -v systemd-inhibit >/dev/null 2>&1 || exit 0

key="${ZELLIJ_PANE_ID:-$PPID}"
pidfile="/tmp/claude-inhibit-${key}.pid"

# Idempotent: if a holder is already alive for this session, leave it be.
if [ -f "$pidfile" ]; then
    oldpid=$(cat "$pidfile" 2>/dev/null)
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then exit 0; fi
fi

claude_pid=$PPID  # the Claude process that spawned this hook

# sleep:idle block = guaranteed (logind-enforced) no auto-suspend + screen stays
# awake, exactly while this holder lives. The watchdog loop exits when Claude dies.
systemd-inhibit --what=sleep:idle --who=claude \
    --why="Claude working (turn in progress)" --mode=block \
    bash -c 'while kill -0 '"$claude_pid"' 2>/dev/null; do sleep 8; done' \
    >/dev/null 2>&1 &
echo $! > "$pidfile"
exit 0
