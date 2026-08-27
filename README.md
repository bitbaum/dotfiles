# dotfiles

George's Linux environment, plus the fleet's central automation.

Two things live here, and only these two:

**1. The environment.** `.bashrc`, `.ssh/config`, `.editorconfig`, and
`.config/` (kitty, starship, zellij, git hooks). Installed by symlink:

```bash
git clone git@github.com:catomean/dotfiles.git ~/dev/dotfiles
cd ~/dev/dotfiles && ./install.sh
```

**2. Fleet-wide automation.** Checks that run *from this repo against every
other repo*, so there is one copy and nothing can drift:

| | |
|---|---|
| [`SHARED.md`](SHARED.md) | the shared-package registry and the duplication ratchet — **read before building anything cross-cutting** |
| `scripts/ci/auto-merge-sweep.sh` | the canonical merge policy; 16 repos call it as a reusable workflow |
| `scripts/ci/model-pin-audit.mjs` | runs daily: is any model id the fleet pins still served by its vendor? |
| `scripts/ci/verify-floor-audit.sh` | does every repo's `verify` actually run lint + typecheck + test? |
| `scripts/ci/shared-inventory.sh` | counts duplication across the fleet and holds it as a ratchet |
| `templates/ci/` | golden CI workflows + pre-commit, deliberately one central copy |

Every audit has a test suite beside it (`test-*.sh`, `test-*.mjs`). Keep it
that way — these gate every repo, so a broken checker is a fleet-wide outage.

## What does *not* live here

Agent dispatch. The stop/notify loop, prompt injection and the PyQt beacon
migrated to **FleetCrown** (Fleet Runner) over 2026-06. `.claude/hooks/` keeps
only the thin per-session edge — see [CLAUDE.md](CLAUDE.md) for which hooks are
alive and which are deliberate no-ops.

Product and business decisions belong in the repo that owns them, not beside
`SHARED.md`.
