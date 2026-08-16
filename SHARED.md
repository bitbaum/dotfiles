# Shared code across the fleet

**Before you build something, check this file. If it is here, install it.**

This exists because the alternative was tried and measurably failed. Every
duplication in this fleet was already known, and knowing changed nothing:

- orangecat's `ADR-0002-rate-limiting-unification.md` (2026-01-18) is still
  **Status: Proposed**. It names *two* implementations. There are now **four**.
- `templates/ci/README.md` says "deliberately ONE central script, not a copy per
  repo". `auto-merge-sweep.sh` lives in **22 repos**, and as of 2026-08-16 in
  **8 distinct versions** spanning 11,787–19,344 bytes. A fix landed in one
  reaches at most 9 of them.

Both were written down. Writing it down is what failed. So this file is short,
the inventory underneath it is **generated**, and the number it produces is a
**ratchet** — see "The process" below.

---

## The registry — what already exists

| Package | Install | Replaces |
|---|---|---|
| [`ai-forms`](https://github.com/maonakamoto/ai-forms) | `npm i github:maonakamoto/ai-forms#v0.1.0` | per-app "fill this form from prose" + conversational refinement. Headless — ships **no markup**, so each app keeps its own styling. |
| [`ai-ration`](https://github.com/maonakamoto/ai-ration) | `npm i github:maonakamoto/ai-ration#v0.2.0` | LLM free-tier survival: multi-vendor fallback chain, the three kinds of 429, per-user fair-share rationing, `modelCost()` so a fallback can never silently bill. |
| [`threadkit`](https://github.com/maonakamoto/threadkit) | ⚠️ **not installable yet — no tag cut** | multi-participant message threads where *permission is participation*, not a role or an ownership column. Headless pure functions, so "who may read this" is unit-testable instead of buried in a `WHERE` clause. AI participants obey the same visibility rules. |

**Adopted:** `ai-forms` — fleetcrown, evig, aoz-housing, revampit,
surf-your-life. `ai-ration` — fleetcrown.
**Not yet:** orangecat and kivvi still carry their own form-assist; kivvi, evig,
botsmann still carry their own provider layers.

**`threadkit` is listed but cannot be installed yet.** Its README says
`npm install threadkit`; the package is not on npm and the repo has no tags,
and its publish workflow triggers *on a version tag*. So the one command it
documents fails today. Listed anyway, deliberately — this table is the fleet's
discovery surface, and a shared package nobody can find is one that gets
rewritten by hand. It replaces exactly the bug that
[`single-tenant-prod-hides-unscoped-queries`] records: role-derived access that
is correct at one doctor / one tenant / one org and silently wrong at two.
Cutting `v0.1.0` publishes it and makes this row real.

## What is worth extracting next

Ranked by (copies × how identical the logic is). Counts from
`scripts/ci/shared-inventory.sh`, forks excluded.

| Concern | Files | Why it is a good candidate |
|---|---|---|
| `auto-merge-sweep.sh` | **22** | 8 live versions of infrastructure that decides what ships. Highest count, worst drift. |
| rate limiting | **14** | A pure algorithm with zero app coupling. orangecat has 4, evig 3, botsmann 2 — *within one repo each*. |
| AI provider client | **16** | evig 7, orangecat 5. `ai-ration` already owns the hard part (chain, 429, budget); these are the callers. |
| logger | **10** | sbb-lost-found alone has 4. |
| health route | **8** | Identical shape in 8 repos; a 20-line contract. |
| `@ai-native-cms/core` | 2 | evig and revampit vendor it with **byte-identical trees** (`675b864b…`). Not yet diverged, so it is the cheapest extraction available — and a clock that is running. |

## What must NOT be centralized

Stated explicitly, because "share everything" is its own failure:

- **Auth / sessions** — coupled to the framework *and* the user schema.
- **DB schemas** — Drizzle vs Prisma vs raw SQL; a shared schema fights every ORM.
- **UI markup for chat and forms** — behaviour is shareable, *markup is not*.
  Each app owns its design tokens and has to keep looking like itself. This is
  why `ai-forms` is headless.
- **Anything where app semantics decide correctness.** orangecat legitimately
  lists paid model ids (BYOK — the user's key, the user's choice) while the same
  id in kivvi's fallback was a bug. Centralize the **rule**; assert it
  **locally**, where the app knows which is which.

---

## The process

**1. Rule of three.** First time, write it. Second time, notice. **Third time is
forbidden** — extract it, or you have chosen to maintain N copies forever.

**2. Check this file before building.** One grep. The cost of not checking is
visible above: 22 copies of one script.

**3. New extraction? Follow the shape that already works.**
Unscoped `ai-*` name · ESM · `dist` built by `prepare` (gitignored) ·
`exports` map · `verify = build && test` · **tests that import the package by
NAME**, not by reaching into `dist/` — otherwise a broken `exports`/`files` map
stays green until the first consumer installs it.

**4. Ship no HTTP client.** Every app has its own calling conventions, retries
and logging. Replacing those is a rewrite, not an adoption. Supply the
decisions; leave the fetch alone. This is why `ai-ration` has no client and
`ai-forms` has no markup.

**5. The ratchet.** `scripts/ci/shared-inventory.sh --check` runs on every PR
here and weekly across the fleet. Duplication counts may **fall**, may **hold**,
and may **never rise**.

```bash
scripts/ci/shared-inventory.sh            # report
scripts/ci/shared-inventory.sh --check    # ratchet — exit 1 if a count rose
scripts/ci/shared-inventory.sh --update   # move the baseline, in a PR, reviewed
```

Nobody has to fix 87 duplicated files today. The only requirement is to stop
adding to them — and when a count *falls*, `--update` locks the win in so it
cannot silently regress.

**Raising the baseline is allowed** — sometimes a copy really is right. It just
has to happen in a PR, where someone sees it, instead of by accident.
