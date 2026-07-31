#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=scripts/lib-detect.sh
. "$DIR/scripts/lib-detect.sh"

require_ubuntu_2404
HOME_TARGET="$(home_target_for_arch)"

ln -sfn "$DIR" "$HOME/.dotfiles"
export DOTFILES_USERNAME="${USER:-$(id -un)}"
export DOTFILES_HOME="$HOME"
home-manager switch --impure --flake "$HOME/.dotfiles#$HOME_TARGET"

CURRENT_LOGIN_SHELL="$(getent passwd "$DOTFILES_USERNAME" | cut -d: -f7)"
if [[ "$CURRENT_LOGIN_SHELL" != "/usr/bin/zsh" ]]; then
  echo "==> Restoring Zsh as the login shell"
  sudo chsh -s /usr/bin/zsh "$DOTFILES_USERNAME"
fi
