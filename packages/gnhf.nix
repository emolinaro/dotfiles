{ coreutils, lib, nodejs, symlinkJoin, writeShellScriptBin }:

let
  version = "0.1.42";
  npmPackage = "gnhf@${version}";
  npmExec = "${nodejs}/bin/npm exec --yes --package ${npmPackage} -- gnhf";

  gnhfWrapper = writeShellScriptBin "gnhf" ''
    exec ${npmExec} "$@"
  '';
  gnhfCodexWrapper = writeShellScriptBin "gnhf-codex" ''
    exec ${npmExec} --agent codex "$@"
  '';
  gnhfOpencodeWrapper = writeShellScriptBin "gnhf-opencode" ''
    exec ${npmExec} --agent opencode "$@"
  '';
  gnhfCodexNonoWrapper = writeShellScriptBin "gnhf-codex-nono" ''
    set -euo pipefail

    sandbox_bin="$(command -v codex-nono || true)"
    if [ -z "$sandbox_bin" ]; then
      echo "error: codex-nono wrapper is not installed" >&2
      exit 1
    fi

    wrapper_dir=$(${coreutils}/bin/mktemp -d)
    cleanup() {
      ${coreutils}/bin/rm -rf "$wrapper_dir"
    }
    trap cleanup EXIT

    ${coreutils}/bin/ln -s "$sandbox_bin" "$wrapper_dir/codex"
    PATH="$wrapper_dir:$PATH" exec ${npmExec} --agent codex "$@"
  '';
  gnhfOpencodeNonoWrapper = writeShellScriptBin "gnhf-opencode-nono" ''
    set -euo pipefail

    sandbox_bin="$(command -v opencode-nono || true)"
    if [ -z "$sandbox_bin" ]; then
      echo "error: opencode-nono wrapper is not installed" >&2
      exit 1
    fi

    wrapper_dir=$(${coreutils}/bin/mktemp -d)
    cleanup() {
      ${coreutils}/bin/rm -rf "$wrapper_dir"
    }
    trap cleanup EXIT

    ${coreutils}/bin/ln -s "$sandbox_bin" "$wrapper_dir/opencode"
    PATH="$wrapper_dir:$PATH" exec ${npmExec} --agent opencode "$@"
  '';
in
symlinkJoin {
  name = "gnhf";
  inherit version;
  paths = [
    gnhfWrapper
    gnhfCodexWrapper
    gnhfOpencodeWrapper
    gnhfCodexNonoWrapper
    gnhfOpencodeNonoWrapper
  ];
  meta = {
    description = "gnhf orchestrator CLI with quick agent wrappers";
    homepage = "https://github.com/kunchenguid/gnhf";
    license = lib.licenses.mit;
  };
}
