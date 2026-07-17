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
