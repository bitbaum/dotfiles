# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# ═══════════════════════════════════════════════════
# History
# ═══════════════════════════════════════════════════
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
HISTSIZE=50000
HISTFILESIZE=100000
# Save history after every command (survive crashes)
PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}history -a"

# ═══════════════════════════════════════════════════
# Shell Options
# ═══════════════════════════════════════════════════
shopt -s checkwinsize
shopt -s globstar
# cd into directory by typing its name
shopt -s autocd 2>/dev/null
# Correct minor cd typos
shopt -s cdspell 2>/dev/null

# Make less more friendly for non-text input files
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# ═══════════════════════════════════════════════════
# PATH (deduplicated, order matters)
# ═══════════════════════════════════════════════════
_add_to_path() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$1:$PATH" ;;
    esac
}
_add_to_path "$HOME/.local/bin"
_add_to_path "$HOME/dev/evig/scripts"
_add_to_path "$HOME/dev/fitfoot"
_add_to_path "$HOME/.opencode/bin"
_add_to_path "$HOME/.bun/bin"
export PATH

# ═══════════════════════════════════════════════════
# Prompt (Starship)
# ═══════════════════════════════════════════════════
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init bash)"
else
    # Fallback prompt
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
fi

# ═══════════════════════════════════════════════════
# Color Support
# ═══════════════════════════════════════════════════
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi

# ═══════════════════════════════════════════════════
# Aliases — modern replacements
# ═══════════════════════════════════════════════════
# ls → eza
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons'
    alias ll='eza -la --icons --git'
    alias la='eza -a --icons'
    alias l='eza --icons'
    alias tree='eza --tree --icons'
else
    alias ls='ls --color=auto'
    alias ll='ls -alF'
    alias la='ls -A'
    alias l='ls -CF'
fi

# cat → bat
if command -v bat >/dev/null 2>&1; then
    alias cat='bat --paging=never'
    alias catp='bat'  # with pager
fi

# grep with color
alias grep='grep --color=auto'

# git shortcuts
alias gs='git status'
alias gd='git diff'
alias gl='git log --oneline -20'
alias gp='git push'

# project shortcuts
alias stop-dev='pkill -f "next dev" && pkill -f "strapi develop" && pkill -f "concurrently"'
alias code='flatpak run com.visualstudio.code'

alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# ═══════════════════════════════════════════════════
# Completions
# ═══════════════════════════════════════════════════
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# ═══════════════════════════════════════════════════
# Tool Integrations
# ═══════════════════════════════════════════════════

# direnv
if command -v direnv >/dev/null 2>&1; then
    eval "$(direnv hook bash)"
fi

# fzf — fuzzy finder (Ctrl+R history, Ctrl+T files, Alt+C dirs)
if command -v fzf >/dev/null 2>&1; then
    eval "$(fzf --bash)"
    # Use fd for faster, gitignore-aware file search
    if command -v fd >/dev/null 2>&1; then
        export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
        export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
        export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
    fi
fi

# zoxide — smart cd
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash)"
fi

# nvm (lazy-loaded — only sources on first use of nvm/node/npm/npx/pnpm)
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    # Add nvm's current node to PATH immediately (instant node/npm without full nvm load)
    _NVM_DEFAULT=$(cat "$NVM_DIR/alias/default" 2>/dev/null)
    if [ -n "$_NVM_DEFAULT" ]; then
        for d in "$NVM_DIR/versions/node"/v${_NVM_DEFAULT}*/bin; do
            [ -d "$d" ] && _add_to_path "$d" && break
        done
    fi
    unset _NVM_DEFAULT

    _nvm_lazy_load() {
        unset -f nvm node npm npx pnpm corepack 2>/dev/null
        \. "$NVM_DIR/nvm.sh"
        [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    }
    nvm() { _nvm_lazy_load; nvm "$@"; }

    # Auto-switch Node version when entering a dir with .nvmrc
    _nvm_auto_switch() {
        if [ "$PWD" != "${_NVM_LAST_DIR:-}" ] && [ -f ".nvmrc" ]; then
            _NVM_LAST_DIR="$PWD"
            _nvm_lazy_load
            nvm use --silent 2>/dev/null
        elif [ "$PWD" != "${_NVM_LAST_DIR:-}" ]; then
            _NVM_LAST_DIR="$PWD"
        fi
    }
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND$'\n'}_nvm_auto_switch"
fi

