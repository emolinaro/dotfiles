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

  if output="$(require_supported_linux_distro "$os_release" 2>&1)"; then
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

  if output="$(require_supported_linux_distro "$os_release" 2>&1)"; then
    fail "$name: unexpectedly accepted"
  elif [[ "$output" == *"$expected"* ]]; then
    pass "$name"
  else
    fail "$name: expected '$expected', got '$output'"
  fi
}

assert_distro_id() {
  local name="$1"
  local os_release="$2"
  local expected="$3"
  local output

  if output="$(linux_distro_id "$os_release")"; then
    if [[ "$output" == "$expected" ]]; then
      pass "$name"
    else
      fail "$name: expected '$expected', got '$output'"
    fi
  else
    fail "$name: $output"
  fi
}

assert_distro_id_rejects() {
  local name="$1"
  local os_release="$2"

  if linux_distro_id "$os_release" >/dev/null 2>&1; then
    fail "$name: unexpectedly accepted"
  else
    pass "$name"
  fi
}

assert_home_target() {
  local name="$1"
  local arch="$2"
  local expected="$3"
  local output

  local shim_dir
  shim_dir="$(mktemp -d)"
  printf '#!/usr/bin/env bash\necho "%s"\n' "$arch" >"$shim_dir/uname"
  chmod +x "$shim_dir/uname"
  if output="$(PATH="$shim_dir:$PATH" home_target_for_linux_arch)"; then
    if [[ "$output" == "$expected" ]]; then
      pass "$name"
    else
      fail "$name: expected '$expected', got '$output'"
    fi
  else
    fail "$name: $output"
  fi
  rm -rf "$shim_dir"
}

fixtures="$ROOT/tests/fixtures/os-release"

assert_accepts "accepts Ubuntu 24.04" "$fixtures/ubuntu-24.04"
assert_accepts "accepts Ubuntu 26.04" "$fixtures/ubuntu-26.04"
assert_accepts "accepts Arch Linux" "$fixtures/arch"
assert_accepts "accepts Arch Linux ARM" "$fixtures/archarm"
assert_rejects \
  "rejects unsupported Ubuntu releases" \
  "$fixtures/ubuntu-25.10" \
  "Ubuntu 24.04 or 26.04 is required; found Ubuntu 25.10."
assert_rejects \
  "rejects non-supported distributions" \
  "$fixtures/debian-13" \
  "unsupported Linux distribution Debian GNU/Linux 13 (trixie) (ID=debian)"
assert_rejects \
  "rejects a missing os-release file" \
  "$fixtures/missing" \
  "is missing; supported Linux distros: ubuntu, arch, archarm."

assert_distro_id "detects Ubuntu" "$fixtures/ubuntu-24.04" "ubuntu"
assert_distro_id "detects Arch" "$fixtures/arch" "arch"
assert_distro_id "detects Arch Linux ARM via ID" "$fixtures/archarm" "arch"
assert_distro_id_rejects "rejects a missing os-release file" "$fixtures/missing"
assert_distro_id_rejects "rejects an unsupported distro" "$fixtures/debian-13"

assert_home_target "maps x86_64 to linux-x86_64" "x86_64" "linux-x86_64"
assert_home_target "maps aarch64 to linux-aarch64" "aarch64" "linux-aarch64"
assert_home_target "maps arm64 to linux-aarch64" "arm64" "linux-aarch64"

assert_home_target_rejects() {
  local name="$1"
  local arch="$2"
  local shim_dir

  shim_dir="$(mktemp -d)"
  printf '#!/usr/bin/env bash\necho "%s"\n' "$arch" >"$shim_dir/uname"
  chmod +x "$shim_dir/uname"
  if PATH="$shim_dir:$PATH" home_target_for_linux_arch >/dev/null 2>&1; then
    fail "$name: unexpectedly accepted"
  else
    pass "$name"
  fi
  rm -rf "$shim_dir"
}

assert_home_target_rejects "rejects unsupported architectures" "riscv64"

if ((failures > 0)); then
  exit 1
fi
