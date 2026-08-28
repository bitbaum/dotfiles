# Global Engineering Standards

**Purpose**: Single Source of Truth for universal engineering principles.
**Usage**: Import in project CLAUDE.md files with `@~/.claude/CLAUDE.md`
**Last Updated**: 2026-02-24

---

## First Principles

Don't reason by analogy ("other projects do X"). Don't follow rules blindly. Reason from ground truths and derive every decision from them.

### Ground Truths About Software

These are irreducible facts. They don't depend on frameworks, languages, or trends.

1. **Software exists to serve humans, not the reverse.** Every feature, every abstraction, every line of code must make a human's life easier. If it doesn't, it shouldn't exist. Complexity that doesn't serve a user is waste.

2. **A system's behavior is defined by its state.** Bugs are state that doesn't match reality. If state lives in two places, they will eventually disagree. Therefore: one source of truth for every piece of data. No exceptions.

3. **Change is the only constant.** Requirements will change. Teams will change. Technologies will change. The only software that survives is software designed to be changed. Rigid software dies; adaptable software thrives.

4. **Humans are bad at repetition; machines are bad at judgment.** Automate the mechanical (formatting, validation, generation, testing). Reserve human attention for what requires judgment (architecture, UX, business decisions). Every manual step that could be automated is a reliability risk.

5. **Complexity compounds; simplicity scales.** Every abstraction added today is a tax paid on every change tomorrow. Simple code is read 10x more than it's written. The right question is never "can we add this?" but "can we afford to maintain this?"

6. **Correctness beats speed.** Wrong software that ships fast is slower than right software that ships deliberately. Debugging time dwarfs writing time. A bug in production costs 10x a bug caught in development.

### How to Apply First Principles

Before every decision, ask:

1. **"What problem am I actually solving?"** — Not what framework to use. Not what pattern to follow. What is the human problem?

