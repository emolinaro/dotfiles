#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

case "$(uname -s)" in
  Darwin)
    exec "$ROOT/scripts/macos/rebuild.sh" "$@"
    ;;
  Linux)
    if [[ -r /etc/os-release ]]; then
      # shellcheck disable=SC1091
      . /etc/os-release
    fi
    if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]]; then
      exec "$ROOT/scripts/ubuntu/rebuild.sh" "$@"
    fi
    echo "Error: Linux support requires Ubuntu 24.04; found ${PRETTY_NAME:-unknown Linux}." >&2
    exit 1
    ;;
  *)
    echo "Error: unsupported operating system $(uname -s)." >&2
    exit 1
    ;;
esac
