#!/usr/bin/env bash
# Upgrade the Determinate Nix daemon, then prove it still works.
#
# The daemon belongs to the Determinate installer, not to this flake
# (configuration.nix sets nix.enable = false), so ./rebuild.sh never changes
# it. Upgrades happen here instead: upgrade, restart if needed, smoke test, and
# only then point at ./rebuild.sh.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=scripts/lib-nix.sh
. "$DIR/scripts/lib-nix.sh"

usage() {
  cat <<'EOF'
Usage: nix-upgrade.sh [<version> | --latest | --check] [--force]

Upgrade the Determinate Nix daemon, verify it, and report the result.

  (no arguments)  upgrade to the latest stable release, same as --latest
  <version>       upgrade to an exact version
  --latest        upgrade to the latest stable release
  --check         print running and latest versions; change nothing
  --force         proceed even if a rebuild appears to be running
  -h, --help      show this help

Environment:
  DOTFILES_NIX_SMOKE_TIMEOUT  seconds allowed for the config dry-run (300)
EOF
}

main() {
  local mode="latest" requested="" force=0

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        usage
        return 0
        ;;
      --check) mode="check" ;;
      --latest) mode="latest" ;;
      --force) force=1 ;;
      -*)
        echo "error: unknown option: $1" >&2
        usage >&2
        return 2
        ;;
      *)
        if [[ -n "$requested" ]]; then
          echo "error: expected one version, got '$requested' and '$1'." >&2
          return 2
        fi
        requested="$1"
        ;;
    esac
    shift
  done

  if ! command -v nix >/dev/null 2>&1; then
    echo "error: nix is not on PATH." >&2
    return 1
  fi
  local nixd=""
  if ! nixd="$(command -v determinate-nixd)"; then
    echo "error: determinate-nixd not found." >&2
    echo "This repo expects Determinate Nix, which bootstrap.sh step 1 installs." >&2
    return 1
  fi

  local current="" latest="" target=""
  read -r current latest <<<"$(nix_read_versions)"

  if [[ "$mode" == "check" ]]; then
    nix_report_versions "$current" "$latest"
    return 0
  fi

  if [[ -n "$requested" ]]; then
    target="${requested#v}"
  else
    target="$latest"
    if [[ -z "$target" ]]; then
      echo "error: could not determine the latest release; pass a version instead." >&2
      return 1
    fi
  fi

  if ((force == 0)) && nix_builds_running; then
    echo "error: a Nix build is running, and upgrading now would interrupt it." >&2
    echo "Re-run with --force to upgrade anyway." >&2
    return 1
  fi

  if [[ -z "$current" ]]; then
    echo "warning: could not read the running daemon version; it may be unhealthy." >&2
  elif [[ "$current" == "$target" ]]; then
    echo "==> Determinate Nix is already on $target; verifying only"
  fi

  if [[ "$current" != "$target" ]]; then
    echo "==> Upgrading Determinate Nix ${current:-unknown} -> $target"
    # sudo resets PATH on macOS, so hand it the resolved path, as bootstrap.sh does.
    sudo "$nixd" upgrade --version "$target"
  fi

  if ! nix_wait_for_daemon 45; then
    nix_restart_daemon
    if ! nix_wait_for_daemon 60; then
      echo "error: the Nix daemon did not come back after a restart." >&2
      return 1
    fi
  fi

  read -r current _ <<<"$(nix_read_versions)"
  if [[ -n "$current" && "$current" != "$target" ]]; then
    echo "error: expected $target after upgrading but the daemon reports $current." >&2
    return 1
  fi

  nix_run_smoke_test "$NIX_SMOKE_TIMEOUT"

  echo
  echo "==> Determinate Nix $target is installed and verified"
  echo "    Next: ./rebuild.sh"
}

main "$@"