2. **"What are the constraints?"** — What must be true? What are the laws of physics of this domain? (e.g., money must balance, data must be isolated, inputs can't be trusted)

3. **"What is the simplest solution that respects those constraints?"** — Not the most elegant. Not the most extensible. The simplest that is correct.

4. **"Which ground truth does this serve?"** — If the answer is "convention" or "best practice" without a reason, stop and rethink.

### The Anti-Pattern: Reasoning by Analogy

Analogy: "React apps usually have a `utils/` folder, so we should too."
First principles: "Do we have shared utilities? If yes, where should they live? If no, we don't need the folder."

Analogy: "Other projects use Redux, so we should too."
First principles: "What state do we need to manage? Can React's built-in state handle it? Only add a library if built-in solutions are insufficient."

Analogy: "We should add error boundaries everywhere."
First principles: "Where can errors actually occur? What should happen when they do? Add handling where it's needed, not everywhere 'just in case.'"

---

## Best Practices

Derived from the ground truths. Not rules to memorize — consequences of thinking clearly.

### From Truth #2 (state defines behavior → one source of truth)

**SSOT (Single Source of Truth)**
Every piece of data/config lives in **exactly ONE place**.

- Types derived from schemas (Zod/Drizzle → TypeScript), never defined separately
- Config in dedicated files, never scattered across components
- Constants centralized, never hardcoded in multiple places

**Schema as SSOT**
- Database schema defines what exists
- Types derived from schema (never defined separately)
- If data exists in two places, one of them is wrong. Eliminate it.

### From Truth #3 (change is constant → design for change)

**DRY (Don't Repeat Yourself)**
If you're copying code, **STOP** and extract to shared utility.

```
Rule of Three:
- 1st time: Write it
- 2nd time: Note the duplication
- 3rd time: Extract to shared module
```

**Configuration Over Code**
For data that changes: use config files, not hardcoded values.

```typescript
// WRONG - hardcoded in component
const labels = { ACTIVE: 'Aktiv', PENDING: 'Ausstehend' };

// RIGHT - in config file, imported where needed
// lib/config/status.ts
export const STATUS_CONFIG = {
  options: ['ACTIVE', 'PENDING'],
  labels: { ACTIVE: 'Aktiv', PENDING: 'Ausstehend' }
};
```

**Separation of Concerns**
Each layer has ONE responsibility:

```
lib/config/      → WHAT exists (definitions, options, labels)
lib/domain/      → Business logic (no HTTP, no UI)
app/api/         → HTTP layer (thin, delegates to domain)
components/      → UI rendering (no business logic)
hooks/           → Data fetching, state management
```

### From Truth #4 (automate the mechanical → never fix it twice)

**The Never-Twice Rule.** The second time you (or an agent) fix an instance of a
bug, you do not fix the third — you write the automation that ends the class:

```
1st time: fix it
2nd time: fix it, and notice it's a pattern
3rd time: FORBIDDEN — the rule/check/routine should already exist
```

A one-off fix costs tokens every recurrence and misses cases; a lint rule, CI
check, codemod, or CLAUDE.md rule closes the class *forever* at zero future cost.
Ask it as the last question of every fix: **"am I fixing this, or teaching the
machine to fix it forever?"** The first is 1x; the second compounds.

Concrete forms, cheapest first:
- Recurring code mistake → **ESLint rule** (or `no-restricted-syntax` / a grep gate).
- "Don't do X in this repo" knowledge → **CLAUDE.md rule** + a check that enforces it.
- Repeated manual sequence → a **script** or **skill**, named and committed.
- A whole class of regressions → a **test** that fails on it, wired into CI.
- No silent caps: if you must defer automating a class, say so in the fix — an
  un-encoded "I'll remember" is exactly the knowledge-in-a-head this rule targets.

**One definition of "verified".** Each repo exposes a `verify` script
(lint + typecheck + test) that CI calls verbatim — the check bundle is defined
once, run identically locally and on the shared branch. Green `verify` locally ⇒
green CI. Run it before declaring any change done. (Golden templates:
`fleet/templates/ci/`.)

**Check `fleet/SHARED.md` before building anything cross-cutting** — AI
calls, form fill, rate limiting, email, logging, health routes, CI sweeps. If a
package there already owns it, install it; do not write a second one. Measured
2026-08-16: `auto-merge-sweep.sh` exists in 22 repos in 8 different versions,
and rate limiting has 14 implementations (orangecat alone has 4, and its ADR to
unify them has been "Proposed" since January while the count doubled). The
duplication count is a ratchet — `fleet: scripts/ci/shared-inventory.sh --check` — and
it may fall or hold but never rise. If a copy really is justified, raise the
baseline in the same PR so a human sees the decision instead of inheriting it.

### From Truth #5 (complexity compounds → simplicity scales)

**KISS (Keep It Simple, Stupid)**
The simplest solution that works is usually the best.

- Three lines of similar code is better than a premature abstraction
- Don't add configurability until you need it
- Complexity must earn its place

**YAGNI (You Ain't Gonna Need It)**
Don't build for hypothetical future requirements.

- Build what's needed NOW
- Refactor when actual requirements emerge
- Premature abstraction is worse than duplication

**Modularity & Composability**
Build small, focused modules that compose together.

- Each module does ONE thing well
- Modules can be combined for complex behavior
- Changes to one module don't break others

### From Truth #6 (correctness beats speed)

**Validate Early, Fail Fast**
```typescript
// Schema is SSOT for validation
const result = schema.safeParse(input);
if (!result.success) {
  return { success: false, errors: result.error.flatten() };
}
// From here, data is guaranteed valid
```

**TypeScript Strict Mode Always**
- Minimize `any` (justify when used)
- Derive types from schemas when possible
- The compiler is your first line of defense

---

## The Litmus Tests

Quick checks to validate decisions:

### The "2 Files vs 5+ Files" Test

Before adding a field/feature, trace where it needs to exist:

```
Adding a new field should require:
✓ 1-2 files: Config + Schema (GOOD)
✗ 5+ files: Architecture is WRONG
```

### The "Explain It" Test

"Can I explain this architecture in one sentence?"
- **Yes** → Good
- **"It's complicated..."** → Too complex. Simplify.

### The "Blast Radius" Test

"What's the blast radius of changing this?"
- **Isolated to one module** → Good
- **Changes cascade through codebase** → Bad coupling. Decouple.

### The "New Team Member" Test

"Could someone new understand this in 15 minutes?"
- **Yes** → Appropriate complexity
- **No** → Overengineered or under-documented

---

## Red Flags

Stop and redesign if you find yourself:

1. **Copying same code to third location** → Extract to shared module
2. **Adding a field requires 5+ file changes** → Architecture is wrong
3. **Editing component code to add data** → Should be config
4. **Writing "temporary" workarounds** → Fix the root cause
5. **Can't explain the architecture simply** → Too complex
6. **Following a pattern without knowing why** → Reasoning by analogy. Stop.
7. **Adding abstraction for one use case** → YAGNI. Wait for the pattern.
8. **Catching errors "just in case"** → Where can errors actually occur? Handle those.
9. **Hardcoding numbers/stats in UI** → Query from DB or source from SSOT config. Never display fake placeholder metrics.

**STOP. Think from first principles. Then continue.**

---

## Anti-Patterns

| Anti-Pattern | Ground Truth Violated | Do Instead |
|--------------|----------------------|------------|
| Labels in components | #2 (one source of truth) | Import from config/constants |
| Options hardcoded in JSX | #2, #3 (change is constant) | Generate from config |
| Business logic in components | #5 (simplicity scales) | Move to lib/domain |
| Copy-paste programming | #3 (design for change) | Extract shared utility |
| "Make it work now, fix later" | #6 (correctness beats speed) | Design first, then code |
| God components (>300 lines) | #5 (complexity compounds) | Split into smaller components |
| Types separate from schema | #2 (one source of truth) | Derive types from schema |
| Magic strings | #4 (automate the mechanical) | Use constants/enums |
| Magic numbers (hardcoded stats, counts, metrics) | #2 (one source of truth) | Query from DB or source from config SSOT |
| Premature abstraction | #5 (simplicity scales) | Wait for 3 instances |
| Error handling "everywhere" | #1 (serve humans) | Handle where errors occur |
| Hardcoded hex color in className (`bg-[#hex]`) | #2 (one source of truth) | CSS var in globals.css + semantic Tailwind class |
| Hardcoded hex color in inline style | #2 (one source of truth) | CSS var in globals.css + className |
| Literal color value in tailwind.config | #2 (one source of truth) | `'var(--color-name)'` — never `'#hex'` |
| Design token defined in 2+ files | #2 (one source of truth) | Consolidate to globals.css only |

---

## Code Quality Standards

### Naming Conventions

```
Files:
  Components     → PascalCase.tsx (UserCard.tsx)
  Utilities      → camelCase.ts (formatDate.ts)
  Config         → kebab-case.ts (entity-registry.ts)
  Constants      → UPPER_SNAKE.ts (API_CONSTANTS.ts)

Code:
  Components     → PascalCase (UserCard)
  Functions      → camelCase (formatDate)
  Constants      → UPPER_SNAKE_CASE (MAX_RETRIES)
  Types          → PascalCase (UserProfile)
```

### Error Handling

- Validate inputs at system boundaries (user input, APIs)
- Return structured errors: `{ success: boolean; data?: T; error?: string }`
- Log errors with context (not just "Error")
- User-facing errors: helpful and actionable, never technical

### API Response Format

```typescript
// Success
{ success: true, data: {...}, meta?: { total, page } }

// Error
{ success: false, error: "Message", details?: [...] }
```

### Query Patterns

- Select only needed columns
- Use joins, avoid N+1 queries
- Paginate large results
- Index frequently queried columns

### Security

- Validate all inputs at API boundary
- Use parameterized queries (never string concatenation)
- Apply RLS/authorization at database level when possible
- Never expose internal errors to users

---

## UI/UX Principles

### Progressive Disclosure

Show only what user needs NOW, hide complexity until needed.

```
Level 1: Simple     → Templates, defaults
Level 2: Basic      → Core required fields
Level 3: Advanced   → Optional fields (collapsible)
Level 4: Expert     → Full control (hidden by default)
```

### States (Always Handle)

Every async operation needs:
- **Loading**: Skeleton or spinner
- **Empty**: Helpful message + action
- **Error**: Clear message + recovery action
- **Success**: Confirmation feedback

### Visual Hierarchy

- One primary CTA per page
- Size indicates importance
- Color draws attention (use sparingly)
- White space creates clarity

### Accessibility Basics

- Touch targets: minimum 44x44px
- Focus states visible
- Alt text for images
- Semantic HTML

---

## Design System Standards

This applies to every project with a CSS/UI layer. Design is subject to the same SSOT, DRY, and SoC rules as code.

### The Rule: CSS Custom Properties Are the Only SSOT for Design Tokens

All visual decisions (colors, fonts, spacing, radii, shadows) live in **one file** — `app/globals.css` (or `src/styles/globals.css`). Nothing else may define or duplicate these values.

**Canonical structure:**
```css
:root {
  /* Tier 1 — Primitive palette (raw values, not used directly by components) */
  --primitive-teal-600: #0D6E78;
  --primitive-orange-500: #E06B3A;

  /* Tier 2 — Semantic tokens (what things MEAN — always use these) */
  --color-brand:       var(--primitive-teal-600);
  --color-action:      var(--primitive-orange-500);
  --color-bg:          #FAF8F5;
  --color-surface:     #FFFFFF;
  --color-border:      #E8E2D9;
  --color-text:        #1C1917;
  --color-text-muted:  #78716C;

  /* Typography */
  --font-sans: 'Inter', sans-serif;
  --font-mono: 'JetBrains Mono', monospace;

  /* Radii / Shadows */
  --radius-card:   16px;
  --radius-btn:    8px;
  --shadow-card:   0 1px 4px rgb(0 0 0 / 0.08);
}
```

**Tailwind config MUST reference CSS vars — never hardcode literal values:**
```ts
// ✓ CORRECT — retheme by changing globals.css only
extend: {
  colors: { brand: 'var(--color-brand)', action: 'var(--color-action)' },
  borderRadius: { card: 'var(--radius-card)', btn: 'var(--radius-btn)' },
  boxShadow: { card: 'var(--shadow-card)' },
}

// ✗ WRONG — retheme requires finding every hardcoded value across the codebase
extend: { colors: { brand: '#0D6E78' } }
```

**Components MUST use semantic Tailwind classes — never arbitrary values or inline styles for brand decisions:**
```tsx
// ✓ CORRECT
<button className="bg-action text-white rounded-btn shadow-card">

// ✗ WRONG
<button className="bg-[#E06B3A] rounded-[8px]" style={{ boxShadow: '0 1px 4px ...' }}>
```

### Design SSOT Violations — Catch and Fix Immediately

When doing ANY work touching UI, scan for and fix these before moving on:

| Violation | Example | Fix |
|-----------|---------|-----|
| Arbitrary hex in className | `bg-[#1a2b3c]`, `text-[#fff]` | Define CSS var + semantic Tailwind class |
| Hex in inline style | `style={{ color: '#1a2b3c' }}` | Move to CSS var, use className |
| Literal color in tailwind.config | `brand: '#0D6E78'` | Change to `brand: 'var(--color-brand)'` |
| Hardcoded font in className | `font-['Inter']` | Use `font-sans` (from Tailwind + CSS var) |
| Radius/shadow hardcoded | `rounded-[12px]`, `shadow-[0_4px_...]` | Define `--radius-*` / `--shadow-*` vars |
| Token defined in multiple files | Same color in tailwind.config AND globals.css as literal | Keep only in globals.css as CSS var |

### Design File Roles (SoC)

```
app/globals.css      ← SSOT: ALL design tokens as CSS custom properties
tailwind.config.ts   ← maps Tailwind utilities → CSS vars (NEVER literal values)
lib/tokens.ts        ← (optional) TypeScript re-export of token NAMES for non-CSS contexts
                        (Recharts charts, Satori OG images, canvas) — values come from CSS vars at runtime
components/          ← consume Tailwind semantic classes only; zero raw values
```

### Why This Matters

With this structure:
- **Retheme the entire product**: edit `globals.css` only — zero component changes needed
- **Dark mode**: CSS vars flip via `.dark` class — zero component changes needed
- **Agent audit**: `grep -r '\[#' src/` instantly shows every violation

Without this structure, "make it look like x.ai" means touching hundreds of component files.

---

## Testing Philosophy

### What to Test

| Priority | What | Why (Ground Truth) |
|----------|------|--------------------|
| High | Business logic | #6: Correctness beats speed |
| High | API endpoints | #6: Validate at boundaries |
| Medium | UI interactions | #1: Serve humans |
| Low | Pure utilities | Usually obvious from types |

### Browser Automation

Use for:
- E2E flows (create, edit, delete)
- Visual verification after UI changes
- Form submission testing

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

### Commit Format

```
<type>(<scope>): <description>

Types: feat, fix, refactor, perf, test, docs, chore
```

### Pre-Commit Checklist

- [ ] Lint passes
- [ ] Type check passes
- [ ] Tests pass (if applicable)
- [ ] No console.log in production code
- [ ] No hardcoded secrets

### Code Comments

- Comment **WHY**, not **WHAT** (Ground Truth #1: serve humans reading code)
- No obvious comments ("increment counter")
- Document complex algorithms
- Mark workarounds with TODO + context

---

## Workflow (Claude Code Specific)

### Plan Mode

- Enter plan mode when requirements are ambiguous or the change is architectural
- If something goes sideways, STOP and re-plan immediately — don't keep pushing
- Write detailed specs upfront to reduce ambiguity

### Subagent Strategy

- Delegate to a subagent only for large tasks that are genuinely independent and parallelizable (e.g. a wide multi-file investigation)
- Do not delegate work you can finish yourself in a handful of tool calls, and do not use subagents to verify or double-check your own work
- Offload noisy research/exploration to subagents to keep the main context clean

### Deployment Monitoring (self-hosted on Hetzner "bitbaum")

Every studio app is self-hosted on the single Hetzner box "bitbaum"
(167.233.22.31) behind Caddy — **there is no Vercel**. Deploys are push-to-main
→ GitHub Actions (a `deploy-selfhost.yml`-style workflow) → build → rsync to
`/opt/<app>/app` → `systemctl restart <app>-app`. After every `git push` to a
deploy branch, monitor the run to completion before reporting done:

```bash
# gh run list can return the PREVIOUS run right after a push — filter by the SHA
# you just pushed, and give Actions a moment to register it.
sleep 6
sha=$(git rev-parse HEAD)
run=$(gh run list --limit 10 --json databaseId,headSha \
  --jq "map(select(.headSha==\"$sha\"))[0].databaseId")
[ -n "$run" ] && gh run watch "$run" --exit-status && echo "✓ CI/deploy green" \
  || { echo "✗ deploy failed"; gh run view "$run" --log-failed | tail -40; }
```

Then confirm the app actually came back up — CI green ≠ live:

```bash
curl -fsS https://<app>.orangecat.ch/api/health && echo "  ✓ live"
```

If it fails: read the failed job logs (`gh run view <run> --log-failed`), or ssh
`ubuntu@167.233.22.31` and check `journalctl -u <app>-app -n 50` / `systemctl
status <app>-app`. Fix, push again. **Never tell the user a feature is deployed
until CI is green AND the health check returns 200.** (Local warm builds can take
~8 min, cold 30+ — budget for it; don't declare done on push.)

### Autonomous Bug Fixing

- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests — then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how
- Escalate when the fix implies a design decision that should involve the user

### Agent Prompt System

All prompts in `~/.config/agent-prompts.json` follow the **SPACE framework** documented at `~/.config/prompts-system.md`. When writing or editing a prompt:

- **S — State**: specify what context the agent must fetch (git log, tsc, grep) beyond the always-loaded session + CLAUDE.md
- **P — Priority**: for autonomous prompts, include a numbered triage order
- **A — Action**: one concrete, scoped action — not "improve things"
- **C — Constraints**: at least one explicit out-of-bounds ("no new features", "fix top 3 only")
- **E — Exit**: never duplicate the handoff block — `buildPromptWithSession` appends it automatically

Anti-patterns: role-playing preambles, "Follow CLAUDE.md" (noise — it's always loaded), "zero warnings" (unachievable), analysis-only steps that produce a list but no code change.

### Uncertainty Handling

- When uncertain, state uncertainty explicitly rather than guessing
- Distinguish between "I don't know" and "I need to research this"
- Ask clarifying questions before making assumptions on ambiguous requirements

### Memory (Cross-Session Context)

A memory MCP server is available. Use it to persist context across sessions so work never starts cold. Sessions can die at any time (crash, restart, network drop) — save state **continuously**, not just at exit.

**Session start — do this on the FIRST user message of every session:**

**Core principle: ground truth first, memory second.** Git state is always accurate. Memory may be stale. Never trust memory alone.

- **Step 1: Establish the project — `cwd` is the answer.** The launcher already resolved it, so `pwd` IS the project. Nothing else needs detecting. Only when `cwd` is bare `$HOME` is the project genuinely unknown — then ask the user.

  **Do NOT detect the project from the zellij tab.** That mechanism is retired: tabs are no longer renamed per project (they read `Tab #1`), one pane now hosts many concurrent sessions so `ZELLIJ_PANE_ID` is not unique, and `/tmp/claude-pane-*` is deleted by whichever of them exits first. `~/.config/claude-projects.conf` is legacy — do not consult it.

  **Many sessions run concurrently** (commonly 5–10, often several in the same repo). Every live session self-registers at `~/.claude/sessions/<pid>.json`. That registry is the SSOT for what else is running:
  ```bash
  jq -r 'select(.status!=null) | "\(.status)\t\(.kind)\t\(.cwd)\t\(.name)"' \
    ~/.claude/sessions/*.json 2>/dev/null | sort
  ```
  Check it before starting **wide-blast-radius work** (a type layer, a shared config, a migration). Not for file conflicts — `_claude_autoworktree_enter` already isolates each session into its own worktree automatically. Check it for *semantic* collisions, which worktrees do **not** prevent and which have bitten this fleet repeatedly: two sessions fixing the same bug on different branches, or two sessions choosing the same migration timestamp.

- **Step 2: Inspect ground truth** (run in parallel once in the project directory):
  ```bash
  git log --oneline -10    # What shipped recently
  git status               # Uncommitted work
  git stash list           # Anything stashed
  ```
  This is the authoritative picture of where the project actually is.

- **Step 3: Load memory context** (ALWAYS):
  1. Call `mcp__memory__search_nodes` with query `"session:"` to find ALL `session:*` entities
  2. If `cwd` identified a project: call `mcp__memory__open_nodes` with `["session:<project>", "project:<project>"]`
  3. If `cwd` is `$HOME` but `session:*` entities exist: list them and ask the user which to continue (or which project to work on)
  4. If `cwd` is `$HOME` and no sessions exist: ask the user which project to work on
  5. **Cross-reference memory against git**: if they conflict, trust git. Update stale memory if needed.

- **Step 4: Synthesize and propose** — assess from multiple angles then present a brief:
  - What was last committed (recency, nature of work)
  - Any uncommitted/stashed work
  - What memory says was in progress (validated against git)
  - One clear recommended next move
  - Keep it concise — the user wants to get moving, not read a report

- **Step 5: Bootstrap new project** if `cwd` identified a project but `project:<name>` entity does NOT exist in memory:
  - Tell the user: "New project detected — no memory entity found for `<name>`. I'll create one so future sessions restore properly."
  - Read the project's CLAUDE.md (if it exists) and package.json to extract stack/purpose
  - Create `project:<name>` entity immediately with: purpose, stack, repo path, and `currentState: New project, no prior work recorded.`
  - This ensures the next session in this tab restores context instead of starting cold

**Save continuously — after every meaningful milestone:**
- Completed a feature, fix, or refactor → update `project:<name>` with `currentState` observation
- Made an architectural decision → create `decision:<project>:<topic>` entity
- Discovered a non-obvious pattern or gotcha → create `pattern:<project>:<name>` entity
- Fixed a recurring bug → create `bug:<project>:<area>` entity
- Established a convention the user confirms → save it

**Track active work — REPLACE (not append) `session:<project>` entity:**
- **CRITICAL**: Always use `delete_entities` then `create_entities` to replace the session entity. NEVER use `add_observations` — it appends, creating stale history that confuses future session detection.
- **When starting a task**: delete+recreate `session:<project>` with what you're about to do
- **After each commit or significant step**: delete+recreate with current state
- **When finishing all work**: delete the `session:<project>` entity (clean state = no active work)

The `session:<project>` entity should contain exactly ONE observation with ALL of:
- `activeTask`: what is currently being worked on (specific enough to resume)
- `progress`: what steps are done, what remains
- `uncommittedChanges`: description of any unsaved/uncommitted work
- `nextStep`: the immediate next action to take

This way, if the session dies mid-task, the next session can pick up exactly where it left off.

**Entity naming convention:**
```
project:<name>              → top-level project context (long-lived)
session:<project>           → active work in progress (ephemeral, deleted when done)
decision:<project>:<topic>  → architectural decisions
bug:<project>:<area>        → known bugs and fixes
pattern:<project>:<name>    → codebase patterns to follow
```

**What NOT to save:** transient debugging steps, things already in CLAUDE.md, obvious facts.

### Project isolation during continuation prompts

**CRITICAL**: The user reuses a single session-continuation template across all projects. The template often contains a hardcoded project name that does not match where you actually are. **Always substitute the project implied by `cwd`.**

Rules:
- Session file to create/update = `/home/g/.claude/sessions/<project>.md`, where `<project>` derives from `cwd` — never from the project name in the user's prompt.
- Derive `<project>` from the **repo root**, not the worktree: in `~/dev/orangecat/.claude/worktrees/foo` the project is `OrangeCat`, not `foo`. Use `basename "$(git rev-parse --show-toplevel)"` and match it case-insensitively against the existing `sessions/*.md` names.
- If the prompt says "create Cockpit.md" but `cwd` is under `~/dev/orangecat` → create/update `OrangeCat.md` instead.
- Never write code to or read files from a project directory other than the one `cwd` is in. If a prompt references another project's directory or session, ignore that reference and stay put.
- If you catch a mismatch (prompt project ≠ `cwd` project), note it once: "Prompt referenced `<X>.md` but cwd is `<Y>` — updating `<Y>.md`." Then continue without asking.

---

## Summary

**6 Ground Truths:**
1. Software exists to serve humans
2. State defines behavior — one source of truth
3. Change is constant — design for it
4. Automate the mechanical, reserve humans for judgment
5. Complexity compounds; simplicity scales
6. Correctness beats speed

**The Process:**
1. What problem am I solving?
2. What are the actual constraints?
3. What is the simplest correct solution?
4. Which ground truth does this serve?

**If you can't answer #4, stop and rethink.**

---

*Think from ground truths. Build for change. Ship correct code.*
