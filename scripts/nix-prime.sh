#!/usr/bin/env bash
# Materialise this flake's inputs and outputs in the Nix store as the invoking
# user.
#
# The Nix daemon belongs to the Determinate installer, and root keeps its own
# eval and fetcher caches. A sudo-only build therefore imports whole source
# trees itself, inside the privileged step, where a stale lock is invisible and
# an interrupted import can stall every later build. Priming does that work
# unprivileged instead: progress is visible, a lock deadlock is detected and
# cleared automatically, and the following sudo build finds everything present.
#
# ./rebuild.sh does this automatically before switching. Run it directly after
# `nix flake update`, or when a rebuild looks like it is doing cold work.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=scripts/lib-nix.sh
. "$DIR/scripts/lib-nix.sh"

usage() {
  cat <<'EOF'
Usage: nix-prime.sh [flake]

Fetch every flake input source tree and build every output in the store as the
invoking user, so a later `sudo` build has nothing cold to do.

  flake       path to the flake to prime (default: this repository)
  -h, --help  show this help

Environment:
  NIX_LOCK_GRACE_SECONDS  quiet lock wait before treating it as a deadlock (120)
  NIX_LOCK_WATCH_SECONDS  give up watching for a deadlock after this (1800)
EOF
}

main() {
  local flake="$DIR"

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        usage
        return 0
        ;;
      -*)
        echo "error: unknown option: $1" >&2
        usage >&2
        return 2
        ;;
      *)
        if [[ "$flake" != "$DIR" ]]; then
          echo "error: expected one flake path, got '$flake' and '$1'." >&2
          return 2
        fi
        flake="$1"
        ;;
    esac
    shift
  done

  if ! command -v nix >/dev/null 2>&1; then
    echo "error: nix is not on PATH." >&2
    return 1
  fi

  nix_prime_store "$flake"
}

main "$@"
