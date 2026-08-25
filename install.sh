#!/bin/bash
set -e

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link() {
  local src="$DOTFILES/$1"
  local dst="$HOME/$1"

  mkdir -p "$(dirname "$dst")"

  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "  ok  $dst"
    return
  fi

  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$dst" "$dst.bak"
    echo "  bak $dst → $dst.bak"
  fi

  ln -sf "$src" "$dst"
  echo "  ln  $dst → $src"
}

echo "Installing dotfiles..."

# Claude Code
link .claude/CLAUDE.md
link .claude/settings.json
link .claude/hooks
link .claude/skills/fix-types
link .claude/skills/write-tests
link .claude/skills/fix-lint

# Git
link .config/git/hooks/pre-commit
link .config/git/hooks/pre-push
link .config/git/ignore

# Shell
link .bashrc

# Terminal
link .config/kitty/kitty.conf
link .config/starship.toml
link .config/zellij/config.kdl

# Project mapping
link .config/claude-projects.conf
link .config/claude-prompts-meta.json

# Editor
link .editorconfig

# SSH config (not keys)
link .ssh/config

echo "Done."
