#!/usr/bin/env bash
# Report disk usage of the managed installation after bootstrap.
#
# /nix/store is measured via the Nix database (seconds) rather than a full
# filesystem walk. Other roots use dust when available, otherwise du.
# Nix closures are shown separately because they are subsets of the store.
set -euo pipefail

TOTAL_KB=0
MEASURE_TOOL="du"
STORE_METHOD="du"

human_kb() {
  local kb=$1
  awk -v kb="$kb" 'BEGIN {
    units[1]="K"; units[2]="M"; units[3]="G"; units[4]="T"
    size = kb
    i = 1
    while (size >= 1024 && i < 4) { size /= 1024; i++ }
    if (size >= 100 || i == 1) printf "%.0f%s", size, units[i]
    else if (size >= 10) printf "%.1f%s", size, units[i]
    else printf "%.2f%s", size, units[i]
  }'
}

bytes_to_kb() {
  local bytes=$1
  echo $(((bytes + 1023) / 1024))
}

section() {
  printf '\n%s\n' "$1"
}

row() {
  local label=$1
  local human=$2
  local path=$3
  printf '  %-22s %8s  %s\n' "$label" "$human" "$path"
}

# Populate MEASURE_KB for PATH using dust JSON (bytes) or du -sk.
measure_path_kb() {
  local path=$1
  MEASURE_KB=""

  if [[ ! -e "$path" ]]; then
    return 1
  fi

  if [[ "$MEASURE_TOOL" == "dust" ]]; then
    local json bytes
    json="$(dust -j -d 0 -P -c -o b -- "$path" 2>/dev/null || true)"
    bytes="$(
      jq -r '
        if type == "array" then .[0].size else .size end
        | capture("(?<n>[0-9]+)B?") | .n
      ' <<<"$json" 2>/dev/null || true
    )"
    if [[ -n "${bytes:-}" && "$bytes" =~ ^[0-9]+$ ]]; then
      MEASURE_KB="$(bytes_to_kb "$bytes")"
      return 0
    fi
  fi

  MEASURE_KB="$(du -sk "$path" 2>/dev/null | awk '{print $1}')" || true
  [[ -n "${MEASURE_KB:-}" ]]
}

measure() {
  local label=$1
  local path=$2

  if [[ ! -e "$path" ]]; then
    row "$label" "—" "$path (missing)"
    return 0
  fi

  if ! measure_path_kb "$path"; then
    row "$label" "?" "$path (unreadable)"
    return 0
  fi

  row "$label" "$(human_kb "$MEASURE_KB")" "$path"
  TOTAL_KB=$((TOTAL_KB + MEASURE_KB))
}

measure_nix_store() {
  local path="/nix/store"

  if [[ ! -e "$path" ]]; then
    row "store" "—" "$path (missing)"
    return 0
  fi

  if command -v nix >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    local bytes
    bytes="$(nix path-info --json --all 2>/dev/null | jq '[.[].narSize] | add' || true)"
    if [[ -n "${bytes:-}" && "$bytes" =~ ^[0-9]+$ ]]; then
      MEASURE_KB="$(bytes_to_kb "$bytes")"
      STORE_METHOD="nix path-info (NAR size)"
      row "store" "$(human_kb "$MEASURE_KB")" "$path [$STORE_METHOD]"
      TOTAL_KB=$((TOTAL_KB + MEASURE_KB))
      return 0
    fi
  fi

  # Fallback: dust/du filesystem walk.
  if [[ "$MEASURE_TOOL" == "dust" ]]; then
    printf '  measuring %s with dust...\r' "$path" >&2
  else
    printf '  measuring %s (may take a minute)...\r' "$path" >&2
  fi
  if measure_path_kb "$path"; then
    printf '\033[2K' >&2
    STORE_METHOD="$MEASURE_TOOL"
    row "store" "$(human_kb "$MEASURE_KB")" "$path"
    TOTAL_KB=$((TOTAL_KB + MEASURE_KB))
  else
    printf '\033[2K' >&2
    row "store" "?" "$path (unreadable)"
  fi
}

closure() {
  local label=$1
  local path=$2

  if [[ ! -e "$path" ]]; then
    row "$label" "—" "$path (missing)"
    return 0
  fi
  if ! command -v nix >/dev/null 2>&1; then
    row "$label" "—" "nix not on PATH"
    return 0
  fi

  local line size store_path
  if ! line="$(nix path-info -Sh "$path" 2>/dev/null | tail -n 1)"; then
    row "$label" "—" "$path (unreadable)"
    return 0
  fi
  # nix prints: <store-path><TAB><number> <unit>  e.g. "8.6 GiB"
  store_path="${line%%$'\t'*}"
  size="$(awk -F '\t' '{print $2}' <<<"$line" | awk '{print $1 $2}' | sed 's/iB$//')"
  row "$label" "${size:-?}" "${store_path:-$path}"
}

if command -v dust >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  MEASURE_TOOL="dust"
fi

printf 'Managed installation disk usage\n'
printf '===============================\n'
printf 'Host: %s (%s)\n' "$(hostname -s 2>/dev/null || hostname)" "$(uname -s)/$(uname -m)"
printf 'Measure tool: %s\n' "$MEASURE_TOOL"

section "Nix"
measure_nix_store
measure "state" "/nix/var/nix"
measure "user cache" "${XDG_CACHE_HOME:-$HOME/.cache}/nix"

section "Active Nix closures (subset of store; not in total)"
if [[ "$(uname -s)" == "Darwin" ]]; then
  closure "darwin system" "/run/current-system"
fi
hm_current="$HOME/.local/state/home-manager/gcroots/current-home"
if [[ -L "$hm_current" || -e "$hm_current" ]]; then
  closure "home-manager" "$hm_current"
elif [[ -L "$HOME/.local/state/nix/profiles/home-manager" ]]; then
  closure "home-manager" "$HOME/.local/state/nix/profiles/home-manager"
else
  row "home-manager" "—" "no current-home gcroots"
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  section "Homebrew"
  if [[ -d /opt/homebrew ]]; then
    measure "prefix" "/opt/homebrew"
  elif [[ -d /usr/local/Homebrew ]]; then
    measure "prefix" "/usr/local"
  else
    row "prefix" "—" "Homebrew not found"
  fi
fi

section "gstack"
measure "checkout" "$HOME/.local/share/gstack"
measure "state" "$HOME/.gstack"

section "Total (non-overlapping measured paths)"
row "total" "$(human_kb "$TOTAL_KB")" "nix + homebrew + gstack + caches"

printf '\nNotes:\n'
printf '  - /nix/store uses %s when available (much faster than walking the store).\n' \
  "nix path-info"
printf '  - NAR size can differ from on-disk usage when the store is optimised/hardlinked.\n'
printf '  - Active closures are already inside /nix/store and are shown only for reference.\n'
# shellcheck disable=SC2016 # backticks are intentional emphasis for the printed command
printf '  - Run `nix-collect-garbage -d` to reclaim old Nix generations if the store looks large.\n'
if [[ "$MEASURE_TOOL" != "dust" ]]; then
  # shellcheck disable=SC2016 # backticks are intentional emphasis for the printed name
  printf '  - Install/rebuild so `dust` is on PATH for faster non-store measurements.\n'
fi
