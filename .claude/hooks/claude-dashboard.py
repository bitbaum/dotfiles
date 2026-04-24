#!/usr/bin/env python3
"""Claude Projects Dashboard — project overview, prompt library, settings."""
import sys, os, json, subprocess, re
from pathlib import Path
from datetime import datetime, date

from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QScrollArea, QPushButton, QFrame, QTextEdit,
    QSizePolicy, QToolButton, QComboBox, QSlider, QGridLayout,
)
from PyQt6.QtCore import Qt, QThread, pyqtSignal
from PyQt6.QtGui import QColor, QCursor, QPalette, QFont

# ── Paths ─────────────────────────────────────────────────────────────────────
CONF     = Path(os.environ.get("CLAUDE_PROJECTS_CONF",
                                Path.home() / ".config/claude-projects.conf"))
PROMPTS  = Path(os.environ.get("CLAUDE_PROMPTS",
                                Path.home() / ".config/claude-prompts.json"))
SESSIONS = Path.home() / ".claude/sessions"
SETTINGS = Path.home() / ".config/claude-dashboard-settings.json"

# ── Settings ──────────────────────────────────────────────────────────────────
DEFAULT_SETTINGS = {
    "claude_model":   "claude-sonnet-4-6",
    "whisper_model":  "base",
    "countdown_secs": 12,
}
CLAUDE_MODELS = [
    ("claude-opus-4-6",           "Opus 4.6  — most capable"),
    ("claude-sonnet-4-6",         "Sonnet 4.6  — fast + smart  (default)"),
    ("claude-haiku-4-5-20251001", "Haiku 4.5  — fastest"),
]
WHISPER_MODELS = ["tiny", "base", "small", "medium"]
WHISPER_DESC   = {"tiny":"Fast, less accurate","base":"Good balance (default)",
                  "small":"More accurate, slower","medium":"Most accurate, slowest"}

def load_settings() -> dict:
    if SETTINGS.exists():
        try:
            return {**DEFAULT_SETTINGS, **json.loads(SETTINGS.read_text())}
        except Exception:
            pass
    return dict(DEFAULT_SETTINGS)

def save_settings(s: dict):
    SETTINGS.parent.mkdir(parents=True, exist_ok=True)
    SETTINGS.write_text(json.dumps(s, indent=2))

# ── Prompt metadata ───────────────────────────────────────────────────────────
CATEGORIES = [
    {"id":"dev",     "icon":"🛠", "label":"Development",        "keys":["next_best","test_and_fix","browser_test","quality"]},
    {"id":"ship",    "icon":"🚀", "label":"Ship & Deploy",      "keys":["commit_push","deploy_check","full_audit"]},
    {"id":"vision",  "icon":"🧭", "label":"Vision & Product",   "keys":["mission","product","ux_review"]},
    {"id":"content", "icon":"📣", "label":"Content & Marketing","keys":["marketing","social"]},
]
PROMPT_META = {
    "next_best":    ("⚡","Next best task",      "1"),
    "test_and_fix": ("🧪","Test & fix",           "2"),
    "browser_test": ("🌐","Browser test",         "—"),
    "quality":      ("💎","Code quality pass",    "4"),
    "commit_push":  ("📦","Commit & push",        "3"),
    "deploy_check": ("✅","Deploy checklist",     "—"),
    "full_audit":   ("🔍","Full audit + plan",    "5"),
    "mission":      ("🎯","Mission alignment",    "6"),
    "product":      ("🏗", "Product thinking",   "—"),
    "ux_review":    ("🎨","UX / design review",   "—"),
    "marketing":    ("📣","Marketing copy",        "—"),
    "social":       ("📱","Social media content", "—"),
    "continue":     ("▶", "Continue",             "—"),
}

# ── Colours ───────────────────────────────────────────────────────────────────
# ── Design tokens (SSOT — never hardcode these inline) ───────────────────────
# Surface scale — deep navy dark theme
BG        = "#080b1a"   # page background
SIDEBAR   = "#0b0e1f"   # sidebar surface
CARD      = "#0f1327"   # card background
SURFACE   = "#151b36"   # raised surface (inputs, chips)
SURFACE2  = "#1b2240"   # hover / selected surface
BORDER    = "#1c2445"   # subtle divider
BORDER2   = "#232c55"   # stronger divider

# Typography scale
TEXT1     = "#eef1ff"   # primary — near-white, high contrast
TEXT2     = "#8d97c8"   # secondary — readable, not dominant
TEXT3     = "#4a5278"   # tertiary — timestamps, labels, hints

# Semantic colours + their dark bg fills
ACCENT    = "#7c86f5"   # indigo — default interactive
ACCENT_BG = "#141847"
GREEN     = "#34d97b"   # emerald — success, active, done
GREEN_BG  = "#092217"
AMBER     = "#f5a623"   # amber — warning, pending
AMBER_BG  = "#201400"
RED       = "#f46f6f"   # rose — error, critical
RED_BG    = "#240d0d"
CYAN      = "#22d3ee"   # cyan — info, next actions
CYAN_BG   = "#031a22"
PURPLE    = "#b57ef5"   # violet — UX/design/testing
PURPLE_BG = "#180d30"

# Spacing scale (8px grid)
SP1 = 8;  SP2 = 16;  SP3 = 24;  SP4 = 32;  SP5 = 48

# Border-radius scale
R_SM = 8;  R_MD = 12;  R_LG = 16;  R_XL = 20

# Prompt category colour map
CAT_COLORS = {
    "dev":     (ACCENT, ACCENT_BG),
    "ship":    (GREEN,  GREEN_BG),
    "vision":  (PURPLE, PURPLE_BG),
    "content": (AMBER,  AMBER_BG),
}

# ── Dark palette ──────────────────────────────────────────────────────────────
def apply_palette(app):
    app.setStyle("Fusion")
    p = QPalette()
    p.setColor(QPalette.ColorRole.Window,          QColor(BG))
    p.setColor(QPalette.ColorRole.WindowText,      QColor(TEXT1))
    p.setColor(QPalette.ColorRole.Base,            QColor(SURFACE))
    p.setColor(QPalette.ColorRole.AlternateBase,   QColor(CARD))
    p.setColor(QPalette.ColorRole.Text,            QColor(TEXT1))
    p.setColor(QPalette.ColorRole.Button,          QColor(SURFACE))
    p.setColor(QPalette.ColorRole.ButtonText,      QColor(TEXT1))
    p.setColor(QPalette.ColorRole.Highlight,       QColor(ACCENT))
    p.setColor(QPalette.ColorRole.HighlightedText, QColor(TEXT1))
    p.setColor(QPalette.ColorRole.ToolTipBase,     QColor(CARD))
    p.setColor(QPalette.ColorRole.ToolTipText,     QColor(TEXT1))
    p.setColor(QPalette.ColorRole.PlaceholderText, QColor(TEXT3))
    app.setPalette(p)

