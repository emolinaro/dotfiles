#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=scripts/lib-nix.sh
. "$DIR/scripts/lib-nix.sh"

ln -sfn "$DIR" ~/.dotfiles

# Nix itself belongs to the Determinate installer, and root keeps its own eval
# and fetcher caches. A sudo-only build therefore tends to pull whole source
# trees into the privileged step, where a stale lock is invisible and stalls
# forever. Do the fetching and building here instead, as the invoking user,
# with a watchdog that clears a lock deadlock and retries.
if [[ "${DOTFILES_SKIP_PRIME:-0}" != "1" ]]; then
  nix_prime_store "$DIR"
fi

exec sudo darwin-rebuild switch --impure --flake ~/.dotfiles#mac
