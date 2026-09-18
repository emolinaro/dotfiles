#!/usr/bin/env bash
# Takes a fresh supported Linux server from nothing to a Home Manager config.
# Run this once. After it finishes, use ./rebuild.sh for later changes.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
# shellcheck source=scripts/lib-detect.sh
. "$DIR/scripts/lib-detect.sh"

require_supported_linux_distro
HOME_TARGET="$(home_target_for_linux_arch)"
DISTRO="$(linux_distro_id)"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Error: run this script as the target user, not as root." >&2
  exit 1
fi

install_ubuntu_prerequisites() {
  echo "==> Step 1: Ubuntu integration packages"
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends \
    ca-certificates curl docker.io xz-utils zsh \
    fonts-noto-color-emoji xvfb \
    libasound2t64 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 \
    libcairo2 libcups2t64 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0t64 \
    libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 \
    libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2
}

install_arch_prerequisites() {
  echo "==> Step 1: Arch integration packages"
  # Arch keeps GUI runtime libraries unsplit, so one package per library
  # family covers the set Ubuntu spreads across lib*-t64 packages.
  # at-spi2-core provides libatk/libatspi/libatk-bridge; glib2 provides
  # libglib; mesa provides libgbm. ca-certificates, curl, and xz are in the
  # Arch base group but are listed for parity with Ubuntu.
  sudo pacman -Sy --needed --noconfirm \
    ca-certificates curl docker xz zsh \
    noto-fonts-emoji xorg-server-xvfb \
    alsa-lib at-spi2-core cairo cups dbus glib2 mesa \
    nspr nss pango libxcomposite libxdamage libxrandr
}

case "$DISTRO" in
  ubuntu) install_ubuntu_prerequisites ;;
  arch) install_arch_prerequisites ;;
  *) echo "Error: unsupported distribution $DISTRO." >&2 && exit 1 ;;
esac

if [[ "$DISTRO" == "ubuntu" ]]; then
  echo "==> Step 2: allow unprivileged user namespaces (Codex sandbox)"
  # Supported Ubuntu releases restrict unprivileged user namespaces via
  # AppArmor by default.
  # Codex's Linux sandbox runs bubblewrap from the Nix store, which has no
  # AppArmor profile, so the kernel blocks `bwrap --unshare-user` and sandboxed
  # commands break. Relax the restriction system-wide via a persistent sysctl.
  # Arch does not restrict unprivileged user namespaces, so this step is
  # Ubuntu-only.
  userns_node="/proc/sys/kernel/apparmor_restrict_unprivileged_userns"
  if [[ ! -e "$userns_node" || "$(<"$userns_node")" == "0" ]]; then
    echo "    unprivileged user namespaces already allowed, skipping"
  else
    echo "kernel.apparmor_restrict_unprivileged_userns=0" |
      sudo tee /etc/sysctl.d/60-userns.conf >/dev/null
    sudo sysctl --system
  fi
else
  echo "==> Step 2: allow unprivileged user namespaces (Codex sandbox)"
  echo "    not restricted on this distribution, skipping"
fi

echo "==> Step 3: Determinate Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix |
    sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> Step 4: symlink this repo to ~/.dotfiles"
ln -sfn "$DIR" "$HOME/.dotfiles"

echo "==> Step 5: first Home Manager switch"
export DOTFILES_USERNAME="${USER:-$(id -un)}"
export DOTFILES_HOME="$HOME"
nix run github:nix-community/home-manager/release-26.05 -- \
  switch --impure --flake "$HOME/.dotfiles#$HOME_TARGET"

echo "==> Step 6: set Zsh as the login shell"
CURRENT_LOGIN_SHELL="$(getent passwd "$DOTFILES_USERNAME" | cut -d: -f7)"
if [[ "$CURRENT_LOGIN_SHELL" != "/usr/bin/zsh" ]]; then
  sudo chsh -s /usr/bin/zsh "$DOTFILES_USERNAME"
else
  echo "    Zsh is already the login shell, skipping"
fi

echo "==> Step 7: enable Docker"
sudo systemctl enable --now docker.service
if id -nG "$DOTFILES_USERNAME" | tr ' ' '\n' | grep -qx docker; then
  echo "    $DOTFILES_USERNAME is already in the docker group, skipping"
else
  sudo usermod -aG docker "$DOTFILES_USERNAME"
fi

echo "==> Done. Start a new login session, run 'codex login', and use ./rebuild.sh for future changes."
