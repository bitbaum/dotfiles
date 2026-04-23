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

- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately — don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### Subagent Strategy

- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### Verification Before Done

- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### Deployment Monitoring (Vercel projects)

After every `git push` on a Vercel project, monitor the deployment to completion before reporting done. Use the Monitor tool to stream status:

```bash
prev=$(vercel ls --prod 2>/dev/null | grep -v "^>" | grep -v "Age" | head -1 | awk '{print $3}')
while true; do
  row=$(vercel ls --prod 2>/dev/null | grep -v "^>" | grep -v "Age" | head -1)
  url=$(echo "$row" | awk '{print $3}')
  status=$(echo "$row" | awk '{print $5}')
  [ "$url" != "$prev" ] && echo "DEPLOY $status: $url"
  echo "$status" | grep -q "^Ready$" && echo "✓ live: $url" && exit 0
  echo "$status" | grep -qiE "Error|Failed|Canceled" && echo "✗ FAILED: $url" && exit 1
  sleep 8
done
```

If it fails: run `vercel logs <url>` to read the error, fix, push again. **Never tell the user a feature is deployed until Vercel shows Ready.**

### Autonomous Bug Fixing

- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests — then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how
- Escalate when the fix implies a design decision that should involve the user

### Uncertainty Handling

- When uncertain, state uncertainty explicitly rather than guessing
- Distinguish between "I don't know" and "I need to research this"
- Ask clarifying questions before making assumptions on ambiguous requirements

### Memory (Cross-Session Context)

A memory MCP server is available. Use it to persist context across sessions so work never starts cold. Sessions can die at any time (crash, restart, network drop) — save state **continuously**, not just at exit.

**Session start — do this on the FIRST user message of every session:**

**Core principle: ground truth first, memory second.** Git state is always accurate. Memory may be stale. Never trust memory alone.

- **Step 1: Detect project from zellij tab** (if `$HOME` and `ZELLIJ` is set):
  1. Run this exact command to find which tab this Claude process is in:
     ```bash
     # Find our shell (parent of claude), then zellij server (parent of shell), then correlate tab names with zellij's child PIDs
     _SHELL_PID=$(ps -o ppid= -p $PPID | tr -d ' ') && _ZS=$(ps -o ppid= -p $_SHELL_PID | tr -d ' ') && _TABS=$(zellij action query-tab-names 2>/dev/null) && _PIDS=$(ps -o pid= --ppid $_ZS 2>/dev/null | tr -d ' ') && paste <(echo "$_TABS") <(echo "$_PIDS") | while IFS=$'\t' read -r tab pid; do [ "$pid" = "$_SHELL_PID" ] && echo "$tab" && break; done
     ```
     **Why**: `focus=true` in dump-layout tracks the *viewed* tab, not the tab running Claude. Instead, this walks the process tree: `claude (PPID)` → `bash shell` → `zellij server`, then correlates `query-tab-names` order with zellij's child PIDs to find the tab owning our shell.
  2. Clean the tab name: strip trailing `$` and whitespace, then match case-insensitively against `~/.config/claude-projects.conf` (format: `tab_name|directory`)
  3. If found and directory exists, `cd` to it and tell the user: "Detected project: X (from zellij tab)"

- **Step 2: Inspect ground truth** (run in parallel once in the project directory):
  ```bash
  git log --oneline -10    # What shipped recently
  git status               # Uncommitted work
  git stash list           # Anything stashed
  ```
  This is the authoritative picture of where the project actually is.

- **Step 3: Load memory context** (ALWAYS, even if tab detection failed):
  1. Call `mcp__memory__search_nodes` with query `"session:"` to find ALL `session:*` entities
  2. If tab matched a project: call `mcp__memory__open_nodes` with `["session:<project>", "project:<project>"]`
  3. If tab did NOT match but `session:*` entities exist: list them and ask the user which to continue (or which project to work on)
  4. If tab did NOT match and no sessions exist: ask the user which project to work on
  5. **Cross-reference memory against git**: if they conflict, trust git. Update stale memory if needed.

- **Step 4: Synthesize and propose** — assess from multiple angles then present a brief:
  - What was last committed (recency, nature of work)
  - Any uncommitted/stashed work
  - What memory says was in progress (validated against git)
  - One clear recommended next move
  - Keep it concise — the user wants to get moving, not read a report

- **Step 5: Bootstrap new project** if tab matched but `project:<name>` entity does NOT exist in memory:
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

**CRITICAL**: The user reuses a single session-continuation template across all projects. The template often contains a hardcoded project name that does not match the current tab. **Always substitute the tab-detected project name.**

Rules:
- Session file to create/update = `/home/g/.claude/sessions/<tab-project>.md` — always derived from the zellij tab, never from the project name in the user's prompt.
- If the prompt says "create Cockpit.md" but the tab is OrangeCat → create/update `OrangeCat.md` instead.
- Never write code to or read files from a project directory that does not match the detected tab. If a prompt references another project's directory or session, ignore that reference and stay in the tab-detected project.
- If you catch a mismatch (prompt project ≠ tab project), note it once: "Prompt referenced `<X>.md` but this is the `<Y>` tab — updating `<Y>.md`." Then continue without asking.

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
