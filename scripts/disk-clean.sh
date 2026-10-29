#!/usr/bin/env bash
# Reclaim the disk space that Nix rebuilds leave behind.
#
# Nix only collects what it is told to collect: dead paths from aborted builds
# and from superseded closures stay in the store indefinitely, and every switch
# adds a generation that keeps its whole closure alive as a rollback root. On a
# small disk two generations plus the next update do not fit, and running out of
# space mid-build is reported as a cascade of "Cannot build ... 1 dependency
# failed" lines for every parent derivation instead of naming the real cause.
#
# Generations are deleted here, so there is no rollback afterwards.
set -euo pipefail

# The daemon profile owns the clients, and sudo does not carry your PATH.
NIX_BIN="/nix/var/nix/profiles/default/bin"
ROOT_PROFILE="/nix/var/nix/profiles/per-user/root/profile"
JOURNAL_CAP="300M"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: disk-clean.sh [--dry-run]

Reclaim disk space from the Nix store: old generations of your profiles and of
root's profile, dead store paths, duplicate files kept as separate copies, and
the systemd journal above a size cap.

  -n, --dry-run  show what would be removed, change nothing
  -h, --help     show this help

The active generation is never deleted. It stops being current only when a
later switch replaces it, and a run after that switch collects it.

Order matters: generations go first so their closures become unreachable, then
the store is collected, then the surviving files are hard-linked together.
EOF
}

free_space() {
  df -h /nix | awk 'NR == 2 { printf "%s used, %s available", $3, $4 }'
}

# For the steps whose tools have no dry run of their own: say what would run.
planned() {
  printf '    %s\n' "$*"
  if ((DRY_RUN == 0)); then
    "$@"
  fi
}

main() {
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        usage
        return 0
        ;;
      -n | --dry-run) DRY_RUN=1 ;;
      -*)
        echo "error: unknown option: $1" >&2
        usage >&2
        return 2
        ;;
      *)
        echo "error: unexpected argument: $1" >&2
        usage >&2
        return 2
        ;;
    esac
    shift
  done

  if [[ ! -x "$NIX_BIN/nix-collect-garbage" ]]; then
    echo "error: $NIX_BIN/nix-collect-garbage is missing; is Nix installed?" >&2
    return 1
  fi

  echo "==> Before: $(free_space)"

  echo "==> Old generations of your profiles"
  if ((DRY_RUN)); then
    "$NIX_BIN/nix-collect-garbage" -d --dry-run
  else
    "$NIX_BIN/nix-collect-garbage" -d
  fi

  echo "==> Old generations of root's profile"
  if [[ -e "$ROOT_PROFILE" ]]; then
    if ((DRY_RUN)); then
      sudo "$NIX_BIN/nix-env" -p "$ROOT_PROFILE" --list-generations
    else
      # The collection above only reaches profiles you own.
      sudo "$NIX_BIN/nix-env" -p "$ROOT_PROFILE" --delete-generations old
    fi
  fi

  echo "==> Dead store paths"
  if ((DRY_RUN)); then
    "$NIX_BIN/nix" store gc --dry-run
  else
    "$NIX_BIN/nix" store gc
  fi

  echo "==> Duplicate files in the store"
  # auto-optimise-store only hard-links paths as they are added, never
  # retroactively, so this still reclaims gigabytes after a few rebuilds.
  planned "$NIX_BIN/nix" store optimise

  if command -v journalctl >/dev/null 2>&1; then
    echo "==> systemd journal above $JOURNAL_CAP"
    planned sudo journalctl --vacuum-size="$JOURNAL_CAP"
  fi

  echo "==> After: $(free_space)"
}

main "$@"
