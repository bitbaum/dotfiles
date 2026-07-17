#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook for FleetCrown.
#
# Captures every prompt typed into a Claude terminal and POSTs it to the
# fleet server so the Activity page sees terminal work, not just dispatches
# routed through /api/inject. Always exits 0 — never blocks the user.
#
# Claude sends the hook event on stdin as JSON with at least:
#   { "prompt": "...", "cwd": "...", "session_id": "..." }
#
# Auth: Bearer FLEETCROWN_DAEMON_TOKEN (mirrored via daemon.env).

set +e   # never fail the user's prompt because logging is broken

# Load token from daemon env. Skip silently if not present.
for f in "${HOME}/.config/fleetcrown/daemon.env" "${HOME}/.config/cockpit/daemon.env"; do
  [ -f "$f" ] || continue
  set -a
  # shellcheck disable=SC1090
  . "$f"
  set +a
done

TOKEN="${FLEETCROWN_DAEMON_TOKEN:-${COCKPIT_DAEMON_TOKEN:-}}"
# Prefer the local systemd server when it's up — writes land in the same
# shared DB the Vercel deployment reads, and the local one always has the
# newest endpoints. Override with FLEET_CAPTURE_URL for headless / remote use.
BASE="${FLEET_CAPTURE_URL:-http://localhost:3000}"

if [ -z "$TOKEN" ]; then
  exit 0
fi

# Slurp Claude's JSON payload from stdin BEFORE backgrounding (background can't
# read the parent's stdin reliably). Pass through env to the worker so the
# heredoc-vs-stdin collision doesn't happen.
PAYLOAD="$(cat)"

# Fire-and-forget worker. Exits within 1.5s on the inner urlopen timeout, but
# we don't wait — the user's prompt must submit instantly.
FLEET_PAYLOAD="$PAYLOAD" FLEET_BASE="$BASE" FLEET_TOKEN="$TOKEN" nohup python3 -c '
import json, os, sys, urllib.request
base = os.environ["FLEET_BASE"]
token = os.environ["FLEET_TOKEN"]
try:
    payload = json.loads(os.environ["FLEET_PAYLOAD"])
except Exception:
    sys.exit(0)
prompt = (payload.get("prompt") or "").strip()
cwd = payload.get("cwd") or os.getcwd()
session_id = payload.get("session_id") or ""
if not prompt:
    sys.exit(0)
body = json.dumps({"prompt": prompt, "cwd": cwd, "sessionId": session_id}).encode("utf-8")
req = urllib.request.Request(
    f"{base}/api/activity/capture",
    data=body,
    method="POST",
    headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
)
try:
    urllib.request.urlopen(req, timeout=1.5).read()
except Exception:
    pass
' </dev/null >/dev/null 2>&1 &

disown
exit 0
