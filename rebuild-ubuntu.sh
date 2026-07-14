#!/usr/bin/env bash
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

ln -sfn "$DIR" "$HOME/.dotfiles"
export DOTFILES_USERNAME="${USER:-$(id -un)}"
export DOTFILES_HOME="$HOME"
exec home-manager switch --impure --flake "$HOME/.dotfiles#$HOME_TARGET"
