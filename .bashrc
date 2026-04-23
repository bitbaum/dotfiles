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
_add_to_path "$HOME/dev/revampit/scripts"
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
# Usage: dev up revampit | dev down orangecat | dev status
dev() {
    local action="${1:-status}" project="${2:-}"

    case "$action" in
        up)
            case "$project" in
                revampit|ri)
                    echo "Starting RevampIT stack..."
                    docker compose -f ~/dev/revampit/docker-compose.yml up -d
                    ;;
                orangecat|oc)
                    echo "Starting OrangeCat (Supabase) stack..."
                    (cd ~/dev/orangecat && npx supabase start)
                    # Supabase sets restart=always; override to prevent boot-start
                    docker ps --filter "name=supabase_.*_orangecat" -q | xargs -r docker update --restart=no >/dev/null 2>&1
                    ;;
                *)
                    echo "Unknown project: $project"
                    echo "Available: revampit (ri), orangecat (oc)"
                    return 1
                    ;;
            esac
            ;;
        down)
            case "$project" in
                revampit|ri)
                    echo "Stopping RevampIT stack..."
                    docker compose -f ~/dev/revampit/docker-compose.yml down
                    ;;
                orangecat|oc)
                    echo "Stopping OrangeCat (Supabase) stack..."
                    cd ~/dev/orangecat && npx supabase stop && cd - >/dev/null
                    ;;
                all)
                    echo "Stopping all dev stacks..."
                    docker compose -f ~/dev/revampit/docker-compose.yml down 2>/dev/null
                    (cd ~/dev/orangecat && npx supabase stop) 2>/dev/null
                    ;;
                *)
                    echo "Unknown project: $project"
                    echo "Available: revampit (ri), orangecat (oc), all"
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
            echo "Projects: revampit (ri), orangecat (oc), all"
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
# Zellij Auto-Attach
# ═══════════════════════════════════════════════════
if [ -z "${ZELLIJ:-}" ] && command -v zellij >/dev/null 2>&1; then
    if zellij list-sessions -ns 2>/dev/null | grep -q .; then
        zellij attach
    else
        zellij -l projects
    fi
fi

# ═══════════════════════════════════════════════════
# Claude Code — Session Recovery with Zellij Tab Awareness
# ═══════════════════════════════════════════════════
_claude_resolve_project_dir() {
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

claude() {
    if [ "$PWD" = "$HOME" ] && [ -n "${ZELLIJ:-}" ]; then
        local PROJECT_DIR
        PROJECT_DIR=$(_claude_resolve_project_dir)
        if [ -n "$PROJECT_DIR" ]; then
            echo "  -> Tab -> $PROJECT_DIR"
            cd "$PROJECT_DIR" || true
        fi
    fi

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
    command claude "$@"
}

# Secrets (passwords, tokens) — loaded from .env, which is gitignored
[ -f "$HOME/.env" ] && source "$HOME/.env"
alias claude-dashboard='DISPLAY=:0 python3 ~/.claude/hooks/claude-dashboard.py &'
