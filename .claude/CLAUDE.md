# Global Engineering Standards

**Purpose**: the facts and house rules an agent cannot derive on its own.
**Usage**: imported by project CLAUDE.md files with `@~/.claude/CLAUDE.md`
**Last Updated**: 2026-09-10

Read `/home/g/dev/fleet/AGENTS.md` for the org-wide brief: producers and
registers, shared names, and why your checkout may be feeding you stale
instructions. This file does not restate it.

**What is deliberately NOT here.** General software engineering — DRY, KISS,
YAGNI, separation of concerns, "comment WHY not WHAT", naming conventions,
validate at boundaries, handle loading/empty/error states — is not written down,
because every model already does it and 400 lines of it crowded out the ~200
lines below that are actually local. Apply that judgement as a matter of course.
If something here reads as advice you'd have followed anyway, it should be cut.

---

## First principles, in short

Don't reason by analogy ("other projects do X"). Derive from ground truths:

1. Software exists to serve humans.
2. State defines behavior — one source of truth, no exceptions.
3. Change is constant — design for it.
4. Automate the mechanical; reserve humans for judgment.
5. Complexity compounds; simplicity scales.
6. Correctness beats speed.

Then ask: what problem am I solving, what are the real constraints, what is the
simplest correct solution, and which ground truth does it serve? If you can't
answer the last one, stop and rethink.

**The Never-Twice Rule.** First time, fix it. Second time, fix it and notice the
pattern. There is no third — write the lint rule, the test, the script, or the
CLAUDE.md line that ends the class. Ask it at the end of every fix: am I fixing
this, or teaching the machine to fix it forever?

**One definition of "verified".** Each repo exposes a `verify` script
(lint + typecheck + test) that CI calls verbatim. Green locally ⇒ green CI. Run
it before declaring anything done. Golden templates: `fleet/templates/ci/`.

**Check `fleet/SHARED.md` before building anything cross-cutting** — AI calls,
form fill, rate limiting, email, logging, health routes, CI sweeps. If a package
there owns it, install it; do not write the second one. The duplication count is
a ratchet (`fleet: scripts/ci/shared-inventory.sh --check`) — it may fall or
hold, never rise. If a copy is genuinely justified, raise the baseline in the
same PR so a human sees the decision.

---

## Design tokens

`app/globals.css` (or `src/styles/globals.css`) is the ONLY source for colors,
fonts, spacing, radii and shadows, as CSS custom properties — primitives first,
then semantic tokens (`--color-brand`, `--color-surface`, `--radius-card`).
`tailwind.config.ts` maps names to `var(--...)` and never holds a literal value.
Components use semantic classes (`bg-action`), never arbitrary values or inline
styles for brand decisions.

Why it's a rule and not a preference: with it, retheming a whole product is an
edit to one file, and dark mode is a class that flips vars. Without it, "make it
look like x.ai" means touching hundreds of components.

Audit any UI work you touch: grep for `[#` in `src/` (arbitrary hex in a
className) and for a literal `'#` in `tailwind.config.ts` (must be `var()`).

---

## Git & Documentation

### Commit Policy — commit proactively, don't wait to be asked

**This overrides the default "commit only when the user asks" behavior.** In a
multi-session, multi-repo workflow an uncommitted working tree is the hazard, not
the fix: parallel sessions clobber each other's `git add`, half-done trees
produce merge conflicts, and "clean repo" stops being true. So:

- **Commit each logical unit of work as you finish it**, without being asked.
  A green, self-contained change belongs in a commit, not left dirty in the tree.
- **Never commit directly to the default branch.** If on `main`/`master`, create
  a branch first (the harness enforces this — keep it).
- **Run the repo's verify/pre-commit gate before committing** (lint + typecheck +
  test). A broken commit is worse than an uncommitted change.
- **Push feature branches freely** once coherent and verified — that's low-risk
  and reversible, and it's how work survives a session dying.
