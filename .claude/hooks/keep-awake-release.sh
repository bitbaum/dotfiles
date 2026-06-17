#!/usr/bin/env bash
# keep-awake-release.sh — Stop hook.
#
# Drops the power inhibitor taken by keep-awake-acquire.sh when the turn ends, so
# the machine returns to normal suspend behavior while Claude sits idle at the
# prompt. Always exits 0.

key="${ZELLIJ_PANE_ID:-$PPID}"
pidfile="/tmp/claude-inhibit-${key}.pid"
[ -f "$pidfile" ] || exit 0

pid=$(cat "$pidfile" 2>/dev/null)
if [ -n "$pid" ]; then
    pkill -TERM -P "$pid" 2>/dev/null   # stop the watchdog child loop
    kill -TERM "$pid" 2>/dev/null       # stop systemd-inhibit -> releases the lock
fi
rm -f "$pidfile"
exit 0
