# The Golden CI Floor

**One source of truth for what "a defended branch" means across every repo.**

Rung 2 of the efficiency ladder: the reason to have this is that automation only
multiplies you if it is *uniform*. When every repo has the same self-defending
floor, every agent in the fleet — and every human contributor on day one — gets
the same guarantees no matter which repo they land in. A good check trapped in
one repo helps one repo; the same check in the template helps all of them.

## What the floor guarantees

Every repo's `main` is protected by, at minimum, on every push and PR:

1. **Lint** — catches the undefined-identifier / dead-code class before merge.
2. **Typecheck** (`tsc --noEmit`) — the compiler is the first line of defence.
3. **Tests** — the suite you already wrote actually *runs*. Tests that never run
   are pure waste; this is the whole point of Rung 2.
4. **Build** — the app compiles into the artifact you ship (tested == shipped).

These four are **hermetic**: they need no secrets, no live database, no network.
That is deliberate — a gate that goes red for want of a secret trains you to
ignore red. Anything that needs infra (e2e against a real DB, prod smoke,
migration replay) is an *upgrade* you add per-repo once the secrets exist. See
the ladder below.

## How to adopt (copy, don't reinvent)

- **npm repo** → copy `ci-npm.yml` to `.github/workflows/ci.yml`.
- **pnpm repo** → copy `ci-pnpm.yml` to `.github/workflows/ci.yml`.
- Adjust the `test`/`typecheck` step to match the repo's actual `package.json`
  script names. If a repo has no `typecheck` script, call `npx tsc --noEmit`
  directly (don't add a script just for CI).
- Commit on a branch and open a PR — the `pull_request` trigger runs the whole
  gate on the PR itself, so you *see it go green before it ever touches main*.

## The local mirror: a `verify` script (Rung 3 — close the loop)

CI protects the *shared* branch, asynchronously, after a push. That still leaves
a human running the app by hand to check a change before it ships. The `verify`
script removes that human: it gives an agent the **same signal, synchronously,
in one command, before pushing.**

Every repo exposes one script with an identical name and contract:

```jsonc
// package.json — mirrors the CI floor's HERMETIC gates
"verify": "<pm> run lint && <pm> run typecheck && <pm> run test"
```

- Same checks as CI (minus the non-hermetic build/e2e) → **green `verify` locally
  ⇒ green CI.** No surprises after push.
- Uniform name across every repo → an agent (or a new contributor) runs the same
  command everywhere and never has to learn a per-repo incantation.
- The reflex is encoded in each repo's CLAUDE.md: *before declaring a change done,
  run `verify` and read the result.* That is what takes the prompter out of the
  validate loop — the agent sees red and self-corrects in the same turn.

Add a `typecheck` script (`tsc --noEmit`) to any repo missing one so `verify` is
uniform. Deeper "drive the running app" smokes are a per-repo upgrade on top.

#### This contract is now audited

The sentence above was true on paper and false in practice — repos shipped a
`verify` that silently dropped a gate, so "verify is green" meant something
different in each one, while the merge train and auto-merge were built on top
of it meaning one thing.

```bash
scripts/ci/verify-floor-audit.sh              # exit 1 if any repo is below
scripts/ci/verify-floor-audit.sh --warn-only  # report only
```

It reads every repo remotely, on that repo's own default branch, and sorts
them three ways: **at floor**, **fixable** (the repo has the script, `verify`
just skips it — a one-line change), and **needs real work** (no such script
exists; adding a no-op to satisfy the floor would be theatre). It runs weekly
via `.github/workflows/verify-floor.yml`, reporting into the job summary.

Deliberately **one central script, not a copy per repo** — `auto-merge-sweep.sh`
was copied into 17 repos and now has at least 5 live variants, so a fix landed
in one reaches none of the others.

**What it does not prove:** that each gate is *effective*. A `lint` script that
exists but silently does nothing passes. `sbb-lost-found` is the live example —
`next lint` prompts interactively because the repo has a flat config Next 14
cannot read, so lint has never actually run.

#### `continue-on-error` on a gate is worse than no gate

One effectiveness hole *is* checked, because the fleet already fell down it.
evig's CI ran the full unit suite on every PR and discarded the result with
`continue-on-error: true` — added as "non-blocking while the suite matures",
never flipped back. The suite matured to 7,769 tests. When the 2026-07-28
`primary-*` → `success-*` token sweep broke 25 assertions in 15 suites, CI ran
them, saw them fail, and reported green for three weeks.

That is strictly worse than having no test job: an absent gate is *visibly*
absent, while a discarded one manufactures a ✓. The audit now flags any step
that runs a floor gate under `continue-on-error`. It is scoped to floor gates
on purpose — a best-effort step with a real fallback (orangecat's `cd.yml`
artifact download, which builds from source if the download fails) is a
legitimate use and is not flagged.

**Rule:** if a check is not ready to block, don't wire it into CI green. Run it
on a schedule, or in a job nothing depends on — but never as a step that
reports success while failing.

## The maturity ladder (add per-repo as the secrets/infra appear)

The floor is rung 0. Reach for the next rung when the repo earns it — the
reference implementations already exist, lift them:

| Upgrade | Lift it from | Add when |
|---|---|---|
| Secret scan (gitleaks) in CI | `orangecat/.github/workflows/ci.yml` (`security` job) | always, once green |
| Committed-secret pre-commit hook | `botsmann/.husky/pre-commit` | repo has contributors |
| Dependency audit gate | `orangecat` `security` job | always, once green |
| e2e against a seeded DB | `revampit/.github/workflows/ci.yml` (`e2e-local` job) | repo has Playwright specs |
| Migration drift replay | `revampit` (`migrations` job) | repo owns SQL migrations |
| CodeQL SAST | `orangecat/.github/workflows/codeql.yml` | repo is security-sensitive |
| P0 e2e matrix + build artifact | `orangecat/.github/workflows/ci.yml` | flagship / shipping repo |

**Rule:** the second time you hand-fix a class of bug, it becomes a gate here —
not a third manual fix. This template is where "never fix it twice" lives.

## Checking that a repo actually honours the floor

Everything above is a *stated* rule. Stating a rule is not enforcing one, and
the gap between the two is where this fleet has repeatedly lost weeks:

```bash
dotfiles/scripts/ci/check-verify-contract.sh            # this repo
dotfiles/scripts/ci/check-verify-contract.sh --all      # every repo under ~/dev
```

It asserts the contract **end to end** — `verify` exists, CI actually invokes
it, and that invocation cannot be softened:

| Rule | Why it is a rule |
|---|---|
| `verify` exists | without it there is no single definition of "verified" |
| CI invokes `verify` | a repo can hand-copy the steps, then drift from them |
| no `--if-present` on it | renaming a script turns its gate into a silent pass |
| no `continue-on-error` on that step | the result is computed, then discarded |
| `verify` has no `\|\| true` inside | CI faithfully runs a gate that cannot fail |

The earlier fleet audit checked only whether repos *declared* a `verify` script
and found 21 of 21 did — which reads like success and was not. Running the
end-to-end check found four real violations, including a repo whose CI
hand-copied verify's four steps with `--if-present` on each, and one whose CI
linted with `--max-warnings 0` while its own `verify` script did not — so
`verify` on a laptop was **weaker** than the gate blocking the merge.

**What it deliberately does not check**, so a pass is not read as more than it
is: whether the checks inside `verify` are any good, whether the tests assert
anything, or `|| true` elsewhere in CI (usually legitimate — flagging it gave
nine false alarms out of nine here, and a checker that cries wolf gets ignored).

The checker has its own negative tests (`test-check-verify-contract.sh`, run by
this repo's CI) proving each rule still bites against a violating fixture. A
gate that has never gone red is indistinguishable from one that cannot.
