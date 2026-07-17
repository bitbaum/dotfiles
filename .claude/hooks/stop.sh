#!/usr/bin/env bash
# No-op as of 2026-06-11 — part of killing-the-bash-daemon migration.
# The previous content exec'd ~/.local/share/fleetcrown-beacon/agent-hook-bridge.sh
# which is the bash bridge being retired. Fleet Runner now triggers dispatch
# via home/watcher.ts → notifyOnIdle (see Session 2 of the migration plan at
# /home/g/.claude/plans/structured-baking-kazoo.md).
# Backup of the original is at stop.sh.backup-2026-06-11.
exit 0
