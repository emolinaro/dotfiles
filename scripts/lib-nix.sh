# shellcheck shell=bash
# Shared helpers for the Nix daemon commands (nix-upgrade.sh, doctor.sh).
#
# The daemon is installed and upgraded by the Determinate installer, not by
# this flake: configuration.nix sets nix.enable = false so nix-darwin leaves
# /etc/nix/nix.conf and the daemon alone. Anything that touches the daemon
# therefore lives here, behind an explicit command, with hard timeouts so a
# wedged daemon fails fast instead of hanging a rebuild for an hour.
#
# This file is meant to be sourced, not executed.

NIX_SMOKE_TIMEOUT="${DOTFILES_NIX_SMOKE_TIMEOUT:-300}"
NIX_DAEMON_SERVICE_DARWIN="system/systems.determinate.nix-daemon"
NIX_DAEMON_SERVICE_LINUX="nix-daemon.service"

NIX_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=scripts/lib-detect.sh
. "$NIX_REPO_ROOT/scripts/lib-detect.sh"

# macOS ships no timeout(1), so use perl, which is in the base system on both
# macOS and Linux. A command killed by the deadline exits 142 (128 + SIGALRM).
nix_run_with_timeout() {
  local secs="$1"
  shift
  perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
}

# Echo "<running> <latest>", either of which can be empty (no daemon, or
# offline for the latest lookup). One call, because `determinate-nixd version`
# also does the network lookup for the latest release.
nix_read_versions() {
  local out=""
  local current=""
  local latest=""
  if out="$(nix_run_with_timeout 25 determinate-nixd version 2>/dev/null)"; then
    current="$(printf '%s\n' "$out" | sed -n 's/^Determinate Nixd daemon version: //p' | head -1)"
    latest="$(printf '%s\n' "$out" | sed -n 's/^Latest version: //p' | head -1)"
    # When nothing is newer, nixd reports prose instead of a version line.
    if [[ -z "$latest" ]] && printf '%s\n' "$out" | grep -q "running the latest version"; then
      latest="$current"
    fi
  fi
  printf '%s %s\n' "$current" "$latest"
}

# Human-readable version report shared by the upgrade command and the doctor.
nix_report_versions() {
  local current="$1" latest="$2"
  printf '  running daemon: %s\n' "${current:-unknown (not responding)}"
  printf '  latest stable:  %s\n' "${latest:-unknown}"
  if [[ -n "$current" && -n "$latest" && "$current" != "$latest" ]]; then
    echo "  note: $latest is available; run ./nix-upgrade.sh"
  fi
}

nix_daemon_ping() {
  local secs="${1:-20}"
  nix_run_with_timeout "$secs" nix store ping >/dev/null 2>&1
}

nix_wait_for_daemon() {
  local secs="${1:-45}" waited=0
  while ((waited < secs)); do
    if nix_daemon_ping 10; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  return 1
}

nix_restart_hint() {
  case "$(uname -s)" in
    Darwin) echo "sudo launchctl kickstart -k $NIX_DAEMON_SERVICE_DARWIN" ;;
    Linux) echo "sudo systemctl restart $NIX_DAEMON_SERVICE_LINUX" ;;
    *) echo "" ;;
  esac
}

nix_restart_daemon() {
  echo "==> Restarting the Nix daemon"
  case "$(uname -s)" in
    Darwin) sudo launchctl kickstart -k "$NIX_DAEMON_SERVICE_DARWIN" ;;
    Linux)
      if sudo systemctl restart "$NIX_DAEMON_SERVICE_LINUX" 2>/dev/null; then
        return 0
      fi
      echo "warning: $NIX_DAEMON_SERVICE_LINUX not found; trying determinate-nixd.service" >&2
      sudo systemctl restart determinate-nixd.service
      ;;
    *)
      echo "error: no known way to restart the daemon on $(uname -s)." >&2
      return 1
      ;;
  esac
}

nix_builds_running() {
  pgrep -f "darwin-rebuild|home-manager switch|nix build" >/dev/null 2>&1 && return 0
  pgrep -x nix >/dev/null 2>&1
}

