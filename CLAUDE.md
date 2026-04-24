## Mission
Turn AI-assisted development into a reliable autopilot: Claude autonomously maintains and advances 19+ projects, surfaces the right work at the right time, and keeps the human in control with minimal friction.

## What This Repo Is
George's dotfiles and Claude Code automation system. The Claude hooks in `.claude/hooks/` are the core product — a real-time agentic development platform.

## Architecture

```
.claude/hooks/
  claude-popup.py      PyQt6 stop/confirm popup (Whisper STT, progressive disclosure)
  claude-dashboard.py  PyQt6 projects dashboard (All Projects overview + profiles)
  stop.sh              Fires on Claude finish → popup → prompt injection into Zellij tab
  notification.sh      Fires on Claude pause → auto-injects "continue"
  pre-tool-use.sh      Auto-approves safe commands, shows confirm popup for destructive ops
  lib.sh               Shared: resolve_tab, get_prompt, inject_prompt, play_sound

.config/
  claude-prompts.json  SSOT for all 13 injected prompts (next_best, test_and_fix, etc.)
  claude-projects.conf Zellij tab name → project directory registry (19 projects)
  claude-dashboard-settings.json  Runtime settings: whisper model, countdown, Claude model
```

## Design System (PyQt6)
All design tokens live in `claude-dashboard.py` at the top as module-level constants.
**SSOT rule**: never hardcode a color, size, or spacing inline — use the constants.

Font stack (set via `QFont` in `main()`):
- UI: Inter → Segoe UI → Helvetica Neue → sans-serif
- Mono: JetBrains Mono → Fira Code → Cascadia Code

Spacing uses an 8px grid: 8, 16, 24, 32, 48.
Border radius: sm=8, md=12, lg=16, card=12.

## When Working Here

**Test changes (always run both):**
```bash
python3 -c "import py_compile; py_compile.compile('.claude/hooks/claude-dashboard.py', doraise=True)"
DISPLAY=:0 timeout 4 python3 .claude/hooks/claude-dashboard.py
```

**Commit frequently** — these hooks power all 19 projects. Every working state should be committed.

**After editing prompts** (`claude-prompts.json`): the changes take effect immediately on the next Stop hook fire. No restart needed.

**After editing hooks** (`stop.sh`, `notification.sh`, etc.): changes take effect on the next Claude session finish/pause.

## Key Constraints
- PyQt6 only — no web tech, no Electron, no external servers
- Prompts injected via `zellij action write-chars` — no length limit but keep them focused
- Session files at `~/.claude/sessions/<TabName>.md` — one per project, updated by Claude
- Settings at `~/.config/claude-dashboard-settings.json` — shared between popup and dashboard

## Quality Standards
@~/.claude/CLAUDE.md