# bun
export BUN_INSTALL="$HOME/.bun"

# Homebrew (cached — regenerates only when brew binary changes)
_BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"
if [ -f "$_BREW_BIN" ]; then
    _BREW_ENV_CACHE="$HOME/.cache/brew-shellenv.sh"
    if [ ! -f "$_BREW_ENV_CACHE" ] || [ "$_BREW_BIN" -nt "$_BREW_ENV_CACHE" ]; then
        env -i HOME="$HOME" SHELL="$SHELL" "$_BREW_BIN" shellenv > "$_BREW_ENV_CACHE"
    fi
    source "$_BREW_ENV_CACHE"
    unset _BREW_ENV_CACHE
fi
unset _BREW_BIN

# git — use delta as pager
if command -v delta >/dev/null 2>&1; then
    export GIT_PAGER="delta"
fi

# OpenClaw
if [ -f "$HOME/.openclaw/completions/openclaw.bash" ]; then
    source "$HOME/.openclaw/completions/openclaw.bash"
fi
alias pig='openclaw tui --session "$(date +%s)"'

# GitHub CLI shortcuts
alias ghi='gh issue list'
alias ghic='gh issue create'
alias ghpr='gh pr list'
alias ghprc='gh pr create'
alias ghprv='gh pr view --web'
alias ghrc='gh repo clone'

# ═══════════════════════════════════════════════════
# Dev Stack Manager
# ═══════════════════════════════════════════════════
# Usage: dev up evig | dev down orangecat | dev status
dev() {
    local action="${1:-status}" project="${2:-}"

    case "$action" in
        up)
            case "$project" in
                evig|ev)
                    echo "Starting evig stack..."
                    docker compose -f ~/dev/evig/docker-compose.yml up -d
                    ;;
                orangecat|oc)
                    echo "Starting OrangeCat (Supabase) stack..."
                    (cd ~/dev/orangecat && npx supabase start)
                    # Supabase sets restart=always; override to prevent boot-start
                    docker ps --filter "name=supabase_.*_orangecat" -q | xargs -r docker update --restart=no >/dev/null 2>&1
                    ;;
                *)
                    echo "Unknown project: $project"
                    echo "Available: evig (ev), orangecat (oc)"
                    return 1
                    ;;
            esac
            ;;
        down)
            case "$project" in
                evig|ev)
                    echo "Stopping evig stack..."
                    docker compose -f ~/dev/evig/docker-compose.yml down
                    ;;
                orangecat|oc)
                    echo "Stopping OrangeCat (Supabase) stack..."
                    cd ~/dev/orangecat && npx supabase stop && cd - >/dev/null
                    ;;
                all)
                    echo "Stopping all dev stacks..."
                    docker compose -f ~/dev/evig/docker-compose.yml down 2>/dev/null
                    (cd ~/dev/orangecat && npx supabase stop) 2>/dev/null
                    ;;
                *)
                    echo "Unknown project: $project"
                    echo "Available: evig (ev), orangecat (oc), all"
                    return 1
                    ;;
            esac
            ;;
        status|st)
            echo "Docker containers:"
            docker ps --format "  {{.Names}}: {{.Status}} ({{.Ports}})" 2>/dev/null | sed 's/0.0.0.0://g; s/, \[::\]:[0-9->\/tcp]*//g' || echo "  Docker not running"
            ;;
        *)
            echo "Usage: dev <up|down|status> [project]"
            echo "Projects: evig (ev), orangecat (oc), all"
            ;;
    esac
}