SS = f"""
QScrollBar:vertical {{
    background:{SURFACE}; width:5px; border-radius:3px; margin:0;
}}
QScrollBar::handle:vertical {{
    background:{BORDER2}; border-radius:3px; min-height:24px;
}}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {{ height:0; }}
QScrollArea {{ border:none; background:transparent; }}
QTextEdit {{
    background:{SURFACE}; color:{TEXT1};
    border:1px solid {BORDER}; border-radius:8px;
    padding:10px 12px;
    font-family:'JetBrains Mono','Fira Code','Cascadia Code',monospace;
    font-size:12px; line-height:1.5;
    selection-background-color:#3a4490; selection-color:{TEXT1};
}}
QComboBox {{
    background:{SURFACE}; color:{TEXT1};
    border:1px solid {BORDER}; border-radius:8px;
    padding:8px 12px; font-size:13px;
}}
QComboBox::drop-down {{ border:none; width:24px; }}
QComboBox QAbstractItemView {{
    background:{CARD}; color:{TEXT1};
    border:1px solid {BORDER};
    selection-background-color:{ACCENT_BG};
}}
"""

# ── Widget helpers ────────────────────────────────────────────────────────────

def L(text, size=13, color=TEXT1, bold=False, italic=False,
       wrap=False, selectable=False) -> QLabel:
    w = QLabel(text)
    ss = f"font-size:{size}px; color:{color};"
    if bold:   ss += "font-weight:700;"
    if italic: ss += "font-style:italic;"
    w.setStyleSheet(ss)
    if wrap: w.setWordWrap(True)
    if selectable:
        w.setTextInteractionFlags(
            Qt.TextInteractionFlag.TextSelectableByMouse |
            Qt.TextInteractionFlag.TextSelectableByKeyboard)
        w.setCursor(QCursor(Qt.CursorShape.IBeamCursor))
    return w

def divider(color=BORDER) -> QFrame:
    f = QFrame()
    f.setStyleSheet(f"background:{color}; max-height:1px; min-height:1px;")
    f.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
    return f

def chip(text, fg, bg, size=11) -> QLabel:
    w = QLabel(text)
    w.setStyleSheet(f"color:{fg}; background:{bg}; border-radius:6px;"
                    f"padding:3px 10px; font-size:{size}px; font-weight:700;")
    w.setSizePolicy(QSizePolicy.Policy.Maximum, QSizePolicy.Policy.Fixed)
    return w

def tag(text, fg, bg) -> QLabel:
    w = QLabel(text)
    w.setStyleSheet(f"color:{fg}; background:{bg}; border-radius:5px;"
                    f"padding:2px 8px; font-size:11px; font-weight:600;")
    w.setSizePolicy(QSizePolicy.Policy.Maximum, QSizePolicy.Policy.Fixed)
    return w

def card(left_accent=None) -> QWidget:
    w = QWidget()
    border_left = f"border-left:3px solid {left_accent};" if left_accent else ""
    w.setStyleSheet(f"background:{CARD}; border-radius:12px;"
                    f"border:1px solid {BORDER}; {border_left}")
    return w

def action_btn(text) -> QPushButton:
    b = QPushButton(text)
    b.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
    b.setStyleSheet(
        f"QPushButton{{background:{SURFACE}; color:{TEXT2}; border:1px solid {BORDER};"
        f"border-radius:8px; padding:8px 16px; font-size:12px; font-weight:600;}}"
        f"QPushButton:hover{{background:{SURFACE2}; color:{TEXT1}; border-color:{ACCENT};}}")
    return b

def section_label(text, color=TEXT3) -> QLabel:
    w = QLabel(text)
    w.setStyleSheet(f"font-size:10px; font-weight:700; color:{color}; letter-spacing:1px;")
    return w

def time_ago(ts: float) -> str:
    d = datetime.now().timestamp() - ts
    if d < 60:    return "just now"
    if d < 3600:  return f"{int(d/60)}m ago"
    if d < 86400: return f"{int(d/3600)}h ago"
    return f"{int(d/86400)}d ago"

def health_fg_bg(h: str):
    hl = h.lower()
    if hl in ("good","excellent","clean"): return GREEN, GREEN_BG
    if "critical" in hl or "broken" in hl: return RED, RED_BG
    return AMBER, AMBER_BG

# ── Data ──────────────────────────────────────────────────────────────────────

def load_projects():
    if not CONF.exists(): return []
    out = []
    for line in CONF.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'): continue
        parts = line.split('|', 1)
        if len(parts) == 2:
            name, path = parts[0].strip(), Path(parts[1].strip())
            if path.exists():
                out.append({"name": name, "path": path})
    return out

SESSION_FIELDS = {
    'done','next','in_progress','tests','todos','health',
    'build','browser','ux','deploy','mission',
}

def load_session(name: str) -> dict:
    if not SESSIONS.exists(): return {}
    for f in SESSIONS.iterdir():
        if f.stem.lower() == name.lower() and f.suffix == ".md":
            parsed = {}
            for line in f.read_text().splitlines():
                if ':' in line:
                    k, _, v = line.partition(':')
                    k = k.strip().lower()
                    if k in SESSION_FIELDS:
                        parsed[k] = v.strip()
            parsed['_mtime'] = f.stat().st_mtime
            return parsed
    return {}

def extract_mission(claude_md: Path) -> str:
    if not claude_md.exists(): return ""
    text = claude_md.read_text()
    m = re.search(r'##\s+Mission\s*\n(.*?)(?=\n##|\Z)', text, re.DOTALL)
    if m: return m.group(1).strip()[:500]
    for para in text.split('\n\n'):
        para = para.strip()
        if para and not para.startswith(('#','|','`')) and len(para) > 40:
            return para[:350]
    return ""

def detect_stack(path: Path) -> list:
    tags = []
    pkg = path / "package.json"
    if pkg.exists():
        try:
            data = json.loads(pkg.read_text())
            deps = {**data.get("dependencies",{}), **data.get("devDependencies",{})}
            if "next" in deps:        tags.append("Next.js")
            elif "react" in deps:     tags.append("React")
            if "typescript" in deps or (path/"tsconfig.json").exists(): tags.append("TypeScript")
            if "drizzle-orm" in deps: tags.append("Drizzle")
            if "prisma" in deps:      tags.append("Prisma")
            if "@supabase/supabase-js" in deps: tags.append("Supabase")
            if "tailwindcss" in deps: tags.append("Tailwind")
            if "vitest" in deps or "jest" in deps: tags.append("Tests")
        except Exception: pass
    if (path/"requirements.txt").exists() or (path/"pyproject.toml").exists(): tags.append("Python")
    if (path/"Cargo.toml").exists(): tags.append("Rust")
    if (path/"go.mod").exists():     tags.append("Go")
    if not tags and pkg.exists():    tags.append("Node")
    return tags

