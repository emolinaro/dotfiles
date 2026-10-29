#!/usr/bin/env bash
# Report on the parts of this setup that Nix cannot manage for you: the
# Determinate Nix daemon, substituter reachability, store space, and whether
# the daemon can still do real work. Changes no configuration, though the
# smoke test does download one small file to prove store writes work.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=scripts/lib-nix.sh
. "$DIR/scripts/lib-nix.sh"

usage() {
  cat <<'EOF'
Usage: doctor.sh [--quick]

Report on the Nix daemon, substituters, store space, and in-flight builds,
then run a bounded smoke test that proves the daemon can evaluate the config
and schedule substitutes.

  --quick     skip the smoke test (fast status only)
  -h, --help  show this help
EOF
}

report_auth() {
  local out=""
  local auth="unknown"
  if out="$(nix_run_with_timeout 25 determinate-nixd status 2>/dev/null)"; then
    auth="$(printf '%s\n' "$out" | sed -n 's/^Authentication: //p' | head -1)"
    auth="${auth:-unknown}"
  fi
  printf '  FlakeHub auth:  %s\n' "$auth"
  if [[ "$auth" == "logged-out" ]]; then
    echo "                  (expected for this repo; only private flakes need it)"
  fi
}

main() {
  local quick=0 problems=0

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        usage
        return 0
        ;;
      --quick) quick=1 ;;
      -*)
        echo "error: unknown option: $1" >&2
        usage >&2
        return 2
        ;;
      *)
        echo "error: unexpected argument: $1" >&2
        return 2
        ;;
    esac
    shift
  done

  echo "== Nix daemon"
  if command -v determinate-nixd >/dev/null 2>&1; then
    local current="" latest=""
    read -r current latest <<<"$(nix_read_versions)"
    nix_report_versions "$current" "$latest"
    report_auth
    if [[ -z "$current" ]]; then
      echo "  error: the daemon did not answer 'determinate-nixd version'" >&2
      problems=$((problems + 1))
    fi
  else
    echo "  determinate-nixd: not found (bootstrap.sh step 1 installs it)" >&2
    problems=$((problems + 1))
  fi

  echo
  echo "== Substituters"
  if ! nix_report_substituters; then
    problems=$((problems + 1))
  fi

  echo
  echo "== Store"
  nix_report_disk || problems=$((problems + 1))

  echo
  echo "== Builds"
  if nix_builds_running; then
    echo "  in-flight: yes (an upgrade would interrupt it)"
  else
    echo "  in-flight: none"
  fi

  if ((quick == 0)); then
    echo
    if ! nix_run_smoke_test "$NIX_SMOKE_TIMEOUT"; then
      problems=$((problems + 1))
    fi
  fi

  echo
  if ((problems > 0)); then
    echo "doctor: $problems problem(s) found"
    return 1
  fi
  echo "doctor: no problems found"
}

main "$@"