# ═══════════════════════════════════════════════════
# Git Health — check all repos at once
# ═══════════════════════════════════════════════════
git-health() {
    local dev_dir="${1:-$HOME/dev}"
    local dirty=0 ahead=0 clean=0

    for d in "$dev_dir"/*/; do
        [ -d "$d/.git" ] || continue
        local name=$(basename "$d")
        local status=""

        local n_dirty=$(git -C "$d" status --porcelain 2>/dev/null | wc -l)
        local n_ahead=$(git -C "$d" log --oneline @{u}..HEAD 2>/dev/null | wc -l)
        local branch=$(git -C "$d" branch --show-current 2>/dev/null)

        if [ "$n_dirty" -gt 0 ] || [ "$n_ahead" -gt 0 ]; then
            [ "$n_dirty" -gt 0 ] && status+=" ${n_dirty} dirty" && ((dirty++))
            [ "$n_ahead" -gt 0 ] && status+=" ${n_ahead} unpushed" && ((ahead++))
            printf "  \033[33m%-20s\033[0m (%s)%s\n" "$name" "$branch" "$status"
        else
            ((clean++))
        fi
    done

    echo ""
    echo "  $clean clean, $dirty dirty, $ahead with unpushed commits"
}

# ═══════════════════════════════════════════════════
# Stranded work — finished work that is going nowhere
# ═══════════════════════════════════════════════════
# git-health above answers "what is dirty", which is every repo someone is
# working in. That number was 118 for orangecat every day for ten days and
# changed nobody's behaviour, because a count that is equally true at minute
# five and at day ten reads as noise.
#
# This one only speaks when work has AGED past a threshold, and says nothing
# otherwise. It prints from cache so it never costs a prompt, and refreshes in
# the background when that cache goes stale.
fleet-stranded() { bash "$HOME/dev/dotfiles/scripts/fleet/stranded-work.sh" "${1:-}"; }

if [ -z "${BASH_EXECUTION_STRING:-}" ] && [ -f "$HOME/dev/dotfiles/scripts/fleet/stranded-work.sh" ]; then
    bash "$HOME/dev/dotfiles/scripts/fleet/stranded-work.sh" --shell 2>/dev/null
fi

# ═══════════════════════════════════════════════════
# Zellij Auto-Attach
# ═══════════════════════════════════════════════════
# Only auto-attach for genuine human login terminals. Skip when:
#   - already inside zellij ($ZELLIJ set), or
#   - this is a programmatic `bash -c` launch ($BASH_EXECUTION_STRING set),
#     e.g. the FleetCrown Fleet Runner spawning `bash -lic '... && claude'`
#     for an owned PTY. Auto-launching zellij there hijacks the runner's PTY
#     before Claude can own it, so injected prompts never reach Claude.
if [ -z "${ZELLIJ:-}" ] && [ -z "${BASH_EXECUTION_STRING:-}" ] && command -v zellij >/dev/null 2>&1; then
    if zellij list-sessions -ns 2>/dev/null | grep -q .; then
        zellij attach
    else
        zellij
    fi
fi

# ═══════════════════════════════════════════════════
# Agent + Cockpit helpers with Zellij Tab Awareness
# ═══════════════════════════════════════════════════
_agent_resolve_project_dir() {
    local CONFIG="$HOME/.config/claude-projects.conf"
    [ -f "$CONFIG" ] || return 1

    local TAB_NAME TMP="/tmp/_claude_zt_$$.txt"
    zellij action dump-layout > "$TMP" 2>/dev/null
    TAB_NAME=$(grep 'focus=true' "$TMP" | grep 'tab name=' | sed 's/.*tab name="\([^"]*\)".*/\1/')
    rm -f "$TMP"
    [ -z "$TAB_NAME" ] && return 1

    local DIR
    DIR=$(while IFS='|' read -r name dir; do
        [[ "$name" =~ ^#.*$ ]] && continue
        [ -z "$name" ] && continue
        local clean_tab=$(echo "$TAB_NAME" | sed 's/[$[:space:]]*$//')
        local clean_name=$(echo "$name" | sed 's/[$[:space:]]*$//')
        if [ "${clean_tab,,}" = "${clean_name,,}" ]; then
            echo "$dir"
            break
        fi
    done < "$CONFIG")

    [ -z "$DIR" ] && return 1
    [ -d "$DIR" ] || return 1
    echo "$DIR"
}

_agent_cd_from_tab_if_home() {
    [ "$PWD" = "$HOME" ] || return 0
    [ -n "${ZELLIJ:-}" ] || return 0

    local PROJECT_DIR
    PROJECT_DIR=$(_agent_resolve_project_dir)
    if [ -n "$PROJECT_DIR" ]; then
        echo "  -> Tab -> $PROJECT_DIR"
        cd "$PROJECT_DIR" || return 1
    fi
}

claude() {
    _agent_cd_from_tab_if_home || true

    local SESSION_DIR="$HOME/.claude/sessions"
    mkdir -p "$SESSION_DIR"

    local DIR_HASH=$(echo "$(pwd)" | md5sum | cut -d' ' -f1)
    local SESSION_FILE="$SESSION_DIR/$DIR_HASH.txt"
    local PROJECT=$(basename "$(pwd)")

    if [ -f "$SESSION_FILE" ]; then
        local SAVED_TIME=$(cut -d'|' -f2 "$SESSION_FILE" 2>/dev/null || echo "0")
        local NOW=$(date +%s)
        local DIFF=$((NOW - SAVED_TIME))

        if [ $DIFF -gt 120 ] && [ $DIFF -lt 172800 ]; then
            local SAVED_PROJECT=$(cut -d'|' -f1 "$SESSION_FILE")
            local HOURS=$((DIFF / 3600))
            local MINS=$(((DIFF % 3600) / 60))

            local TIME_AGO=""
            if [ $HOURS -gt 0 ]; then
                TIME_AGO="${HOURS}h ${MINS}m ago"
            else
                TIME_AGO="${MINS}m ago"
            fi

            echo ""
            echo "  Previous session: $SAVED_PROJECT ($TIME_AGO)"
            echo "  Tell Claude: \"continue\""
            echo ""
        fi
    fi

    echo "$PROJECT|$(date +%s)|$(pwd)" > "$SESSION_FILE"

    # Write tab identity keyed by ZELLIJ_PANE_ID so Claude can detect its project
    # even after context-limit continuations (which don't re-run this wrapper).
    if [ -n "$ZELLIJ_PANE_ID" ]; then
        local _tab
        _tab=$(zellij action dump-layout 2>/dev/null \
               | grep 'focus=true' \
               | grep 'tab name=' \
               | sed 's/.*tab name="\([^"]*\)".*/\1/' \
               | head -1)
        [ -n "$_tab" ] && printf '%s' "$_tab" > "/tmp/claude-pane-${ZELLIJ_PANE_ID}"

        # Record which monitor the cursor is on right now — cursor is in the terminal
        # at invocation time, so this is the terminal's screen. beacon.py reads this.
        python3 "$HOME/dev/cockpit/scripts/record-terminal-screen.py" \
            "${ZELLIJ_PANE_ID}" 2>/dev/null &
    fi

    command claude "$@"
    rm -f "/tmp/claude-pane-${ZELLIJ_PANE_ID}" "/tmp/claude-screen-${ZELLIJ_PANE_ID}"
}

codex() {
    _agent_cd_from_tab_if_home || true
    command codex --no-alt-screen "$@"
}

cockpit() {
    cd "$HOME/dev/cockpit" || return 1
    npm run dev "$@"
}

# Secrets (passwords, tokens) — loaded from .env, which is gitignored
[ -f "$HOME/.env" ] && source "$HOME/.env"

# --- Agent Orchestration Wrappers ---
_agent_pre_launch() {
    _agent_cd_from_tab_if_home || true
    if [ -n "$ZELLIJ_PANE_ID" ]; then
        local _tab
        _tab=$(zellij action dump-layout 2>/dev/null | grep 'focus=true' | grep 'tab name=' | sed 's/.*tab name="\([^"]*\)".*/\1/' | head -1)
        if [ -n "$_tab" ]; then
            printf '%s' "$_tab" > "/tmp/agent-tab-$$"
            printf '%s' "$_tab" > "/tmp/claude-tab-$$"
            printf '%s' "$_tab" > "/tmp/claude-pane-${ZELLIJ_PANE_ID}"
        fi
    fi
}

_agent_post_launch() {
    # Keep shell PID -> tab mapping available after the agent exits so Stop/Notification
    # hooks can resolve the exact originating tab even for projects with multiple aliases.
    rm -f "/tmp/claude-pane-${ZELLIJ_PANE_ID}"

    # Belt-and-suspenders: drop any leftover keep-awake power inhibitor for this
    # pane. The Stop hook normally releases it per-turn and a watchdog covers hard
    # kills; this guarantees cleanup on a normal exit too. See ~/.claude/hooks/keep-awake-*.sh
    local _pf="/tmp/claude-inhibit-${ZELLIJ_PANE_ID}.pid"
    if [ -f "$_pf" ]; then
        local _hp; _hp=$(cat "$_pf" 2>/dev/null)
        [ -n "$_hp" ] && { pkill -TERM -P "$_hp" 2>/dev/null; kill -TERM "$_hp" 2>/dev/null; }
        rm -f "$_pf"
    fi
}

gemini() {
    _agent_pre_launch
    local _status _next_prompt _start _elapsed
    local -a _base_args
    _base_args=("$@")

    while true; do
        _start=$(date +%s)
        command gemini "${_base_args[@]}"
        _status=$?
        _elapsed=$(( $(date +%s) - _start ))

        if [ ! -x "$HOME/dev/cockpit/scripts/agent-hook-bridge.sh" ]; then
            _agent_post_launch
            return $_status
        fi

        # Startup crash guard: don't fire beacon if gemini exited non-zero in <3s
        if [ "$_status" -ne 0 ] && [ "$_elapsed" -lt 3 ]; then
            _agent_post_launch
            return $_status
        fi

        _next_prompt=$(
            jq -nc --arg cwd "$PWD" '{cwd:$cwd}' \
                | AGENT_BRIDGE_EMIT_PROMPT=1 "$HOME/dev/cockpit/scripts/agent-hook-bridge.sh" stop 2>>/tmp/agent-hooks.log
        ) || _next_prompt=""

        # Idle-spiral guard — see ~/.claude/bin/autopilot-needs-fire.
        # Returns exit 1 when the project's session.md shows a no-op pattern
        # AND no fire signals (working/critical-health/blocker/inbox/dirty
        # tree/stale session) are pending. Skips the re-invocation rather
        # than burning ~3k tokens on a no-op turn.
        if [ -n "$_next_prompt" ] && [ -x "$HOME/.claude/bin/autopilot-needs-fire" ]; then
            _project_slug=""
            if [ -n "${ZELLIJ_PANE_ID:-}" ] && [ -f "/tmp/claude-pane-${ZELLIJ_PANE_ID}" ]; then
                _project_slug=$(cat "/tmp/claude-pane-${ZELLIJ_PANE_ID}" 2>/dev/null)
            fi
            [ -z "$_project_slug" ] && _project_slug=$(basename "$PWD")
            if ! "$HOME/.claude/bin/autopilot-needs-fire" "$_project_slug" 2>/dev/null; then
                _agent_post_launch
                return $_status
            fi
        fi

        if [ -z "$_next_prompt" ]; then
            _agent_post_launch
            return $_status
        fi

        _base_args=("$_next_prompt")
    done
}

# Override existing claude/codex to use agnostic tab resolution
claude() {
    _agent_pre_launch
    # Isolate into a worktree if this repo's main checkout is already in use by
    # another live session (no-op for a solo session). See _claude_autoworktree_*.
    _claude_autoworktree_enter
    # Hold an "idle" inhibitor for the duration of the session so active work
    # won't idle-suspend on battery. Only the idle timer is inhibited -- a
    # lid-close still suspends, so bagging the laptop always sleeps. Falls back
    # cleanly if systemd-inhibit or the resolved binary is missing.
    local _claude_bin
    _claude_bin=$(type -P claude)
    if [ -n "$_claude_bin" ] && command -v systemd-inhibit >/dev/null 2>&1; then
        systemd-inhibit --what=idle --who=claude --why="Active coding session" "$_claude_bin" "$@"
    else
        command claude "$@"
    fi
    _claude_autoworktree_leave
    _agent_post_launch
}

codex() {
    _agent_pre_launch
    local _status _next_prompt _start _elapsed
    local -a _base_args
    _base_args=("$@")

    while true; do
        _start=$(date +%s)
        command codex --no-alt-screen "${_base_args[@]}"
        _status=$?
        _elapsed=$(( $(date +%s) - _start ))

        if [ ! -x "$HOME/dev/cockpit/scripts/agent-hook-bridge.sh" ]; then
            _agent_post_launch
            return $_status
        fi

        # Startup crash guard: don't fire beacon if codex exited non-zero in <3s
        if [ "$_status" -ne 0 ] && [ "$_elapsed" -lt 3 ]; then
            _agent_post_launch
            return $_status
        fi

        _next_prompt=$(
            jq -nc --arg cwd "$PWD" '{cwd:$cwd}' \
                | AGENT_BRIDGE_EMIT_PROMPT=1 "$HOME/dev/cockpit/scripts/agent-hook-bridge.sh" stop 2>>/tmp/agent-hooks.log
        ) || _next_prompt=""

        # Idle-spiral guard — see ~/.claude/bin/autopilot-needs-fire.
        # Returns exit 1 when the project's session.md shows a no-op pattern
        # AND no fire signals (working/critical-health/blocker/inbox/dirty
        # tree/stale session) are pending. Skips the re-invocation rather
        # than burning ~3k tokens on a no-op turn.
        if [ -n "$_next_prompt" ] && [ -x "$HOME/.claude/bin/autopilot-needs-fire" ]; then
            _project_slug=""
            if [ -n "${ZELLIJ_PANE_ID:-}" ] && [ -f "/tmp/claude-pane-${ZELLIJ_PANE_ID}" ]; then
                _project_slug=$(cat "/tmp/claude-pane-${ZELLIJ_PANE_ID}" 2>/dev/null)
            fi
            [ -z "$_project_slug" ] && _project_slug=$(basename "$PWD")
            if ! "$HOME/.claude/bin/autopilot-needs-fire" "$_project_slug" 2>/dev/null; then
                _agent_post_launch
                return $_status
            fi
        fi

        if [ -z "$_next_prompt" ]; then
            _agent_post_launch
            return $_status
        fi

        _base_args=("$_next_prompt")
    done
}

# >>> grok installer >>>
export PATH="$HOME/.grok/bin:$PATH"
[[ -r "$HOME/.grok/completions/bash/grok.bash" ]] && source "$HOME/.grok/completions/bash/grok.bash"
# <<< grok installer <<<


# Added by Antigravity CLI installer
export PATH="/home/g/.local/bin:$PATH"

# Expose ~/.claude/bin (wt worktree helper + autopilot tools) on PATH.
# Additive; safe to remove. See `wt --help` for isolated-worktree workflow.
case ":$PATH:" in
  *":$HOME/.claude/bin:"*) ;;
  *) export PATH="$HOME/.claude/bin:$PATH" ;;
