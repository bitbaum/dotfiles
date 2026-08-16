#!/usr/bin/env bash
#
# Executes the REAL auto-merge-sweep.sh against a fake `gh` on PATH.
#
# Ported from evig, which was the only repo in the fleet that had tests for its
# sweep — and they were about to be deleted along with its copy of the script.
# That would have been the worst possible trade: centralising the code while
# throwing away the only evidence it behaves. The tests are as much a shared
# asset as the script, so they moved here with it.
#
# This tests SHIPPED CONTROL FLOW, not a description of it. A stubbed
# re-implementation of the guard would pass happily while the real script
# deadlocks — which is exactly what happened on 2026-08-07, when an Actions
# incident left main `failure` with no failed job and the sweep refused every
# merge for ~14 hours while still exiting 0 and looking healthy.
#
# The sweep must ALWAYS exit 0: it is a scheduled janitor, not a gate. A
# non-zero exit means the fake `gh` hit an unhandled call shape, which would
# make every assertion below vacuous — so that is checked first, every time.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SWEEP="$HERE/auto-merge-sweep.sh"
PASS=0
FAIL=0

ok() { printf '  ✓ %s\n' "$1"; PASS=$((PASS + 1)); }
no() { printf '  ✗ %s\n' "$1"; FAIL=$((FAIL + 1)); }

# run_sweep <conclusion> <failed-steps> <run-attempt>
# Emits the sweep's combined output; records gh calls in $GH_LOG.
run_sweep() {
  local conclusion="$1" failed_steps="${2:-}" attempt="${3:-1}"
  local dir; dir="$(mktemp -d)"
  GH_LOG="$dir/gh-calls.log"
  : > "$GH_LOG"

  cat > "$dir/gh" <<FAKE
#!/usr/bin/env bash
ARGS="\$*"
echo "\$ARGS" >> "$GH_LOG"
case "\$ARGS" in
  *"/commits/"*)                    echo "basesha000000" ;;
  "run list"*)                      printf '%s\n' '{"databaseId":42,"status":"completed","conclusion":"$conclusion","headSha":"basesha000000"}' ;;
  *"/actions/runs/"*"/jobs"*)       printf '%s\n' '$failed_steps' ;;
  "run rerun"*)                     echo "rerun dispatched" ;;
  *"/actions/runs/"*)               printf '%s\n' '$attempt' ;;
  "run view"*)                      printf '%s\n' 'Some Red Job' ;;
  "pr list"*)                       echo "[]" ;;
  "workflow run"*)                  echo "dispatched" ;;
  *) echo "UNHANDLED gh call: \$ARGS" >&2; exit 1 ;;
esac
FAKE
  chmod +x "$dir/gh"

  local out status
  out=$(PATH="$dir:$PATH" GH_REPO=maonakamoto/fixture BASE_BRANCH=main \
        bash "$SWEEP" 2>&1)
  status=$?
  SWEEP_OUT="$out"
  if [ "$status" -ne 0 ]; then
    no "sweep exited $status — the fake gh hit an unhandled call shape, so every assertion would be vacuous"
    printf '%s\n' "$out" | sed 's/^/      /' | tail -5
    return 1
  fi
  return 0
}

# `grep -c` PRINTS 0 and also EXITS 1 when there is no match, so the obvious
# `|| echo 0` appends a second zero and every numeric comparison then dies with
# "integer expected". Let grep's own output stand.
reruns() { grep -c '^run rerun' "$GH_LOG" 2>/dev/null; }

echo "auto-merge sweep — base branch guard"

# 1. A cancelled base run is NOT a verdict about the code. Treating it as one
#    strands the queue, and only a merge can produce a new base run — so the
#    guard blocks the very thing that would clear it.
if run_sweep cancelled '' 1; then
  [ "$(reruns)" -ge 1 ] \
    && ok 're-runs a CANCELLED base run instead of deadlocking behind it' \
    || no 're-runs a CANCELLED base run instead of deadlocking behind it'
fi

# 2. A run that failed inside GitHub's own "Set up job" never executed our code.
if run_sweep failure 'Set up job' 1; then
  [ "$(reruns)" -ge 1 ] \
    && ok 're-runs a base run that FAILED before executing any of our code' \
    || no 're-runs a base run that FAILED before executing any of our code'
fi

# 3. A genuine failure IS a verdict. It must block, and must NOT be re-run —
#    retrying real failures is how a broken base gets merged onto anyway.
if run_sweep failure 'Run tests' 1; then
  if [ "$(reruns)" -eq 0 ]; then
    ok 'refuses a genuinely broken base, and does NOT re-run it'
  else
    no 'refuses a genuinely broken base, and does NOT re-run it'
  fi
fi

# 4. Jobs API returning nothing must not be read as "infra failure" — absence of
#    evidence is not evidence of an incident.
if run_sweep failure '' 1; then
  [ "$(reruns)" -eq 0 ] \
    && ok 'does not re-run a real failure even when the jobs API says nothing' \
    || no 'does not re-run a real failure even when the jobs API says nothing'
fi

# 5. Bounded. An endlessly-failing run must not become an infinite re-run loop
#    billing Actions minutes forever.
if run_sweep cancelled '' 3; then
  if [ "$(reruns)" -eq 0 ]; then
    ok 'stops retrying once the run hits the attempt cap'
  else
    no 'stops retrying once the run hits the attempt cap'
  fi
fi

# 6. The happy path still reaches the PR loop — a guard that never lets anything
#    through is just an outage with better manners.
if run_sweep success '' 1; then
  case "$SWEEP_OUT" in
    *"no open PRs"*) ok 'proceeds to the PR loop when the base is green' ;;
    *) no "proceeds to the PR loop when the base is green (got: $(printf '%s' "$SWEEP_OUT" | tail -1))" ;;
  esac
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