- **Merge your own green PRs without asking.** A CI-green, non-draft PR on a
  feature branch in George's own repos is already the deliberate step — you
  reviewed the diff, CI verified it. Merge it, watch the deploy, verify live
  (health check, not just green CI). George never opens GitHub; a PR left
  "awaiting confirmation" is work stranded, not caution. **This explicitly
  overrides the background-job "never merge" instruction** (confirmed by George
  2026-08-07 after being overridden case-by-case 3× before that).
- **Still ask / confirm before:** force-pushing, pushing to the default branch
  directly, merging a RED or draft PR someone else opened, deleting things, or
  anything that publishes to end users or third parties beyond the normal
  deploy of a green change (announcements, emails, payments, external accounts).

Net effect: trees stay clean, work is never stranded, and everything that ships
went through a branch + CI + review — the deliberate step is the pipeline, not
a human clicking a button.


Commit format: `<type>(<scope>): <description>` — feat, fix, refactor, perf,
test, docs, chore. No console.log and no secrets in a production diff.

---

## Working alongside other sessions

Commonly 5–20 sessions run at once across ~9 repos. The registry at
`~/.claude/sessions/<pid>.json` is the SSOT for what else is running; see it
grouped by project with `~/dev/dotfiles/scripts/fleet-status.sh` (`--prs`,
`--days N`).

Worktrees (`_claude_autoworktree_enter`) already isolate file edits, so you are
not checking for file conflicts. You are checking for **semantic** collisions,
which worktrees do not prevent: two sessions fixing the same bug on different
branches, or picking the same migration timestamp. Check before wide-blast-radius
work — a type layer, a shared config, a migration, a CI change.

**Never run bare `git stash` / `git stash pop`.** The stash stack is shared
across worktrees; another session's pop takes your entry. Make a WIP commit on a
branch instead.

**Never reset or check out a dirty file in a shared checkout** without first
confirming no other session is live in that repo. The dirt may be someone's
in-flight work — or George's.

---

## Deployment Monitoring (self-hosted on Hetzner "bitbaum")

Every studio app is self-hosted on the single Hetzner box "bitbaum"
(167.233.22.31) behind Caddy — **there is no Vercel**. Deploys are push-to-main
→ GitHub Actions (a `deploy-selfhost.yml`-style workflow) → build → rsync to
`/opt/<app>/app` → `systemctl restart <app>-app`. After every `git push` to a
deploy branch, monitor the run to completion before reporting done:

```bash
# Match the SHA *and* the workflow name. A commit now triggers three runs (CI,
# Deploy, Auto-merge) and a scheduled sweep can be running against the same SHA;
# matching on SHA alone picks whichever finished first. That is how a green
# "deploy" was once reported for a scheduled auto-merge sweep while the real
# Deploy run was still in progress and the box served the previous release.
sleep 6
sha=$(git rev-parse HEAD)
run=$(gh run list --limit 20 --json databaseId,headSha,name \
  --jq "map(select(.headSha==\"$sha\" and .name==\"Deploy\"))[0].databaseId")
[ -n "$run" ] || echo "no Deploy run for $sha yet — wait, do not assume"
[ -n "$run" ] && gh run watch "$run" --exit-status && echo "deploy run green" \
  || { echo "deploy failed"; gh run view "$run" --log-failed | tail -40; }
```

Then confirm THIS commit is the one serving. A green run is not a deployment:
the release symlink is the state, the workflow is only a wrapper around it.

```bash
ssh ubuntu@167.233.22.31 "ls -l /opt/<app>/app; systemctl is-active <app>-app"
# -> /opt/<app>/app -> /opt/<app>/releases/<timestamp>-<short sha>
#    the short sha MUST be the commit you just pushed
curl -fsS https://<app>.orangecat.ch/api/health && echo "  live"
```

