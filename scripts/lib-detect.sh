# shellcheck shell=bash
# Shared platform detection for the root dispatchers and platform scripts.
# This file is meant to be sourced, not executed.

# Absolute path of the repository checkout this lib belongs to.
dotfiles_repo_root() {
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  (cd "$lib_dir/.." && pwd -P)
}

# Linux distributions whose shared scripts/linux flow this repo supports.
# Values must match the os-release ID field.
supported_linux_distros="ubuntu arch archarm"

require_supported_linux_distro() {
  local os_release="${1:-/etc/os-release}"
  local ID=""
  local ID_LIKE=""
  local PRETTY_NAME=""
  local VERSION_ID=""

  if [[ ! -r "$os_release" ]]; then
    echo "Error: $os_release is missing; supported Linux distros: ${supported_linux_distros// /, }." >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  . "$os_release"
  case "$ID" in
    ubuntu)
      # Ubuntu gates on specific LTS releases; Arch is rolling and needs no version gate.
      if [[ "$VERSION_ID" != "24.04" && "$VERSION_ID" != "26.04" ]]; then
        echo "Error: Ubuntu 24.04 or 26.04 is required; found ${PRETTY_NAME:-unknown OS}." >&2
        exit 1
      fi
      ;;
    arch | archarm) ;;
    *)
      echo "Error: unsupported Linux distribution ${PRETTY_NAME:-unknown} (ID=${ID:-unknown}); supported: ${supported_linux_distros// /, }." >&2
      exit 1
      ;;
  esac
}

# Echo the flake home-configuration target for the current machine
# architecture. Target names are distro-neutral: one Home Manager
# configuration per Linux architecture, shared by every supported distro.
home_target_for_linux_arch() {
  case "$(uname -m)" in
    x86_64) echo "linux-x86_64" ;;
    aarch64 | arm64) echo "linux-aarch64" ;;
    *)
      echo "Error: unsupported architecture $(uname -m); expected x86_64 or aarch64." >&2
      return 1
      ;;
  esac
}

# Detect the current Linux distribution from /etc/os-release. Echoes a
# normalized family ID used by the shared Linux scripts: "ubuntu" or "arch".
# Arch derivatives such as Arch Linux ARM (ID=archarm, ID_LIKE=arch) map to
# "arch"; unknown IDs fall back to their ID_LIKE family when it is supported.
linux_distro_id() {
  local os_release="${1:-/etc/os-release}"
  local ID=""
  local ID_LIKE=""

  if [[ ! -r "$os_release" ]]; then
    echo "Error: $os_release is missing; cannot detect the Linux distribution." >&2
    return 1
  fi

  # shellcheck disable=SC1090
  . "$os_release"
  case "$ID" in
    ubuntu | arch) echo "$ID" ;;
    archarm) echo "arch" ;;
    *)
      if [[ "$ID_LIKE" == *"arch"* ]]; then
        echo "arch"
      else
        echo "Error: unsupported Linux distribution (ID=${ID:-unknown}, ID_LIKE=${ID_LIKE:-unknown})." >&2
        return 1
      fi
      ;;
  esac
}

# Root dispatcher: run scripts/<platform>/<command_name> for the current OS.
dotfiles_dispatch() {
  local command_name="$1"
  local root
  root="$(dotfiles_repo_root)"
  shift

  case "$(uname -s)" in
    Darwin)
      exec "$root/scripts/macos/$command_name" "$@"
      ;;
    Linux)
      require_supported_linux_distro
      exec "$root/scripts/linux/$command_name" "$@"
      ;;
    *)
      echo "Error: unsupported operating system $(uname -s)." >&2
      exit 1
      ;;
  esac
}
