# shellcheck shell=bash
# Shared platform detection for the root dispatchers and platform scripts.
# This file is meant to be sourced, not executed.

# Absolute path of the repository checkout this lib belongs to.
dotfiles_repo_root() {
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  (cd "$lib_dir/.." && pwd -P)
}

require_ubuntu_2404() {
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
}

# Echo the flake home-configuration target for the current machine architecture.
home_target_for_arch() {
  case "$(uname -m)" in
    x86_64) echo "ubuntu-x86_64" ;;
    aarch64 | arm64) echo "ubuntu-aarch64" ;;
    *)
      echo "Error: unsupported architecture $(uname -m); expected x86_64 or aarch64." >&2
      return 1
      ;;
  esac
}

# Root dispatcher: run scripts/<os>/<command_name> for the current OS.
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
      require_ubuntu_2404
      exec "$root/scripts/ubuntu/$command_name" "$@"
      ;;
    *)
      echo "Error: unsupported operating system $(uname -s)." >&2
      exit 1
      ;;
  esac
}