def git_info(path: Path) -> dict:
    """Return last commit + today's commits."""
    result = {}
    try:
        # Today's commits
        today_raw = subprocess.run(
            ["git","log","--since=midnight","--format=%H|%h|%ai|%s"],
            cwd=path, capture_output=True, text=True, timeout=4).stdout.strip()
        today_commits = []
        for line in today_raw.splitlines():
            if '|' in line:
                parts = line.split('|', 3)
                if len(parts) == 4:
                    _, short, ts, msg = parts
                    try:
                        t = datetime.fromisoformat(ts.strip())
                        time_str = t.strftime("%H:%M")
                    except Exception:
                        time_str = ""
                    today_commits.append({"time": time_str, "msg": msg.strip()[:80]})
        result["today"] = today_commits

        # Last commit (may or may not be today)
        log = subprocess.run(
            ["git","log","-1","--format=%ar|%s"],
            cwd=path, capture_output=True, text=True, timeout=4).stdout.strip()
        branch = subprocess.run(
            ["git","branch","--show-current"],
            cwd=path, capture_output=True, text=True, timeout=4).stdout.strip()
        dirty = subprocess.run(
            ["git","status","--porcelain"],
            cwd=path, capture_output=True, text=True, timeout=4).stdout.strip()
        if log:
            when, msg = log.split('|', 1)
            result.update({"when": when, "msg": msg.strip()[:80],
                           "branch": branch, "dirty": bool(dirty)})
    except Exception:
        result["today"] = []
    return result

def load_prompts() -> dict:
    if PROMPTS.exists():
        try: return json.loads(PROMPTS.read_text())
        except Exception: pass
    return {}

def enrich(proj: dict) -> dict:
    proj["session"] = load_session(proj["name"])
    proj["mission"] = extract_mission(proj["path"] / "CLAUDE.md")
    proj["stack"]   = detect_stack(proj["path"])
    proj["git"]     = git_info(proj["path"])
    return proj

# ── Sidebar ───────────────────────────────────────────────────────────────────

class ProjectItem(QFrame):
    clicked = pyqtSignal(dict)

    def __init__(self, proj: dict):
        super().__init__()
        self.proj = proj
        self._sel = False
        self.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        self._build()
        self._restyle()

    def _build(self):
        lay = QVBoxLayout(self)
        lay.setContentsMargins(12,9,12,9)
        lay.setSpacing(2)

        row = QHBoxLayout(); row.setSpacing(6)
        row.addWidget(L(self.proj["name"], 13, TEXT1, bold=True), 1)
        h = self.proj["session"].get("health","")
        if h:
            fg, _ = health_fg_bg(h)
            dot = QLabel("●"); dot.setStyleSheet(f"color:{fg}; font-size:8px;")
            row.addWidget(dot)
        # Show today commit count if any
        tc = len(self.proj.get("git",{}).get("today",[]))
        if tc:
            c = chip(f"{tc} today", GREEN, GREEN_BG, size=10)
            row.addWidget(c)
        lay.addLayout(row)

        sm = self.proj["session"].get("_mtime")
        if sm:
            sub, sc = f"Active {time_ago(sm)}", TEXT2
        elif self.proj.get("git",{}).get("when"):
            sub, sc = f"Last commit {self.proj['git']['when']}", TEXT3
        else:
            sub, sc = "No recent activity", TEXT3
        lay.addWidget(L(sub, 11, sc))

    def _restyle(self):
        if self._sel:
            self.setStyleSheet(
                f"QFrame{{background:{SURFACE2}; border-radius:10px;"
                f"border-left:3px solid {ACCENT}; margin:1px 4px;}}")
        else:
            self.setStyleSheet(
                f"QFrame{{background:transparent; border-radius:10px;"
                f"border-left:3px solid transparent; margin:1px 4px;}}"
                f"QFrame:hover{{background:{SURFACE};}}")

    def set_selected(self, v: bool):
        self._sel = v; self._restyle()

    def mousePressEvent(self, _):
        self.clicked.emit(self.proj)


class Sidebar(QWidget):
    overview_selected = pyqtSignal()
    project_selected  = pyqtSignal(dict)
    prompts_selected  = pyqtSignal()
    settings_selected = pyqtSignal()

    def __init__(self, projects: list):
        super().__init__()
        self.setFixedWidth(248)
        self.setStyleSheet(f"background:{SIDEBAR}; border-right:1px solid {BORDER};")
        self._items: list[ProjectItem] = []
        self._build(projects)

    def _build(self, projects: list):
        lay = QVBoxLayout(self)
        lay.setContentsMargins(0,0,0,0)
        lay.setSpacing(0)

        # Header
        hw = QWidget(); hw.setStyleSheet(f"background:{SIDEBAR};")
        hl = QVBoxLayout(hw); hl.setContentsMargins(18,22,18,14); hl.setSpacing(2)
        tr = QHBoxLayout()
        tr.addWidget(L("Claude", 20, ACCENT, bold=True))
        tr.addWidget(L("Projects", 20, TEXT1, bold=True))
        tr.addStretch()
        hl.addLayout(tr)
        tc_total = sum(len(p.get("git",{}).get("today",[])) for p in projects)
        summary = f"{len(projects)} projects"
        if tc_total: summary += f"  ·  {tc_total} commits today"
        hl.addWidget(L(summary, 11, TEXT3))
        lay.addWidget(hw)

        # Overview button — primary nav entry
        ov_ss = (f"QPushButton{{background:{ACCENT_BG}; color:{ACCENT};"
                 f"border:none; border-bottom:1px solid {BORDER};"
                 f"padding:12px 18px; font-size:13px; font-weight:700; text-align:left;}}"
                 f"QPushButton:hover{{background:#20266a; color:{TEXT1};}}")
        ov_btn = QPushButton("  📊  All Projects")
        ov_btn.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        ov_btn.setStyleSheet(ov_ss)
        ov_btn.clicked.connect(self.overview_selected.emit)
        lay.addWidget(ov_btn)
        lay.addWidget(divider())
        lay.addSpacing(6)

        # Project list
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setStyleSheet("background:transparent; border:none;")
        pw = QWidget(); pw.setStyleSheet("background:transparent;")
        pl = QVBoxLayout(pw); pl.setContentsMargins(4,0,4,0); pl.setSpacing(0)

        def sort_key(p):
            mt = p.get("session",{}).get("_mtime", 0)
            tc = len(p.get("git",{}).get("today",[]))
            return (0 if (mt or tc) else 1, -(mt or 0))

        for proj in sorted(projects, key=sort_key):
            item = ProjectItem(proj)
            item.clicked.connect(self._on_click)
            pl.addWidget(item)
            self._items.append(item)
        pl.addStretch()
        scroll.setWidget(pw)
        lay.addWidget(scroll, stretch=1)

        # Nav buttons
        nav_ss = (f"QPushButton{{background:{SURFACE}; color:{TEXT2}; border:none;"
                  f"padding:13px 18px; font-size:13px; font-weight:600; text-align:left;}}"
                  f"QPushButton:hover{{background:{SURFACE2}; color:{TEXT1};}}")
        lay.addWidget(divider())
        for txt, sig in [("  📚  Prompt Library", self.prompts_selected),
                         ("  ⚙   Settings",       self.settings_selected)]:
            b = QPushButton(txt)
            b.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
            b.setStyleSheet(nav_ss)
            b.clicked.connect(sig.emit)
            lay.addWidget(b)
            lay.addWidget(divider())

    def _on_click(self, proj: dict):
        for item in self._items:
            item.set_selected(item.proj is proj)
        self.project_selected.emit(proj)