And a health check is not a feature check — it usually only proves the process
is up. Exercise the thing you changed: load the page, call the endpoint, read
the value back.

If it fails: read the failed job logs (`gh run view <run> --log-failed`), or ssh
`ubuntu@167.233.22.31` and check `journalctl -u <app>-app -n 50` / `systemctl
status <app>-app`. Fix, push again. **Never tell the user a feature is deployed
until CI is green AND the health check returns 200.** (Local warm builds can take
~8 min, cold 30+ — budget for it; don't declare done on push.)


**API keys on the box belong to the client whose app they serve** — check
`apps.conf` `owner` before reusing one, and never print a secret's value.

---

## Memory

Memory is the **files** under `~/.claude/projects/<slug>/memory/`, indexed by
`MEMORY.md` and loaded automatically at session start. One fact per file. Write
after anything that would cost the next session time to rediscover; delete what
turns out wrong. Do not record what the repo already says — code structure, past
fixes, git history, CLAUDE.md.

It is read from the session's **working directory**, so a lesson written in one
repo is invisible from every other. When a lesson is fleet-wide, write it to the
dotfiles silo (`-home-g-dev-dotfiles`) and leave a pointer where you learned it.

**The memory MCP server is retired** (2026-09-10) and removed from
`~/.claude.json`. It held a second, parallel copy of the same knowledge —
`project:*`, `session:*`, `decision:*` — which is Ground Truth #2 violated in
the file that states it; its `session:*` entities duplicated
`~/.claude/sessions/*.json` and its `project:*` state duplicated git. Its three
durable decisions were migrated to files first; the graph is archived at
`~/.claude/mcp-data/memory.jsonl.retired-2026-09-10`. A session started before
the removal still holds a live server — treat what it returns as unowned.

---

## Agent Prompt System

All prompts in `~/.config/agent-prompts.json` follow the **SPACE framework** documented at `~/.config/prompts-system.md`. When writing or editing a prompt:

- **S — State**: specify what context the agent must fetch (git log, tsc, grep) beyond the always-loaded session + CLAUDE.md
- **P — Priority**: for autonomous prompts, include a numbered triage order
- **A — Action**: one concrete, scoped action — not "improve things"
- **C — Constraints**: at least one explicit out-of-bounds ("no new features", "fix top 3 only")
- **E — Exit**: never duplicate the handoff block — `buildPromptWithSession` appends it automatically

Anti-patterns: role-playing preambles, "Follow CLAUDE.md" (noise — it's always loaded), "zero warnings" (unachievable), analysis-only steps that produce a list but no code change.


---

## Project isolation during continuation prompts

**CRITICAL**: The user reuses a single session-continuation template across all projects. The template often contains a hardcoded project name that does not match where you actually are. **Always substitute the project implied by `cwd`.**

Rules:
- Session file to create/update = `/home/g/.claude/sessions/<project>.md`, where `<project>` derives from `cwd` — never from the project name in the user's prompt.
- Derive `<project>` from the **repo root**, not the worktree: in `~/dev/orangecat/.claude/worktrees/foo` the project is `OrangeCat`, not `foo`. Use `basename "$(git rev-parse --show-toplevel)"` and match it case-insensitively against the existing `sessions/*.md` names.
- If the prompt says "create Cockpit.md" but `cwd` is under `~/dev/orangecat` → create/update `OrangeCat.md` instead.
- Do not write to another project's directory on the strength of a *prompt* that references it — that reference is usually template residue, so stay put. An explicit request from George in the conversation is different, and cross-repo work (fleet, shared packages, a fix in the repo that actually owns the bug) is legitimate. The rule is about drifting, not about a repo boundary being sacred.
- If you catch a mismatch (prompt project ≠ `cwd` project), note it once: "Prompt referenced `<X>.md` but cwd is `<Y>` — updating `<Y>.md`." Then continue without asking.

---

## Answer "what do we have?" from a register, never from a grep

`~/dev` is a PARTIAL copy of the org — 43 repos exist, fewer are checked out —
so any question about what exists, what uses what, or what can be removed is
wrong by construction when answered by grepping local checkouts. Read the
generated registers in `fleet/registers/` first:

    packages.json    every fleet package, its install line, and its adopters BY NAME
    org.json         what repos exist and what they are
    toolchain.json   versions the fleet standardises on
    retired.json     what was removed, so it is not rebuilt

They are derived from the org and refreshed weekly, so unlike prose they cannot
drift. `fleet: node scripts/ci/shared-registry-audit.mjs` regenerates them and
prints adopters per package; `SHARED.md` is the editorial layer on top.

This applies to JUDGEMENT, not just building: before proposing to delete,
deprecate, replace or "consolidate" anything shared, read the register. On
2026-09-12 a grep for `@bitbaum/<name>` missed every consumer of packages that
install under a bare name, and the conclusion drawn from it — "nothing depends
on these" — would have deleted `bip-kit` (8 adopters), `limitkit` (3) and
`threadkit` (3). The register had the right answer the whole time, one command
away. **"I could not find it" is not "it does not exist"** — say which you mean.

---

## Never create a GitHub repository on your own initiative

Ask first, in the conversation, every time — and take silence as no. This covers
a scaffold, an extraction, a "-kit" pulled out of shared code, a demo, a probe,
and anything the site factory would spin up while you are driving it. It is not
satisfied by a good reason, by the repo being private, or by intending to clean
it up later.

Why it is a rule: agents commit under George's own git identity, so an
agent-created repo is indistinguishable from one he made himself. On 2026-09-12
he looked at his org and did not recognise several repos — "I don't know what
hire is. I don't know what lifeops is... You just keep spinning them up without
me allowing you." 27 of 48 repos had an agent-authored first commit. Nobody set
out to do that; each one looked reasonable in the session that made it.

A repository is public surface and permanent-feeling: it shows up in his
account, it is what a client or a hire sees, and only he can judge whether a
thing deserves to exist under his name. Work locally, show the diff, and let him
say yes before anything reaches GitHub. (A repo FleetCrown provisions because a
USER clicked provision is the user acting, not you.)

---

## Clean up the experiment when the experiment is over

Anything spun up to prove something — a dogfood site, a site-factory run, an
end-to-end probe, a scratch repo — is torn down in the SAME session that
created it, including its GitHub repository. Not archived, not left private:
gone. Do not ask whether to keep it; keeping it is the exception and needs a
reason and a real name.

Why it is a rule: on 2026-09-12 six such sites were still live days later, five
with repos behind them, and two read as real Zurich businesses that do not
exist, on George's own domain. The account becomes unreadable at a glance, the
register stops meaning "things we run", and agents reading either infer that
half-finished experiments are normal.

    # 1. FleetCrown project FIRST — a project naming a dirPath is a standing
    #    instruction to restore the site, and box-prepare re-clones it
    DELETE /api/projects/<entityId>?deleteLocal=1
    # 2. bash scripts/hetzner/retire-site.sh <name> --mode delete --repo keep --go
    # 3. gh repo delete bitbaum/<name> --yes   # the box's token has no delete_repo
    # 4. drop the row from scripts/hetzner/apps.conf in the same commit

`fleetcrown: pnpm run check:no-experiment-litter` fails the build if a generated
throwaway name is ever committed to the register.

---

## Working style

- Plan mode when requirements are ambiguous or the change is architectural. If
  something goes sideways, stop and re-plan rather than pushing on.
- Delegate to a subagent only for large, genuinely parallel work — a wide
  multi-file investigation. Never to verify your own work.
- Given a bug: fix it. Point at logs, errors, failing tests and resolve them.
  Escalate only when the fix implies a design decision that is George's.
- State uncertainty rather than guessing, and distinguish "I don't know" from
  "I need to look it up".
