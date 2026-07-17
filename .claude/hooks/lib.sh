#!/bin/bash
# Compatibility shim. The hook runtime now lives in Cockpit.
# Source this file from legacy hooks if they still expect ~/.claude/hooks/lib.sh.

# shellcheck source=/dev/null
source /home/g/dev/cockpit/scripts/agent-hook-lib.sh