# ── Content panel ─────────────────────────────────────────────────────────────

class ContentPanel(QWidget):
    def __init__(self):
        super().__init__()
        self.setStyleSheet(f"background:{BG};")
        root = QVBoxLayout(self)
        root.setContentsMargins(0,0,0,0)
        self._scroll = QScrollArea()
        self._scroll.setWidgetResizable(True)
        self._scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self._scroll.setStyleSheet("background:transparent; border:none;")
        root.addWidget(self._scroll)
        self._set(self._empty_widget())

    def _set(self, w: QWidget):
        self._scroll.setWidget(w)

    def _empty_widget(self) -> QWidget:
        w = QWidget(); w.setStyleSheet("background:transparent;")
        l = QVBoxLayout(w); l.addStretch()
        l.addWidget(L("← Select a project", 14, TEXT3),
                    alignment=Qt.AlignmentFlag.AlignCenter)
        l.addStretch()
        return w

    def _page(self, pad=32) -> tuple[QWidget, QVBoxLayout]:
        """Returns (widget, layout) for a scrollable page."""
        w = QWidget(); w.setStyleSheet("background:transparent;")
        lay = QVBoxLayout(w)
        lay.setContentsMargins(pad,28,pad,32)
        lay.setSpacing(0)
        return w, lay

    # ── Project profile ───────────────────────────────────────────────────────

    def show_project(self, proj: dict):
        w, lay = self._page(pad=SP3)
        git     = proj.get("git", {})
        session = proj.get("session", {})
        today   = git.get("today", [])
        mission = proj.get("mission", "")

        # ── Hero: name + status bar ───────────────────────────────────────────
        hero = QWidget()
        hero.setStyleSheet(f"background:{CARD}; border-radius:{R_LG}px;"
                           f"border:1px solid {BORDER};")
        hl = QVBoxLayout(hero); hl.setContentsMargins(SP3, SP2+4, SP3, SP2); hl.setSpacing(SP1)

        # Row 1: name + health chip
        nr = QHBoxLayout(); nr.setSpacing(SP1+4)
        name_lbl = L(proj["name"], 32, TEXT1, bold=True)
        nr.addWidget(name_lbl, 1)
        health = session.get("health","")
        if health:
            fg, bg = health_fg_bg(health)
            nr.addWidget(chip(f"● {health.upper()}", fg, bg))
        if git.get("dirty"):
            nr.addWidget(chip("uncommitted", AMBER, AMBER_BG))
        hl.addLayout(nr)

        # Row 2: stack + branch
        meta_row = QHBoxLayout(); meta_row.setSpacing(SP1)
        if proj.get("stack"):
            for t in proj["stack"]: meta_row.addWidget(tag(t, ACCENT, ACCENT_BG))
        if git.get("branch"):
            meta_row.addWidget(tag(f"⎇  {git['branch']}", TEXT3, SURFACE2))
        meta_row.addStretch()
        hl.addLayout(meta_row)

        # Row 3: path (selectable, muted)
        hl.addWidget(L(str(proj["path"]), 11, TEXT3, selectable=True))
        lay.addWidget(hero)
        lay.addSpacing(SP2)
        lay.addWidget(divider())
        lay.addSpacing(SP2+2)

        # ── MISSION ──────────────────────────────────────────────────────────
        mc = card(left_accent=CYAN)
        ml = QVBoxLayout(mc); ml.setContentsMargins(SP2, SP2-2, SP2, SP2-2); ml.setSpacing(SP1)
        ml.addWidget(section_label("MISSION", CYAN))
        if mission:
            ml.addWidget(L(mission, 14, TEXT1, wrap=True, selectable=True))
        else:
            ml.addWidget(L("No mission defined yet — run 🎯 Mission alignment.",
                           13, TEXT2, italic=True, wrap=True))
        # Session mission field (from last run of 'mission' prompt)
        s_mission = session.get("mission","")
        if s_mission and s_mission.lower() not in mission.lower():
            ml.addWidget(divider(BORDER))
            ml.addWidget(L(f"Value prop: {s_mission}", 12, CYAN, wrap=True, selectable=True))
        lay.addWidget(mc)
        lay.addSpacing(SP2)

        # ── TODAY ────────────────────────────────────────────────────────────
        today_date = date.today().strftime("%A, %d %b")
        tc = card(left_accent=GREEN if today else BORDER2)
        tl = QVBoxLayout(tc); tl.setContentsMargins(SP2, SP2-2, SP2, SP2-2); tl.setSpacing(SP1)

        # Header row
        th = QHBoxLayout()
        th.addWidget(section_label("TODAY", GREEN if today else TEXT3))
        th.addSpacing(8)
        th.addWidget(L(today_date, 11, TEXT3))
        th.addStretch()
        if today:
            th.addWidget(chip(f"{len(today)} commit{'s' if len(today)!=1 else ''}",
                              GREEN, GREEN_BG))
        tl.addLayout(th)

        # Session "done" summary (if from today)
        session_today = False
        if session.get("_mtime"):
            session_date = datetime.fromtimestamp(session["_mtime"]).date()
            session_today = (session_date == date.today())

        if session_today and session.get("done"):
            drow = QHBoxLayout(); drow.setSpacing(10)
            dl = L("✓", 16, GREEN, bold=True); dl.setFixedWidth(18)
            drow.addWidget(dl)
            drow.addWidget(L(session["done"], 14, TEXT1, wrap=True, selectable=True), 1)
            tl.addLayout(drow)

        if today:
            tl.addWidget(divider(BORDER))
            for commit in today:
                cr = QHBoxLayout(); cr.setSpacing(10)
                cr.addWidget(L(commit["time"], 11, TEXT3))
                cr.addWidget(L(commit["msg"], 12, TEXT2, selectable=True), 1)
                tl.addLayout(cr)
        elif not session_today:
            tl.addWidget(L("No commits today", 13, TEXT3, italic=True))

        # "Next" action — always show if available (it's the call to action)
        if session.get("next"):
            tl.addWidget(divider(BORDER))
            nrow = QHBoxLayout(); nrow.setSpacing(10)
            nl = L("→", 16, CYAN, bold=True); nl.setFixedWidth(18)
            nrow.addWidget(nl)
            nrow.addWidget(L(session["next"], 14, TEXT1, wrap=True, selectable=True), 1)
            tl.addLayout(nrow)

        lay.addWidget(tc)
        lay.addSpacing(SP2)

        # ── ENGINEERING HEALTH ────────────────────────────────────────────
        eng_fields = {k: session.get(k,"") for k in ('health','build','tests','todos')}
        if any(eng_fields.values()):
            ec = card(left_accent=ACCENT)
            el = QVBoxLayout(ec); el.setContentsMargins(18,14,18,14); el.setSpacing(10)
            el.addWidget(section_label("ENGINEERING HEALTH", ACCENT))
            chips_row = QHBoxLayout(); chips_row.setSpacing(8)
            if eng_fields['health']:
                fg, bg = health_fg_bg(eng_fields['health'])
                chips_row.addWidget(chip(f"● {eng_fields['health'].upper()}", fg, bg))
            if eng_fields['build']:
                bc = eng_fields['build']
                b_ok = "clean" in bc.lower() or "0" in bc
                chips_row.addWidget(chip(f"🔨 {bc}", GREEN if b_ok else RED,
                                         GREEN_BG if b_ok else RED_BG))
            if eng_fields['tests']:
                tc2 = eng_fields['tests']
                t_ok = "fail" not in tc2.lower()
                chips_row.addWidget(chip(f"🧪 {tc2}", GREEN if t_ok else RED,
                                          GREEN_BG if t_ok else RED_BG))
            if eng_fields['todos']:
                td = eng_fields['todos']
                t_zero = td.startswith("0")
                chips_row.addWidget(chip(f"📝 {td} TODOs", GREEN if t_zero else AMBER,
                                          GREEN_BG if t_zero else AMBER_BG))
            chips_row.addStretch()
            el.addLayout(chips_row)
            lay.addWidget(ec)
            lay.addSpacing(18)

        # ── UX & TESTING ──────────────────────────────────────────────────
        ux_val      = session.get("ux","")
        browser_val = session.get("browser","")
        if ux_val or browser_val:
            uc = card(left_accent=PURPLE)
            ul = QVBoxLayout(uc); ul.setContentsMargins(18,14,18,14); ul.setSpacing(10)
            ul.addWidget(section_label("UX & TESTING", PURPLE))
            if browser_val:
                br2 = QHBoxLayout(); br2.setSpacing(10)
                b_ok = "fail" not in browser_val.lower() and "untested" not in browser_val.lower()
                br2.addWidget(chip("🌐 Browser", PURPLE, PURPLE_BG, size=10))
                br2.addWidget(L(browser_val, 13, TEXT1 if b_ok else AMBER,
                                  wrap=True, selectable=True), 1)
                ul.addLayout(br2)
            if ux_val:
                ur = QHBoxLayout(); ur.setSpacing(10)
                ur.addWidget(chip("🎨 UX", PURPLE, PURPLE_BG, size=10))
                ur.addWidget(L(ux_val, 13, TEXT1, wrap=True, selectable=True), 1)
                ul.addLayout(ur)
            lay.addWidget(uc)
            lay.addSpacing(18)

        # ── DEPLOY STATUS ─────────────────────────────────────────────────
        deploy_val = session.get("deploy","")
        if deploy_val:
            dc = card(left_accent=GREEN)
            dl2 = QVBoxLayout(dc); dl2.setContentsMargins(18,12,18,12); dl2.setSpacing(8)
            dl2.addWidget(section_label("LAST DEPLOY", GREEN))
            dr = QHBoxLayout(); dr.setSpacing(10)
            d_ok = "ready" in deploy_val.lower()
            dr.addWidget(chip("🚀 Deploy", GREEN if d_ok else RED,
                               GREEN_BG if d_ok else RED_BG, size=10))
            dr.addWidget(L(deploy_val, 13, TEXT1, wrap=True, selectable=True), 1)
            dl2.addLayout(dr)
            lay.addWidget(dc)
            lay.addSpacing(18)

        # ── OLDER HISTORY (if session not from today) ─────────────────────
        if session and not session_today:
            if any(k in session for k in ('done','in_progress')):
                hc = card()
                hl2 = QVBoxLayout(hc); hl2.setContentsMargins(18,14,18,14); hl2.setSpacing(8)
                h2row = QHBoxLayout()
                h2row.addWidget(section_label("LAST SESSION", TEXT3))
                h2row.addStretch()
                if "_mtime" in session:
                    h2row.addWidget(L(time_ago(session["_mtime"]), 11, TEXT3))
                hl2.addLayout(h2row)
                for key, dot, clr in [("done","✓",GREEN),("in_progress","⋯",AMBER)]:
                    if key not in session: continue
                    row = QHBoxLayout(); row.setSpacing(10)
                    dl3 = L(dot, 14, clr, bold=True); dl3.setFixedWidth(18)
                    row.addWidget(dl3)
                    row.addWidget(L(session[key], 13, TEXT1, wrap=True, selectable=True), 1)
                    hl2.addLayout(row)
                lay.addWidget(hc)
                lay.addSpacing(18)

        # ── Quick actions ─────────────────────────────────────────────────
        ar = QHBoxLayout(); ar.setSpacing(8)
        def open_folder():
            subprocess.Popen(["xdg-open", str(proj["path"])], start_new_session=True)
        def open_terminal():
            p = str(proj["path"])
            for t in ["gnome-terminal","kitty","alacritty","xterm","konsole"]:
                try: subprocess.Popen([t,"--working-directory",p], start_new_session=True); return
                except FileNotFoundError: continue
        for txt, fn in [("📁  Open folder", open_folder),("💻  Terminal", open_terminal)]:
            b = action_btn(txt); b.clicked.connect(fn); ar.addWidget(b)
        ar.addStretch()
        lay.addLayout(ar)
        lay.addStretch()
        self._set(w)

    # ── Overview (all projects) ───────────────────────────────────────────────

    def show_overview(self, projects: list):
        w, lay = self._page(pad=28)

        # ── Header ──
        today_date = date.today().strftime("%A, %d %b %Y")
        hr = QHBoxLayout()
        hr.addWidget(L("All Projects", 26, TEXT1, bold=True), 1)
        hr.addWidget(L(today_date, 13, TEXT3))
        lay.addLayout(hr)
        lay.addSpacing(6)

        # Subtitle: total activity today
        tc_total = sum(len(p.get("git",{}).get("today",[]))  for p in projects)
        active   = sum(1 for p in projects if p.get("git",{}).get("today",[]))
        sub = f"{len(projects)} projects"
        if tc_total: sub += f"  ·  {tc_total} commits across {active} project{'s' if active!=1 else ''} today"
        lay.addWidget(L(sub, 12, TEXT3))
        lay.addSpacing(20)
        lay.addWidget(divider())
        lay.addSpacing(22)

        # ── Project cards (2-column grid) ──
        def sort_key(p):
            tc = len(p.get("git",{}).get("today",[]))
            mt = p.get("session",{}).get("_mtime", 0)
            return (0 if (tc or mt) else 1, -tc, -(mt or 0))

        sorted_projects = sorted(projects, key=sort_key)
        grid = QGridLayout(); grid.setSpacing(14)
        for i, proj in enumerate(sorted_projects):
            grid.addWidget(self._overview_card(proj), i // 2, i % 2)

        container = QWidget(); container.setStyleSheet("background:transparent;")
        container.setLayout(grid)
        lay.addWidget(container)
        lay.addSpacing(28)

        # ── Today's activity feed (all commits, chronological) ──
        all_commits = []
        for p in projects:
            for c in p.get("git",{}).get("today",[]):
                all_commits.append((c["time"], p["name"], c["msg"]))
        # sort by time descending (most recent first)
        all_commits.sort(key=lambda x: x[0], reverse=True)

        if all_commits:
            lay.addWidget(divider())
            lay.addSpacing(22)
            fh = QHBoxLayout()
            fh.addWidget(L("TODAY'S ACTIVITY", 10, GREEN, bold=True))
            fh.addSpacing(8)
            fh.addWidget(L(f"{len(all_commits)} commits", 11, TEXT3))
            fh.addStretch()
            lay.addLayout(fh)
            lay.addSpacing(12)

            fc = card()
            fl = QVBoxLayout(fc); fl.setContentsMargins(18,12,18,14); fl.setSpacing(2)
            for i, (time_str, proj_name, msg) in enumerate(all_commits):
                if i > 0:
                    fl.addWidget(divider(BORDER))
                row = QHBoxLayout(); row.setSpacing(12)
                row.addWidget(L(time_str, 11, TEXT3)); row.setAlignment(row.itemAt(0).widget(), Qt.AlignmentFlag.AlignTop)
                row.addWidget(chip(proj_name, ACCENT, ACCENT_BG, size=10))
                row.addWidget(L(msg, 12, TEXT2, selectable=True), 1)
                fl.addLayout(row)
            lay.addWidget(fc)
            lay.addSpacing(20)

        lay.addStretch()
        self._set(w)

    def _overview_card(self, proj: dict) -> QWidget:
        git     = proj.get("git", {})
        session = proj.get("session", {})
        today   = git.get("today", [])
        health  = session.get("health", "")
        nxt     = session.get("next", "")
        done    = session.get("done", "")

        session_today = False
        if session.get("_mtime"):
            session_today = datetime.fromtimestamp(session["_mtime"]).date() == date.today()

        active = bool(today or session_today)
        accent = GREEN if today else (ACCENT if session_today else BORDER2)

        outer = card(left_accent=accent)
        ol = QVBoxLayout(outer); ol.setContentsMargins(18,14,18,14); ol.setSpacing(10)

        # ── Name row ──
        nr = QHBoxLayout(); nr.setSpacing(8)
        nr.addWidget(L(proj["name"], 15, TEXT1, bold=True), 1)
        if health:
            fg, bg = health_fg_bg(health)
            nr.addWidget(chip(f"● {health.upper()}", fg, bg, size=10))
        ol.addLayout(nr)

        # Stack tags
        if proj.get("stack"):
            sr = QHBoxLayout(); sr.setSpacing(5)
            for t in proj["stack"][:4]: sr.addWidget(tag(t, ACCENT, ACCENT_BG))
            sr.addStretch(); ol.addLayout(sr)

        ol.addWidget(divider(BORDER))

        # ── Today section ──
        if today:
            th = QHBoxLayout()
            th.addWidget(chip(f"🟢 {len(today)} commit{'s' if len(today)!=1 else ''} today",
                              GREEN, GREEN_BG, size=10))
            th.addStretch(); ol.addLayout(th)
            for c in today[:2]:
                cr = QHBoxLayout(); cr.setSpacing(8)
                cr.addWidget(L(c["time"], 10, TEXT3))
                cr.addWidget(L(c["msg"][:60] + ("…" if len(c["msg"])>60 else ""),
                               11, TEXT2, selectable=True), 1)
                ol.addLayout(cr)
            if len(today) > 2:
                ol.addWidget(L(f"+ {len(today)-2} more", 10, TEXT3, italic=True))
        elif session_today and done:
            ol.addWidget(L(f"✓ {done[:70]}{'…' if len(done)>70 else ''}",
                           11, GREEN, wrap=True))
        else:
            when = git.get("when","")
            ol.addWidget(L(f"Last commit {when}" if when else "No recent activity",
                           11, TEXT3, italic=True))

        # ── Engineering chips (build / browser / deploy) ──
        eng_chips = []
        build_v   = session.get("build","")
        browser_v = session.get("browser","")
        deploy_v  = session.get("deploy","")
        if build_v:
            ok = "clean" in build_v.lower() or build_v.startswith("0")
            eng_chips.append((f"🔨 {build_v[:30]}", GREEN if ok else RED, GREEN_BG if ok else RED_BG))
        if browser_v:
            ok = "fail" not in browser_v.lower() and "untested" not in browser_v.lower()
            eng_chips.append((f"🌐 {browser_v[:30]}", PURPLE if ok else AMBER, PURPLE_BG if ok else AMBER_BG))
        if deploy_v:
            ok = "ready" in deploy_v.lower()
            eng_chips.append((f"🚀 {deploy_v[:30]}", GREEN if ok else RED, GREEN_BG if ok else RED_BG))
        if eng_chips:
            er = QHBoxLayout(); er.setSpacing(5)
            for txt, fg, bg in eng_chips: er.addWidget(chip(txt, fg, bg, size=10))
            er.addStretch(); ol.addLayout(er)

        # ── Next action ──
        if nxt:
            ol.addWidget(divider(BORDER))
            nr2 = QHBoxLayout(); nr2.setSpacing(8)
            nr2.addWidget(L("→", 13, CYAN, bold=True))
            nr2.addWidget(L(nxt[:72] + ("…" if len(nxt)>72 else ""),
                            12, TEXT1, wrap=True, selectable=True), 1)
            ol.addLayout(nr2)

        # ── Open project button ──
        open_btn = QPushButton("Open →")
        open_btn.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        open_btn.setStyleSheet(
            f"QPushButton{{background:{SURFACE}; color:{TEXT3}; border:1px solid {BORDER};"
            f"border-radius:7px; padding:5px 14px; font-size:11px; font-weight:600;}}"
            f"QPushButton:hover{{background:{SURFACE2}; color:{TEXT1}; border-color:{ACCENT};}}")
        open_btn.clicked.connect(lambda _, p=proj: self.show_project(p))
        br = QHBoxLayout(); br.addStretch(); br.addWidget(open_btn)
        ol.addLayout(br)

        return outer

    # ── Prompt library ────────────────────────────────────────────────────────

    def show_prompts(self, prompts: dict):
        w, lay = self._page()
        hr = QHBoxLayout()
        hr.addWidget(L("Prompt Library", 24, TEXT1, bold=True), 1)
        hr.addWidget(L(f"{len(prompts)} prompts", 11, TEXT3))
        lay.addLayout(hr)
        lay.addSpacing(4)
        lay.addWidget(L(f"Stored at  {PROMPTS}", 11, TEXT3))
        lay.addSpacing(20)
        lay.addWidget(divider())
        lay.addSpacing(24)

        for cat in CATEGORIES:
            cat_keys = [k for k in cat["keys"] if k in prompts]
            if not cat_keys: continue
            fg, bg = CAT_COLORS[cat["id"]]

            ch = QHBoxLayout(); ch.setSpacing(10)
            ch.addWidget(L(cat["icon"], 18))
            ch.addWidget(L(cat["label"], 17, fg, bold=True))
            ch.addStretch()
            ch.addWidget(chip(str(len(cat_keys)), fg, bg))
            lay.addLayout(ch)
            lay.addSpacing(12)

            for key in cat_keys:
                text = prompts[key]
                icon, title, pk = PROMPT_META.get(key, ("·", key, "—"))
                lay.addWidget(self._prompt_card(icon, title, pk, text, fg, bg))
                lay.addSpacing(8)

            lay.addSpacing(14)
            lay.addWidget(divider())
            lay.addSpacing(22)

        lay.addStretch()
        self._set(w)

    def _prompt_card(self, icon, title, popup_key, text, fg, bg) -> QWidget:
        outer = QFrame()
        outer.setObjectName("pc")
        outer.setStyleSheet(
            "QFrame#pc{background:" + CARD + "; border-radius:12px;"
            "border:1px solid " + BORDER + ";}")
        ol = QVBoxLayout(outer); ol.setContentsMargins(0,0,0,0); ol.setSpacing(0)

        # Card header
        hw = QWidget()
        hw.setStyleSheet(f"background:{SURFACE}; border-radius:11px 11px 0 0;"
                         f"border-bottom:1px solid {BORDER};")
        hl = QHBoxLayout(hw); hl.setContentsMargins(16,11,16,11); hl.setSpacing(10)
        hl.addWidget(L(icon, 15))
        tl = QLabel(title)
        tl.setStyleSheet(f"font-size:14px; color:{TEXT1}; font-weight:700;")
        hl.addWidget(tl, 1)
        if popup_key != "—":
            pk_w = QLabel(f"popup [{popup_key}]")
            pk_w.setStyleSheet(f"color:{fg}; background:{bg}; border-radius:5px;"
                               f"font-size:10px; font-weight:700; padding:2px 8px;")
            hl.addWidget(pk_w)
        copy_btn = QToolButton()
        copy_btn.setText("Copy")
        copy_btn.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        copy_btn.setStyleSheet(
            f"QToolButton{{background:{SURFACE2}; color:{TEXT2}; border:1px solid {BORDER};"
            f"border-radius:6px; padding:3px 10px; font-size:11px; font-weight:600;}}"
            f"QToolButton:hover{{color:{TEXT1}; border-color:{ACCENT};}}")
        copy_btn.clicked.connect(
            (lambda t: lambda: QApplication.clipboard().setText(t))(text))
        hl.addWidget(copy_btn)
        ol.addWidget(hw)

        # Card body
        bw = QWidget(); bw.setStyleSheet(f"background:{CARD};")
        bl = QVBoxLayout(bw); bl.setContentsMargins(16,12,16,14); bl.setSpacing(8)
        preview = text.split('\n')[0][:150]
        if len(preview) < len(text.split('\n')[0]): preview += "…"
        bl.addWidget(L(preview, 12, TEXT2, wrap=True))
        te = QTextEdit(); te.setPlainText(text); te.setReadOnly(True)
        te.setVisible(False); te.setMinimumHeight(100); te.setMaximumHeight(320)
        toggle = QPushButton("▸  View full prompt")
        toggle.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        toggle.setStyleSheet(
            f"QPushButton{{background:transparent; color:{TEXT3}; border:none;"
            f"font-size:11px; padding:0; text-align:left;}}"
            f"QPushButton:hover{{color:{fg};}}")
        def _tog(t=toggle, e=te):
            vis = e.isVisible(); e.setVisible(not vis)
            t.setText("▾  Hide full prompt" if not vis else "▸  View full prompt")
        toggle.clicked.connect(_tog)
        bl.addWidget(toggle); bl.addWidget(te)
        ol.addWidget(bw)
        return outer

    # ── Settings ──────────────────────────────────────────────────────────────

    def show_settings(self):
        s = load_settings()
        w, lay = self._page()

        lay.addWidget(L("Settings", 24, TEXT1, bold=True))
        lay.addSpacing(4)
        lay.addWidget(L(f"Stored at  {SETTINGS}", 11, TEXT3))
        lay.addSpacing(20)
        lay.addWidget(divider())
        lay.addSpacing(24)

        def sec(title, color=ACCENT):
            lay.addWidget(section_label(title, color))
            lay.addSpacing(10)

        # Claude model
        sec("CLAUDE MODEL")
        mc = card()
        ml = QVBoxLayout(mc); ml.setContentsMargins(18,14,18,14); ml.setSpacing(10)
        ml.addWidget(L("Model for reference and new sessions.", 12, TEXT2))
        cb = QComboBox()
        for mid, mlabel in CLAUDE_MODELS: cb.addItem(mlabel, mid)
        cur = s.get("claude_model", DEFAULT_SETTINGS["claude_model"])
        for i in range(cb.count()):
            if cb.itemData(i) == cur: cb.setCurrentIndex(i); break
        ml.addWidget(cb)
        lay.addWidget(mc); lay.addSpacing(18)

        # Whisper model
        sec("VOICE TRANSCRIPTION  (Whisper)", PURPLE)
        wc = card()
        wl = QVBoxLayout(wc); wl.setContentsMargins(18,14,18,14); wl.setSpacing(10)
        wl.addWidget(L("Model used when you press 🎤 in the popup. Larger = more accurate but slower.", 12, TEXT2, wrap=True))
        wr = QHBoxLayout(); wr.setSpacing(8)
        wbtns = {}
        cur_w = s.get("whisper_model", "base")

        def _wss(sel):
            return (f"QPushButton{{background:{ACCENT_BG}; color:{ACCENT};"
                    f"border:1.5px solid {ACCENT}; border-radius:8px;"
                    f"padding:8px 16px; font-size:13px; font-weight:700;}}" if sel else
                    f"QPushButton{{background:{SURFACE}; color:{TEXT2};"
                    f"border:1px solid {BORDER}; border-radius:8px; padding:8px 16px; font-size:13px;}}"
                    f"QPushButton:hover{{background:{SURFACE2}; color:{TEXT1};}}")

        acc_lbl = L(WHISPER_DESC.get(cur_w,""), 11, TEXT3)
        for m in WHISPER_MODELS:
            b = QPushButton(m)
            b.setCheckable(True); b.setChecked(m == cur_w)
            b.setStyleSheet(_wss(m == cur_w))
            b.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
            wbtns[m] = b; wr.addWidget(b)
        wr.addStretch()

        def _sel_w(model):
            for m2, b2 in wbtns.items():
                b2.setChecked(m2 == model); b2.setStyleSheet(_wss(m2 == model))
            acc_lbl.setText(WHISPER_DESC.get(model,""))

        for m, b in wbtns.items():
            b.clicked.connect((lambda mo: lambda: _sel_w(mo))(m))

        wl.addLayout(wr); wl.addWidget(acc_lbl)
        lay.addWidget(wc); lay.addSpacing(18)

        # Countdown
        sec("AUTO-RUN COUNTDOWN", AMBER)
        cc = card()
        cl = QVBoxLayout(cc); cl.setContentsMargins(18,14,18,14); cl.setSpacing(10)
        cl.addWidget(L("Seconds before the popup auto-selects ⚡ Next best task. 0 = disabled.", 12, TEXT2, wrap=True))
        sr2 = QHBoxLayout(); sr2.setSpacing(12)
        slider = QSlider(Qt.Orientation.Horizontal)
        slider.setMinimum(0); slider.setMaximum(60)
        slider.setValue(int(s.get("countdown_secs", 12)))
        slider.setStyleSheet(
            f"QSlider::groove:horizontal{{background:{SURFACE}; height:4px; border-radius:2px;}}"
            f"QSlider::handle:horizontal{{background:{ACCENT}; width:16px; height:16px;"
            f"margin:-6px 0; border-radius:8px;}}"
            f"QSlider::sub-page:horizontal{{background:{ACCENT}; height:4px; border-radius:2px;}}")
        sv = L(f"{slider.value()}s" if slider.value() else "off", 14, ACCENT, bold=True)
        sv.setFixedWidth(40)
        slider.valueChanged.connect(lambda v, lbl=sv: lbl.setText(f"{v}s" if v else "off"))
        sr2.addWidget(slider, 1); sr2.addWidget(sv)
        cl.addLayout(sr2)
        lay.addWidget(cc); lay.addSpacing(24)

        # Save
        save_btn = QPushButton("  Save settings")
        save_btn.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))
        save_btn.setStyleSheet(
            f"QPushButton{{background:{ACCENT_BG}; color:{ACCENT}; border:1.5px solid {ACCENT};"
            f"border-radius:10px; padding:12px 28px; font-size:14px; font-weight:700;}}"
            f"QPushButton:hover{{background:#232870; color:{TEXT1};}}")
        saved = L("", 12, GREEN); saved.setVisible(False)

        def _save():
            save_settings({
                "claude_model":   cb.itemData(cb.currentIndex()),
                "whisper_model":  next((m for m,b in wbtns.items() if b.isChecked()), "base"),
                "countdown_secs": slider.value(),
            })
            saved.setText("✓  Saved"); saved.setVisible(True)

        save_btn.clicked.connect(_save)
        br = QHBoxLayout(); br.addWidget(save_btn); br.addWidget(saved); br.addStretch()
        lay.addLayout(br)
        lay.addStretch()
        self._set(w)