# Flake attribute used to prove that evaluation and substitute scheduling still
# work. Keep the macOS host label in sync with scripts/macos/rebuild.sh, or
# override it with DOTFILES_HOST.
nix_flake_smoke_target() {
  local flake="${1:-$NIX_REPO_ROOT}"
  local target=""
  case "$(uname -s)" in
    Darwin)
      printf '%s#darwinConfigurations.%s.system' "$flake" "${DOTFILES_HOST:-mac}"
      ;;
    Linux)
      target="$(home_target_for_linux_arch 2>/dev/null || true)"
      if [[ -n "$target" ]]; then
        printf '%s#homeConfigurations.%s.activationPackage' "$flake" "$target"
      fi
      ;;
  esac
}

# True when any builder process is alive. Builds run as _nixbld* users, so this
# cheaply distinguishes a lock held by real work from a lock held by a leaked
# daemon worker, which is what makes nix wait forever.
nix_build_activity() {
  ps -axo user= 2>/dev/null | awk '$1 ~ /nixbld/ { found = 1 } END { exit !found }'
}

# Run a command in the background, watching its output for nix's lock-deadlock
# pattern: "waiting for lock on ..." with no further output, no builder alive,
# and no progress for NIX_LOCK_GRACE_SECONDS. Only that combination counts as a
# deadlock, because concurrent builds legitimately wait on each other.
# Returns 0 on success, the command's own status on failure, and 3 when a
# deadlock was detected and cleared by restarting the daemon.
nix_run_guarded() {
  local label="$1"
  shift
  local log=""
  local pid=0
  local rc=0
  local size=0
  local last=0
  local stuck=0
  local waited=0
  local warned=0
  local grace="${NIX_LOCK_GRACE_SECONDS:-120}"
  local watch="${NIX_LOCK_WATCH_SECONDS:-1800}"
  local started=0
  local slug="${label//[^A-Za-z0-9]/-}"

  # GNU mktemp requires the XXX template, BSD mktemp does not, so spell it out
  # and keep the label free of spaces to work on both.
  started="$SECONDS"
  log="$(mktemp "${TMPDIR:-/tmp}/nix-$slug.XXXXXX" 2>/dev/null)" || log=""
  if [[ -z "$log" || ! -w "$log" ]]; then
    echo "error: could not create a temporary log file for '$label'." >&2
    return 1
  fi
  "$@" >"$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && ((waited < watch)); do
    size="$(wc -c <"$log" 2>/dev/null || echo 0)"
    if ((size == last)) && grep -q "waiting for lock on" "$log" 2>/dev/null; then
      stuck=$((stuck + 1))
    else
      stuck=0
      warned=0
    fi
    last="$size"
    if ((stuck >= grace)); then
      if nix_build_activity; then
        if ((warned == 0)); then
          echo "    '$label' is waiting on a lock held by an active build; leaving the daemon alone" >&2
          warned=1
        fi
        stuck=0
      else
        echo "    deadlock: '$label' is waiting for a store lock nothing is building; restarting the daemon" >&2
        kill -TERM "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        nix_restart_daemon >&2 || true
        rm -f "$log"
        return 3
      fi
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid" || rc=$?
  if ((rc != 0)); then
    echo "    '$label' failed (exit $rc) after $((SECONDS - started))s; last output:" >&2
    tail -15 "$log" >&2
  else
    echo "    '$label' done in $((SECONDS - started))s"
  fi
  rm -f "$log"
  return "$rc"
}

# Run a nix command, retrying once after a detected lock deadlock has been
# cleared by restarting the daemon.
nix_run_with_deadlock_retry() {
  local label="$1"
  shift
  local attempt=1
  local rc=0
  while ((attempt <= 2)); do
    nix_run_guarded "$label" "$@" && return 0
    rc=$?
    if ((rc != 3)); then
      return "$rc"
    fi
    nix_wait_for_daemon 60 || {
      echo "error: the Nix daemon did not come back after a restart." >&2
      return 1
    }
    attempt=$((attempt + 1))
  done
  echo "error: '$label' is still deadlocked after a daemon restart." >&2
  return 1
}

# Materialise the flake's inputs and outputs in the store as the invoking user.
# Root keeps its own empty eval and fetcher caches, so without this a sudo
# build can pull whole source trees into the privileged step, where a lock
# deadlock is slow to notice and leaves the store half populated.
nix_prime_store() {
  local flake="${1:-$NIX_REPO_ROOT}"
  local target=""

  if ! nix_daemon_ping 15; then
    echo "==> Nix daemon is not answering; restarting it"
    nix_restart_daemon || return 1
    nix_wait_for_daemon 60 || {
      echo "error: the Nix daemon did not come back." >&2
      return 1
    }
  fi

  echo "==> Priming flake inputs"
  nix_run_with_deadlock_retry "flake inputs" nix flake archive --json "$flake"

  target="$(nix_flake_smoke_target "$flake")"
  if [[ -n "$target" ]]; then
    echo "==> Priming build outputs"
    nix_run_with_deadlock_retry "build outputs" nix build --impure --no-link "$target"
  fi
}

