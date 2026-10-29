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
OPTIMISE=0
MAX_FREE=""

usage() {
  cat <<'EOF'
Usage: disk-clean.sh [--dry-run] [--max SIZE] [--optimise]

Reclaim disk space from the Nix store: old generations of your profiles and of
root's profile, dead store paths, the systemd journal above a size cap, and
optionally duplicate files kept as separate copies.

  -n, --dry-run   show what would be removed, change nothing
  --max SIZE      stop collecting once SIZE is free, for example --max 5G
                  (prunes generations explicitly, then caps the collection)
  --optimise      also hard-link duplicate files; walks every file in the store,
                  so it is the slowest step and usually the smallest win
  -h, --help      show this help

The active generation is never deleted. It stops being current only when a
later switch replaces it, and a run after that switch collects it.

Order matters: root's generations go first, then everything else is pruned, and
a single collection covers both. Collecting twice is what made this slow.
EOF
}

free_space() {
  df -h /nix | awk 'NR == 2 { printf "%s used, %s available", $3, $4 }'
}

# Run one step, report how long it took, and skip the work under --dry-run.
timed() {
  local label="$1"
  shift
  printf '==> %s\n' "$label"
  local started=$SECONDS
  "$@"
  printf '    finished in %ss\n' "$((SECONDS - started))"
}

# For the steps whose tools have no dry run of their own: say what would run.
planned() {
  printf '    %s\n' "$*"
  if ((DRY_RUN == 0)); then
    "$@"
  fi
}

# Profiles the current user can prune without sudo. Home Manager and nix profile
# store theirs under the XDG state directory; the legacy location still exists
# on older machines.
profiles_to_prune() {
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles"
  local candidate=""
  for candidate in "$HOME/.nix-profile" "$state_dir/profile" "$state_dir/home-manager"; do
    if [[ -e "$candidate" ]]; then
      printf '%s\n' "$candidate"
    fi
  done
}

step_collect() {
  # Root's profile is a GC root that an unprivileged run cannot prune, so it has
  # to go before the collection, otherwise its closures survive and need a
  # second full pass.
  if [[ -e "$ROOT_PROFILE" ]]; then
    planned sudo "$NIX_BIN/nix-env" -p "$ROOT_PROFILE" --delete-generations old
  fi

  if [[ -n "$MAX_FREE" ]]; then
    local profile=""
    while read -r profile; do
      [[ -n "$profile" ]] || continue
      planned "$NIX_BIN/nix-env" -p "$profile" --delete-generations old
    done < <(profiles_to_prune)
    planned "$NIX_BIN/nix" store gc --max "$MAX_FREE"
  elif ((DRY_RUN)); then
    "$NIX_BIN/nix-collect-garbage" -d --dry-run
  else
    "$NIX_BIN/nix-collect-garbage" -d
  fi
}

step_journal() {
  if command -v journalctl >/dev/null 2>&1; then
    planned sudo journalctl --vacuum-size="$JOURNAL_CAP"
  else
    echo "    skipped: journalctl not available"
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
      --optimise) OPTIMISE=1 ;;
      --max)
        if (($# < 2)); then
          echo "error: --max needs a size, for example --max 5G." >&2
          return 2
        fi
        MAX_FREE="$2"
        shift
        ;;
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

  timed "Old generations and dead store paths" step_collect

  if ((OPTIMISE)); then
    # auto-optimise-store only hard-links paths as they are added, never
    # retroactively, so this can still reclaim gigabytes after a few rebuilds.
    timed "Duplicate files in the store" planned "$NIX_BIN/nix" store optimise
  fi

  timed "systemd journal above $JOURNAL_CAP" step_journal

  echo "==> After: $(free_space)"
}

main "$@"
