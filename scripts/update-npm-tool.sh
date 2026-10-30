#!/usr/bin/env bash
# Update an npm-packaged tool in packages/ to a newer published version.
#
# Usage:
#   update-npm-tool.sh <tool> [version]
#
# <tool> names a package in packages/ that pins a published npm artifact (for
# example gh-axi, quota-axi, tasks-axi, chrome-devtools-axi, lavish-axi, gnhf).
# The script resolves the latest published version, or uses the requested one,
# then rewrites the three pins in packages/<tool>.nix: version, tarball hash,
# and runtime dependency hash. The dependency hash can only be learned by
# building, so the script builds once with a placeholder and reads the real
# hash back from nix.
#
# Review the printed diff afterwards and run ./rebuild.sh to apply.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

usage() {
  echo "Usage: update-npm-tool.sh <tool> [version]" >&2
  echo "  tool     npm-packaged tool in packages/, e.g. quota-axi" >&2
  echo "  version  optional exact version to pin;" >&2
  echo "           defaults to the latest published version" >&2
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
  echo "npm-packaged tools: $(grep -l 'npm-tool.nix' "$ROOT"/packages/*.nix | xargs -n1 basename | sed 's/\.nix$//' | tr '\n' ' ')" >&2
  exit 1
fi

if ! grep -q 'npm-tool\.nix' "$nix_file"; then
  echo "Error: $tool is not an npm-packaged tool; use update-release.sh for release tarballs." >&2
  exit 1
fi

for cmd in curl jq nix; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not on PATH: $cmd" >&2
    exit 1
  fi
done

read_pin() {
  sed -n "s/^[[:space:]]*$1 = \"\([^\"]*\)\";$/\1/p" "$nix_file" | head -n 1
}

current_version="$(read_pin version)"
if [[ -z "$current_version" ]]; then
  echo "Error: no pinned version found in $nix_file" >&2
  exit 1
fi

# --- Resolve the target version ----------------------------------------------

if [[ -n "$requested_version" ]]; then
  new_version="${requested_version#v}"
else
  echo "==> Resolving the latest published version of $tool"
  if ! new_version="$(
    curl -fsSL "https://registry.npmjs.org/$tool" |
      jq -r '."dist-tags".latest // empty'
  )"; then
    echo "Error: failed to query the npm registry for $tool" >&2
    exit 1
  fi
  if [[ -z "$new_version" || "$new_version" == null ]]; then
    echo "Error: no published version found for $tool" >&2
    exit 1
  fi
fi

if [[ "$new_version" == "$current_version" ]]; then
  echo "$tool is already pinned at $current_version; nothing to do."
  exit 0
fi

echo "==> Updating $tool from $current_version to $new_version"

# --- Tarball hash -------------------------------------------------------------

tarball_url="https://registry.npmjs.org/$tool/-/$tool-$new_version.tgz"
echo "==> Prefetching $tarball_url"
new_hash="$(
  nix store prefetch-file --json "$tarball_url" |
    jq -r '.hash'
)"
if [[ -z "$new_hash" || "$new_hash" == null ]]; then
  echo "Error: could not prefetch $tarball_url" >&2
  exit 1
fi

# --- Dependency hash ----------------------------------------------------------

# Replace the pins with the new version and tarball hash, plus a placeholder
# dependency hash, then build once so nix reports the real dependency hash.
python3 - "$nix_file" "$new_version" "$new_hash" <<'PY'
import re, sys
path, version, tarball_hash = sys.argv[1:4]
text = open(path).read()
text = re.sub(r'^(\s*)version = "[^"]*";$', rf'\1version = "{version}";', text, count=1, flags=re.M)
text = re.sub(r'^(\s*)hash = "[^"]*";$', rf'\1hash = "{tarball_hash}";', text, count=1, flags=re.M)
text = re.sub(r'^(\s*)depsHash = "[^"]*";$', r'\1depsHash = lib.fakeHash;', text, count=1, flags=re.M)
open(path, 'w').write(text)
PY

echo "==> Installing the runtime dependencies to learn their hash"
build_output="$(
  nix build --impure --no-link --print-out-paths --expr "
    let
      flake = builtins.getFlake \"$ROOT\";
      pkgs = flake.inputs.nixpkgs.legacyPackages.\${builtins.currentSystem};
    in
    pkgs.callPackage $nix_file { }
  " 2>&1 || true
)"
new_deps_hash="$(printf '%s\n' "$build_output" | sed -n 's/^ *got: *//p' | head -n 1)"

if [[ -z "$new_deps_hash" ]]; then
  echo "Error: could not determine the dependency hash for $tool." >&2
  printf '%s\n' "$build_output" | tail -n 20 >&2
  echo "The version and tarball hash were updated; revert $nix_file if you do not want that." >&2
  exit 1
fi

python3 - "$nix_file" "$new_deps_hash" <<'PY'
import re, sys
path, deps_hash = sys.argv[1:3]
text = open(path).read()
text = re.sub(r'^(\s*)depsHash = lib\.fakeHash;$', rf'\1depsHash = "{deps_hash}";', text, count=1, flags=re.M)
open(path, 'w').write(text)
PY

echo "==> Rebuilding $tool with the new pins"
built_path="$(
  nix build --impure --no-link --print-out-paths --expr "
    let
      flake = builtins.getFlake \"$ROOT\";
      pkgs = flake.inputs.nixpkgs.legacyPackages.\${builtins.currentSystem};
    in
    pkgs.callPackage $nix_file { }
  "
)"
echo "==> $built_path/bin/$tool --version"
"$built_path/bin/$tool" --version

echo "==> Diff to review:"
git -C "$ROOT" --no-pager diff -- "$nix_file"
echo "Run ./rebuild.sh to apply."
