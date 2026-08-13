#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/lib-detect.sh
. "$ROOT/scripts/lib-detect.sh"

dotfiles_dispatch "bootstrap.sh" "$@"