# Prove the daemon does real work: it answers, it can write to the store, and
# it can still evaluate the config and schedule substitutes. The last step is
# the one that catches the wedge class of failure, where a reload hangs while
# everything else looks healthy.
nix_run_smoke_test() {
  local timeout="${1:-$NIX_SMOKE_TIMEOUT}"
  local target="" out="" rc=0

  echo "==> Smoke test: daemon answers"
  if ! nix_daemon_ping 30; then
    echo "error: 'nix store ping' failed." >&2
    return 1
  fi

  echo "==> Smoke test: download and store registration"
  if nix_run_with_timeout 90 nix store prefetch-file --json \
    https://cache.nixos.org/nix-cache-info >/dev/null 2>&1; then
    echo "    ok"
  else
    echo "    warning: could not fetch a small file from cache.nixos.org (offline?)" >&2
  fi

  target="$(nix_flake_smoke_target)"
  if [[ -z "$target" ]]; then
    echo "==> Smoke test: skipped (no flake target for $(uname -s))"
    return 0
  fi

  echo "==> Smoke test: evaluate and schedule substitutes (limit ${timeout}s)"
  out="$(mktemp)"
  export DOTFILES_USERNAME="${DOTFILES_USERNAME:-$(id -un)}"
  export DOTFILES_HOME="${DOTFILES_HOME:-$HOME}"
  if nix_run_with_timeout "$timeout" nix build --impure --dry-run "$target" >"$out" 2>&1; then
    rm -f "$out"
    echo "    ok"
    return 0
  else
    rc=$?
  fi
  if [[ "$rc" -eq 142 ]]; then
    rm -f "$out"
    cat >&2 <<EOF
error: the daemon stopped responding within ${timeout}s.
       That is the wedge class of failure, not a configuration problem.
Next steps:
  sudo determinate-nixd upgrade --version <newer version>
  $(nix_restart_hint)
  ./nix-upgrade.sh
EOF
    return 1
  fi
  echo "    error: 'nix build --dry-run' exited $rc:" >&2
  sed -n '1,10p' "$out" >&2
  rm -f "$out"
  return 1
}

nix_report_substituters() {
  local out="" urls="" url="" result="" code="" secs=""
  if ! out="$(nix_run_with_timeout 25 nix config show substituters 2>/dev/null)"; then
    echo "  error: could not read 'nix config show substituters'" >&2
    return 1
  fi
  # `nix config show <key>` prints the bare value, but tolerate the
  # `key = value` form too in case that changes.
  urls="$(printf '%s\n' "$out" | sed -e 's/^substituters = //' -e '/^[[:space:]]*$/d' | head -1)"
  if [[ -z "$urls" ]]; then
    echo "  error: no substituters are configured" >&2
    return 1
  fi
  for url in $urls; do
    if result="$(nix_run_with_timeout 20 curl -sS -o /dev/null \
      -w '%{http_code} %{time_total}' --max-time 12 "${url%/}/nix-cache-info" 2>/dev/null)"; then
      code="${result%% *}"
      secs="${result##* }"
      if [[ "$code" == "200" ]]; then
        printf '  ok       %s (HTTP %s, %ss)\n' "$url" "$code" "$secs"
      else
        printf '  warning  %s (HTTP %s)\n' "$url" "$code"
      fi
    else
      printf '  warning  %s (unreachable)\n' "$url"
    fi
  done
}

nix_report_disk() {
  local line="" used="" avail=""
  line="$(df -h /nix 2>/dev/null | sed -n '2p')"
  if [[ -z "$line" ]]; then
    echo "  /nix: not mounted?" >&2
    return 1
  fi
  used="$(printf '%s\n' "$line" | awk '{print $3}')"
  avail="$(printf '%s\n' "$line" | awk '{print $4}')"
  printf '  /nix: %s used, %s available\n' "${used:-?}" "${avail:-?}"
}
