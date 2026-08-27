#!/usr/bin/env bash
# No-op since 2026-08-27.
#
# This previously exec'd ~/.local/share/fleetcrown-beacon/agent-hook-bridge.sh,
# which has not existed since the bash bridge was retired — so every
# Notification event failed here. Dispatch on idle now belongs to FleetCrown's
# Fleet Runner (home/watcher.ts -> notifyOnIdle), not to this repo.
#
# Kept as a wired no-op rather than deleted so settings.json stays valid.
exit 0