# ── Loader thread ─────────────────────────────────────────────────────────────

class LoaderThread(QThread):
    done = pyqtSignal(list)
    def __init__(self, projects):
        super().__init__(); self._p = projects
    def run(self):
        self.done.emit([enrich(p) for p in self._p])


# ── Main window ───────────────────────────────────────────────────────────────

class Dashboard(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Claude Projects")
        self.setMinimumSize(960, 640)
        self.resize(1160, 760)
        self.setStyleSheet(SS)

        central = QWidget()
        self.setCentralWidget(central)
        self._root = QHBoxLayout(central)
        self._root.setContentsMargins(0,0,0,0)
        self._root.setSpacing(0)
        loading = QLabel("Loading projects…")
        loading.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._root.addWidget(loading)

        raw = load_projects()
        self._loader = LoaderThread(raw)
        self._loader.done.connect(self._on_loaded)
        self._loader.start()

    def _on_loaded(self, projects: list):
        for i in reversed(range(self._root.count())):
            w = self._root.itemAt(i).widget()
            if w: w.deleteLater()

        self._projects = projects
        self._sidebar  = Sidebar(projects)
        self._panel    = ContentPanel()
        self._prompts  = load_prompts()

        self._sidebar.overview_selected.connect(
            lambda: self._panel.show_overview(self._projects))
        self._sidebar.project_selected.connect(self._on_project_selected)
        self._sidebar.prompts_selected.connect(
            lambda: self._panel.show_prompts(self._prompts))
        self._sidebar.settings_selected.connect(self._panel.show_settings)

        self._root.addWidget(self._sidebar)
        self._root.addWidget(self._panel, stretch=1)

        # Default: show overview
        self._panel.show_overview(projects)

    def _on_project_selected(self, proj: dict):
        self._panel.show_project(proj)


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    os.environ.setdefault("DISPLAY", ":0")
    app = QApplication(sys.argv)
    app.setApplicationName("Dev Dashboard")

    # Font stack — UI body text
    for family in ("Inter", "Segoe UI", "Helvetica Neue", "SF Pro Text", "sans-serif"):
        f = QFont(family, 13)
        if f.exactMatch() or family == "sans-serif":
            app.setFont(f)
            break

    apply_palette(app)
    win = Dashboard()
    win.show(); win.raise_(); win.activateWindow()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
