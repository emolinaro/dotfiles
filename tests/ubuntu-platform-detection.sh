#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=scripts/lib-detect.sh
. "$ROOT/scripts/lib-detect.sh"

failures=0

pass() {
  echo "ok - $1"
}

fail() {
  echo "not ok - $1" >&2
  failures=$((failures + 1))
}

assert_accepts() {
  local name="$1"
  local os_release="$2"
  local output

  if output="$(require_supported_ubuntu "$os_release" 2>&1)"; then
    pass "$name"
  else
    fail "$name: $output"
  fi
}

assert_rejects() {
  local name="$1"
  local os_release="$2"
  local expected="$3"
  local output

  if output="$(require_supported_ubuntu "$os_release" 2>&1)"; then
    fail "$name: unexpectedly accepted"
  elif [[ "$output" == *"$expected"* ]]; then
    pass "$name"
  else
    fail "$name: expected '$expected', got '$output'"
  fi
}

fixtures="$ROOT/tests/fixtures/os-release"

assert_accepts "accepts Ubuntu 24.04" "$fixtures/ubuntu-24.04"
assert_accepts "accepts Ubuntu 26.04" "$fixtures/ubuntu-26.04"
assert_rejects \
  "rejects unsupported Ubuntu releases" \
  "$fixtures/ubuntu-25.10" \
  "Ubuntu 24.04 or 26.04 is required; found Ubuntu 25.10."
assert_rejects \
  "rejects non-Ubuntu distributions" \
  "$fixtures/debian-13" \
  "Ubuntu 24.04 or 26.04 is required; found Debian GNU/Linux 13 (trixie)."
assert_rejects \
  "rejects a missing os-release file" \
  "$fixtures/missing" \
  "is missing; Ubuntu 24.04 or 26.04 is required."

if ((failures > 0)); then
  exit 1
fi