esac

# ── Auto-worktree: isolate concurrent same-repo sessions ──────────────────────
# If another LIVE `claude` session already holds this repo's MAIN checkout, move
# this session into a fresh git worktree so the two never collide (branch swaps,
# shared index, shared .next). A solo session is unchanged — it just claims the
# main checkout. Opt out for one session with:  CLAUDE_NO_AUTOWT=1 claude
# The lock keys on the main checkout's path and stores the holding shell's PID,
# so a crashed session's stale lock is detected (kill -0) and taken over.
_CLAUDE_WT_LOCK=""
_claude_autoworktree_enter() {
    [ -n "${CLAUDE_NO_AUTOWT:-}" ] && return 0
    command -v git >/dev/null 2>&1 || return 0
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
    # A linked worktree has a .git FILE (not dir) → already isolated, nothing to do.
    [ -f "$root/.git" ] && return 0

    local lockdir="/tmp/claude-wt-locks"
    mkdir -p "$lockdir" 2>/dev/null || return 0
    local lock; lock="$lockdir/$(printf '%s' "$root" | md5sum | cut -d' ' -f1)"

    if [ -f "$lock" ]; then
        local pid; pid=$(cat "$lock" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            # Contention → spin up an isolated worktree and move into it.
            local task wtdir
            task="auto-$(date +%H%M%S)-$$"
            wtdir="$(dirname "$root")/$(basename "$root")-wt/$task"
            if "$HOME/.claude/bin/wt" "$task" >/dev/null 2>&1 && cd "$wtdir" 2>/dev/null; then
                export CLAUDE_WORKTREE_DIR="$wtdir"
                echo "  ⚠ $(basename "$root") main checkout is busy (pid $pid) — isolated this session:"
                echo "    → $wtdir  (branch wip/$task)"
                return 0
            fi
            echo "  ⚠ auto-worktree failed; staying in shared checkout — watch for collisions"
            return 0
        fi
    fi
    # Free or stale → claim the main checkout for this session.
    printf '%s' "$$" > "$lock" 2>/dev/null && _CLAUDE_WT_LOCK="$lock"
}
_claude_autoworktree_leave() {
    [ -n "$_CLAUDE_WT_LOCK" ] && rm -f "$_CLAUDE_WT_LOCK" 2>/dev/null
    _CLAUDE_WT_LOCK=""
}
