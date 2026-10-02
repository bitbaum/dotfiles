#!/usr/bin/env bash
# One-time npm bootstrap for @bitbaum kits: first publish of packages npm has
# never seen, and a trusted publisher (GitHub OIDC, publish.yml) on each, so
# every later release is just `git push origin vX.Y.Z` with no login and no
# passkey. npm asks for the passkey in the browser on each write below — that
# is npm's 2FA, once per package, never again after this.
#
#   bash ~/dev/dotfiles/scripts/npm-bootstrap-kits.sh
set -uo pipefail
NEW=(chatkit)                                           # not on npm yet
# A laptop cannot attest provenance ("provider: null"); the first publish goes
# without it, every CI publish after it carries it.
TRUST=(sitekit limitkit chatkit design-tokens paykit)   # get OIDC publishing

npm whoami >/dev/null 2>&1 || npm login || exit 1
echo "npm: signed in as $(npm whoami)"

name() { node -p "require('$HOME/dev/$1/package.json').name"; }   # limitkit is unscoped

for p in "${NEW[@]}"; do
  if npm view "$(name "$p")" version >/dev/null 2>&1; then echo "$p: already on npm"; continue; fi
  tag=$(git -C "$HOME/dev/$p" fetch -q --tags && git -C "$HOME/dev/$p" tag --sort=-v:refname | head -1)
  dir=$(mktemp -d); git -C "$HOME/dev/$p" worktree add -q --detach "$dir" "$tag" || continue
  install="pnpm install --frozen-lockfile --ignore-scripts"
  [ -f "$dir/package-lock.json" ] && install="npm ci --ignore-scripts"    # limitkit uses npm
  ( cd "$dir" && $install >/dev/null && npm run build >/dev/null \
    && npm publish --access public --provenance=false ) && echo "$p $tag: PUBLISHED" || echo "$p $tag: publish FAILED"
  git -C "$HOME/dev/$p" worktree remove --force "$dir"
done

for p in "${TRUST[@]}"; do
  npm trust github "$(name "$p")" --repo "bitbaum/$p" --file publish.yml --yes \
    && echo "$p: trusted publisher set" || echo "$p: trust FAILED (or already set)"
done
echo "Done. Tell Claude — it re-runs the waiting publishes (sitekit 0.3.1)."
