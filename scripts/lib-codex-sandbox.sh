# shellcheck shell=bash
# Configure the system bubblewrap path that Ubuntu's AppArmor profile covers.
# This file is meant to be sourced, not executed.

codex_bwrap_has_user_namespace_access() {
  local bwrap_path=$1

  [[ -x "$bwrap_path" ]] &&
    "$bwrap_path" \
      --unshare-user \
      --unshare-net \
      --ro-bind / / \
      /bin/true \
      >/dev/null 2>&1
}

configure_codex_sandbox() {
  if (($# < 4)); then
    echo "Error: configure_codex_sandbox requires bwrap, source profile, target profile, and a privilege command." >&2
    return 64
  fi

  local bwrap_path=$1
  local profile_source=$2
  local profile_target=$3
  shift 3
  local -a privileged_command=("$@")

  if codex_bwrap_has_user_namespace_access "$bwrap_path"; then
    return 0
  fi
  if [[ ! -x "$bwrap_path" || ! -r "$profile_source" ]]; then
    echo "Error: bubblewrap and its AppArmor profile must be installed before configuring the Codex sandbox." >&2
    return 69
  fi

  echo "==> Configuring the Codex bubblewrap sandbox"
  "${privileged_command[@]}" install -m 0644 -- "$profile_source" "$profile_target"
  "${privileged_command[@]}" apparmor_parser -r "$profile_target"

  if ! codex_bwrap_has_user_namespace_access "$bwrap_path"; then
    echo "Error: /usr/bin/bwrap still cannot create the namespaces required by Codex." >&2
    return 77
  fi
}

ensure_codex_sandbox() {
  if (($# < 4)); then
    echo "Error: ensure_codex_sandbox requires bwrap, source profile, target profile, and a privilege command." >&2
    return 64
  fi

  local bwrap_path=$1
  local profile_source=$2
  local profile_target=$3
  shift 3
  local -a privileged_command=("$@")

  if codex_bwrap_has_user_namespace_access "$bwrap_path"; then
    return 0
  fi
  if [[ ! -x "$bwrap_path" || ! -r "$profile_source" ]]; then
    "${privileged_command[@]}" apt-get update
    "${privileged_command[@]}" apt-get install -y --no-install-recommends \
      apparmor-profiles apparmor-utils bubblewrap
  fi

  configure_codex_sandbox \
    "$bwrap_path" \
    "$profile_source" \
    "$profile_target" \
    "${privileged_command[@]}"
}
