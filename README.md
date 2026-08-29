# dotfiles

George's Linux environment. Nothing else.

`.bashrc`, `.ssh/config`, `.editorconfig`, and `.config/` (kitty, starship,
zellij, git hooks). Installed by symlink:

```bash
git clone git@github.com:bitbaum/dotfiles.git ~/dev/dotfiles
cd ~/dev/dotfiles && ./install.sh
```

`.claude/hooks/` holds the thin per-session Claude Code edge — see
[CLAUDE.md](CLAUDE.md) for which hooks are alive and which are deliberate
no-ops.

## What does *not* live here

**Fleet automation** — the cross-repo audits, the golden CI templates, the
shared-package registry (`SHARED.md`) and the reusable auto-merge sweep moved
to **[bitbaum/fleet](https://github.com/bitbaum/fleet)** on 2026-08-28. A repo
holding a `.bashrc` was the wrong place for machinery gating thirty other
repos. The old `SHARED.md` path and the reusable-workflow path both still
resolve here as pointers/shims, so nothing broke — but new work goes to
`fleet`.

**Agent dispatch** — the stop/notify loop, prompt injection and the PyQt
beacon migrated to **FleetCrown** (Fleet Runner) over 2026-06.

Product and business decisions belong in the repo that owns them.
