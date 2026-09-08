#!/usr/bin/env bash
# Update a precompiled release package in packages/ to a newer GitHub release.
#
# Usage:
#   update-release.sh <tool> [version]
#
# <tool> names a package file in packages/ that pins a GitHub release tarball
# (for example no-mistakes, treehouse, or nono). The script resolves the
# latest release, or uses the requested version, prefetches every platform
# tarball with `nix store prefetch-file`, and rewrites the pinned version
# and hashes in packages/<tool>.nix in place.
#
# Review the printed diff afterwards and run ./rebuild.sh to apply.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

usage() {
  echo "Usage: update-release.sh <tool> [version]" >&2
  echo "  tool     package in packages/, e.g. no-mistakes, treehouse, nono" >&2
  echo "  version  optional exact version (leading v is ignored);" >&2
  echo "           defaults to the latest GitHub release" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

tool="$1"
requested_version="${2:-}"
nix_file="$ROOT/packages/$tool.nix"

if [[ ! -f "$nix_file" ]]; then
  echo "Error: no such package file: $nix_file" >&2
  echo "Packages: $(find "$ROOT/packages" -name '*.nix' -exec basename {} .nix \; | tr '\n' ' ')" >&2
  exit 1
fi

for cmd in curl jq nix; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not on PATH: $cmd" >&2
    exit 1
  fi
done

# --- Read the pinned structure from packages/<tool>.nix ----------------------

current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";$/\1/p' "$nix_file" | head -n 1)"
if [[ -z "$current_version" ]]; then
  echo "Error: no pinned version found in $nix_file" >&2
  exit 1
fi

url_template="$(sed -n 's/^[[:space:]]*url = "\([^"]*\)";$/\1/p' "$nix_file" | head -n 1)"
if [[ -z "$url_template" ]]; then
  echo "Error: no release URL template found in $nix_file" >&2
  exit 1
fi

case "$url_template" in
  https://github.com/*) ;;
  *)
    echo "Error: $nix_file does not fetch a GitHub release: $url_template" >&2
    exit 1
    ;;
esac

github_path="${url_template#https://github.com/}"
owner="${github_path%%/*}"
repo="${github_path#*/}"
repo="${repo%%/*}"

# --- Resolve the target version ----------------------------------------------

if [[ -n "$requested_version" ]]; then
  new_version="${requested_version#v}"
else
  echo "==> Resolving the latest release of $owner/$repo"
  if ! tag="$(
    curl -fsSL "https://api.github.com/repos/$owner/$repo/releases/latest" |
      jq -r '.tag_name // empty'
  )"; then
    echo "Error: failed to query the GitHub API for $owner/$repo" >&2
    exit 1
  fi
  if [[ -z "$tag" ]]; then
    echo "Error: no published release found for $owner/$repo" >&2
    exit 1
  fi
  new_version="${tag#v}"
fi

if [[ "$new_version" == "$current_version" ]]; then
  echo "$tool is already pinned at $current_version; nothing to do."
  exit 0
fi

echo "==> Updating $tool from $current_version to $new_version"

# --- Prefetch every platform tarball ------------------------------------------

# Rows of "<system> <key> <value>" in file order. Every platform block lists
# its naming keys (os/arch or target) before its hash, so the hash row is the
# trigger to prefetch that platform with the values collected so far.
rows="$(
  awk '
    {
      line = $0
      gsub(/^[ \t]+|[ \t]+$/, "", line)
      if (line ~ /^(aarch64-darwin|x86_64-darwin|aarch64-linux|x86_64-linux) = \{/) {
        split(line, parts, " ")
        sys = parts[1]
      } else if (sys != "" && line ~ /^(os|arch|target|hash) = "[^"]*";$/) {
        split(line, parts, "\"")
        key = parts[1]
        gsub(/[ \t=]/, "", key)
        print sys, key, parts[2]
      }
    }
  ' "$nix_file"
)"

if [[ -z "$rows" ]]; then
  echo "Error: no platform release entries found in $nix_file" >&2
  exit 1
fi

# "<system> <old hash> <new hash>" rows for the rewrite below.
updates=""
cur_sys=""
cur_os=""
cur_arch=""
cur_target=""

while read -r sys key value; do
  if [[ "$sys" != "$cur_sys" ]]; then
    cur_sys="$sys"
    cur_os=""
    cur_arch=""
    cur_target=""
  fi
  case "$key" in
    os) cur_os="$value" ;;
    arch) cur_arch="$value" ;;
    target) cur_target="$value" ;;
    hash)
      url="$url_template"
      url="${url//\$\{version\}/$new_version}"
      url="${url//\$\{release\.os\}/$cur_os}"
      url="${url//\$\{release\.arch\}/$cur_arch}"
      url="${url//\$\{release\.target\}/$cur_target}"
      echo "==> $sys: prefetching ${url##*/}"
      if ! new_hash="$(nix store prefetch-file --json "$url" | jq -r .hash)"; then
        echo "Error: prefetch failed for $sys" >&2
        echo "       $url" >&2
        exit 1
      fi
      if [[ -z "$new_hash" || "$new_hash" == "null" ]]; then
        echo "Error: no hash returned for $sys" >&2
        echo "       $url" >&2
        exit 1
      fi
      updates+="$sys $value $new_hash"$'\n'
      ;;
  esac
done <<<"$rows"

if [[ -z "$updates" ]]; then
  echo "Error: no platform hashes found in $nix_file" >&2
  exit 1
fi

# --- Rewrite the pinned version and hashes ------------------------------------

# sed -i differs between GNU sed and BSD sed; pick the right spelling.
sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

sed_inplace "s|version = \"$current_version\";|version = \"$new_version\";|" "$nix_file"
if ! grep -Fq "version = \"$new_version\";" "$nix_file"; then
  echo "Error: failed to rewrite the version in $nix_file" >&2
  exit 1
fi

while read -r sys old_hash new_hash; do
  [[ -n "$sys" ]] || continue
  sed_inplace "s|$old_hash|$new_hash|" "$nix_file"
  if ! grep -Fq "$new_hash" "$nix_file"; then
    echo "Error: failed to rewrite the $sys hash in $nix_file" >&2
    exit 1
  fi
done <<<"$updates"

echo "==> $tool updated to $new_version"
echo
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" diff -- "packages/$tool.nix" || true
fi
echo "Next: review the diff above, then run ./rebuild.sh to apply."
