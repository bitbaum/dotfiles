#!/usr/bin/env bash
# What every agent is working on right now, and what each project has moved.
#
# ── WHY THIS EXISTS ──────────────────────────────────────────────────────────
# Eighteen sessions were running at once on 2026-09-09, across twelve projects,
# and none of them could see any of the others. CLAUDE.md already says to check
# `~/.claude/sessions/*.json` before wide-blast-radius work, but that registry
# holds a one-line NAME per session — it says a session is called "orangecat
# username immutability investigation", not that it has shipped four PRs or
# found something the session next door is about to trip over.
#
# The cost is concrete and was paid repeatedly: the deploy gate races its own CI
# in every repo that uses the shared workflow, and each agent rediscovers that
# alone. Two sessions in the same repo pick the same migration timestamp.
# A lesson written into one project's memory is unreadable from another, because
# memory is loaded from the session's CWD.
#
# ── WHAT IT DOES NOT DO ──────────────────────────────────────────────────────
# It does not coordinate anything, hold a lock, or tell anyone to stop. It is a
# read-only picture, cheap enough to run at the start of a session. Anything
# that claims two agents cannot collide would be a claim this cannot support:
# worktrees already isolate files, and what collides is intent, which only a
# person reading this can judge.
#
# Usage:
#   fleet-status.sh              sessions + local git activity (no network)
#   fleet-status.sh --prs        also ask GitHub for open PRs (slower)
#   fleet-status.sh --days 3     widen the activity window (default 1)

set -uo pipefail

SESSIONS_DIR="${HOME}/.claude/sessions"
DEV_DIR="${HOME}/dev"
DAYS=1
WANT_PRS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --prs) WANT_PRS=1 ;;
    --days) DAYS="${2:-1}"; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
dim()  { printf '\033[2m%s\033[0m\n' "$1"; }

# ── Sessions ─────────────────────────────────────────────────────────────────
# `cwd` is the truth about which project a session is in — including worktrees,
# where the path is <repo>/.claude/worktrees/<name> and the project is the repo.
project_of() {
  local cwd="$1"
  case "$cwd" in
    "${DEV_DIR}"/*)
      local rest="${cwd#"${DEV_DIR}"/}"
      printf '%s' "${rest%%/*}"
      ;;
    "${HOME}") printf '(home)' ;;
    *) printf '%s' "$(basename "$cwd")" ;;
  esac
}

bold "AGENTS RUNNING"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

for f in "$SESSIONS_DIR"/*.json; do
  [ -e "$f" ] || continue
  # A session file outlives a crash, so status is what makes it current.
  jq -r 'select(.status != null)
         | [.cwd, (.status // "?"), (.kind // "?"), (.name // "unnamed")]
         | @tsv' "$f" 2>/dev/null
done > "$tmp"

if [ ! -s "$tmp" ]; then
  dim "  none"
else
  # Sorted by project FIRST, then printed in one pass. An awk associative array
  # plus a trailing `sort` looked equivalent and was not: it reordered the
  # output lines, so every session ended up under somebody else's heading.
  while IFS=$'\t' read -r cwd status kind name; do
    printf '%s\t%s\t%s\t%s\n' "$(project_of "$cwd")" "$status" "$kind" "$name"
  done < "$tmp" | sort -t$'\t' -k1,1 -k2,2 | awk -F'\t' '
    $1 != prev { if (prev != "") printf "\n"; printf "  %s\n", $1; prev = $1 }
    { printf "      %-6s %-12s %s\n", $2, $3, $4 }
  '
fi

# ── Local git activity ───────────────────────────────────────────────────────
echo
bold "MOVED IN THE LAST ${DAYS} DAY(S)"

found_any=0
for repo in "$DEV_DIR"/*/; do
  [ -d "${repo}.git" ] || continue
  name="$(basename "$repo")"

  commits="$(git -C "$repo" log --oneline --since="${DAYS} days ago" 2>/dev/null | wc -l | tr -d ' ')"
  [ "${commits:-0}" -eq 0 ] && continue
  found_any=1

  branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  head="$(git -C "$repo" log --oneline -1 2>/dev/null | cut -c1-72)"
  dirty="$(git -C "$repo" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  # Worktrees are where parallel agents actually work, so count them.
  trees="$(git -C "$repo" worktree list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"

  printf '  %-18s %-14s %3s commits' "$name" "$branch" "$commits"
  [ "${dirty:-0}" -gt 0 ] && printf '  %s dirty' "$dirty"
  [ "${trees:-0}" -gt 0 ] && printf '  %s worktree(s)' "$trees"
  printf '\n'
  dim "      $head"

  if [ "$WANT_PRS" -eq 1 ]; then
    prs="$(gh pr list --repo "$(git -C "$repo" remote get-url origin 2>/dev/null \
            | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#')" \
            --state open --json number,title --jq '.[] | "      #\(.number) \(.title)"' 2>/dev/null)"
    [ -n "$prs" ] && printf '%s\n' "$prs"
  fi
done

[ "$found_any" -eq 0 ] && dim "  nothing"

echo
dim "Memory is loaded per session CWD: ~/.claude/projects/<slug>/memory/."
dim "A lesson written in one project is invisible from another — put it where"
dim "the agents who need it will be sitting, and say so in that project's index."
