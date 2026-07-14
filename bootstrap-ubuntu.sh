#!/usr/bin/env bash
# Takes a fresh Ubuntu 24.04 server from nothing to a Home Manager config.
# Run this once. After it finishes, use ./rebuild-ubuntu.sh for later changes.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ ! -r /etc/os-release ]]; then
  echo "Error: /etc/os-release is missing; Ubuntu 24.04 is required." >&2
  exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
  echo "Error: Ubuntu 24.04 is required; found ${PRETTY_NAME:-unknown OS}." >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64) HOME_TARGET="ubuntu-x86_64" ;;
  aarch64|arm64) HOME_TARGET="ubuntu-aarch64" ;;
  *)
    echo "Error: unsupported architecture $(uname -m); expected x86_64 or aarch64." >&2
    exit 1
    ;;
esac

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Error: run this script as the target user, not as root." >&2
  exit 1
fi

echo "==> Step 1: Ubuntu integration packages"
sudo apt-get update
sudo apt-get install -y \
  ca-certificates curl docker.io xz-utils zsh \
  fonts-noto-color-emoji xvfb \
  libasound2t64 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 \
  libcairo2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 \
  libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 \
  libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2

echo "==> Step 2: Determinate Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> Step 3: symlink this repo to ~/.dotfiles"
ln -sfn "$DIR" "$HOME/.dotfiles"

echo "==> Step 4: first Home Manager switch"
export DOTFILES_USERNAME="${USER:-$(id -un)}"
export DOTFILES_HOME="$HOME"
nix run github:nix-community/home-manager/release-26.05 -- \
  switch --impure --flake "$HOME/.dotfiles#$HOME_TARGET"

echo "==> Step 5: set Zsh as the login shell"
if [[ "${SHELL:-}" != "/usr/bin/zsh" ]]; then
  sudo chsh -s /usr/bin/zsh "$DOTFILES_USERNAME"
else
  echo "    Zsh is already the login shell, skipping"
fi

echo "==> Step 6: enable Docker"
sudo systemctl enable --now docker.service
if id -nG "$DOTFILES_USERNAME" | tr ' ' '\n' | grep -qx docker; then
  echo "    $DOTFILES_USERNAME is already in the docker group, skipping"
else
  sudo usermod -aG docker "$DOTFILES_USERNAME"
fi

echo "==> Done. Start a new login session, run 'codex login', and use ./rebuild-ubuntu.sh for future changes."
