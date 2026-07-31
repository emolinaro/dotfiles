#!/usr/bin/env bash
set -euo pipefail

repo_root="${REPO_UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
ubuntu_image="${UBUNTU_TEST_IMAGE:-ubuntu:24.04}"

docker run --rm --interactive --privileged \
  --mount "type=bind,source=$repo_root,target=/repo,readonly" \
  "$ubuntu_image" bash -se <<'CONTAINER'
set -euo pipefail

userns_node=/proc/sys/kernel/apparmor_restrict_unprivileged_userns
sysctl_file=/etc/sysctl.d/60-userns.conf
command_log=/tmp/bootstrap-command.log
shim_dir=/tmp/bootstrap-shims

mount -t tmpfs tmpfs /proc/sys/kernel
mkdir -p "$shim_dir"
groupadd docker
ln -s /bin/bash /usr/bin/zsh
useradd -m -d /home/tester -s /usr/bin/zsh -G docker tester
chmod 0777 /etc/sysctl.d

make_shim() {
  local name="$1"
  shift
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' "$@" >"$shim_dir/$name"
  chmod +x "$shim_dir/$name"
}

make_shim sudo \
  'printf "sudo" >>/tmp/bootstrap-command.log' \
  'printf " %q" "$@" >>/tmp/bootstrap-command.log' \
  'printf "\n" >>/tmp/bootstrap-command.log' \
  'exec "$@"'
make_shim apt-get 'exit 0'
make_shim nix 'exit 0'
make_shim systemctl 'exit 0'
make_shim sysctl \
  '[[ "${1:-}" == "--system" ]]' \
  'value="$(sed -n "s/^kernel\.apparmor_restrict_unprivileged_userns=//p" /etc/sysctl.d/60-userns.conf)"' \
  'printf "%s\n" "$value" >/proc/sys/kernel/apparmor_restrict_unprivileged_userns' \
  'printf "* Applied kernel.apparmor_restrict_unprivileged_userns=%s\n" "$value"'

run_bootstrap() {
  runuser -u tester -- env \
    HOME=/home/tester \
    USER=tester \
    PATH="$shim_dir:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    /repo/bootstrap.sh
}

assert_file_absent() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "FAIL: expected $path to be absent" >&2
    exit 1
  fi
}

assert_equal() {
  local expected="$1"
  local actual="$2"
  local description="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: expected $description to be '$expected', found '$actual'" >&2
    exit 1
  fi
}

assert_sysctl_calls() {
  local expected="$1"
  local actual
  actual="$(grep -c '^sudo sysctl --system$' "$command_log" || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: expected $expected sysctl --system call(s), found $actual" >&2
    exit 1
  fi
}

printf '1\n' >"$userns_node"
chmod 0666 "$userns_node"
: >"$command_log"
chmod 0666 "$command_log"

echo '=== Restricted kernel setting: bootstrap applies persistent fix ==='
run_bootstrap
assert_equal 0 "$(<"$userns_node")" 'kernel setting after bootstrap'
assert_equal \
  'kernel.apparmor_restrict_unprivileged_userns=0' \
  "$(<"$sysctl_file")" \
  'persistent sysctl config'
assert_sysctl_calls 1
echo "VERIFY kernel value after bootstrap: $(<"$userns_node")"
echo "VERIFY persistent config: $(<"$sysctl_file")"

echo '=== Second run: configured state is idempotent ==='
run_bootstrap
assert_equal 0 "$(<"$userns_node")" 'kernel setting after second bootstrap'
assert_equal \
  'kernel.apparmor_restrict_unprivileged_userns=0' \
  "$(<"$sysctl_file")" \
  'persistent sysctl config after second bootstrap'
assert_sysctl_calls 1
echo 'VERIFY sysctl --system was not called again'

echo '=== Already disabled without config: bootstrap does nothing ==='
rm "$sysctl_file"
: >"$command_log"
run_bootstrap
assert_equal 0 "$(<"$userns_node")" 'pre-disabled kernel setting'
assert_file_absent "$sysctl_file"
assert_sysctl_calls 0
echo 'VERIFY no persistent config was written and sysctl --system was not called'

echo '=== Kernel setting unavailable: bootstrap does nothing ==='
rm "$userns_node"
: >"$command_log"
run_bootstrap
assert_file_absent "$sysctl_file"
assert_sysctl_calls 0
echo 'VERIFY no persistent config was written and sysctl --system was not called'

grep -Fq "AppArmor restriction" /repo/README.md
grep -Fq "namespaces (required by Codex's bubblewrap sandbox)" /repo/README.md
echo 'VERIFY README documents the provisioned Codex sandbox requirement'
echo 'PASS: Ubuntu bootstrap user-namespace behavior matches the documented setup'
CONTAINER
