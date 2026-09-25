{ lib, pkgs }:

let
  claudeCode = pkgs.callPackage ../packages/claude-code.nix { };
  codex = pkgs.callPackage ../packages/codex.nix { };
  opencode = pkgs.callPackage ../packages/opencode.nix { };
in
pkgs.runCommand "agent-clis-test"
  {
    nativeBuildInputs = [
      claudeCode
      codex
      opencode
    ];
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    # Each CLI must expose its bin name and report the pinned version.
    claude --version | grep -qF "${claudeCode.version}"
    codex --version | grep -qF "${codex.version}"
    opencode --version | grep -qF "${opencode.version}"

    # The self-updaters must be disabled so the pinned version stays
    # authoritative inside the read-only Nix store.
    grep -q "DISABLE_AUTOUPDATER" "${lib.getExe claudeCode}"
    grep -q "OPENCODE_DISABLE_AUTOUPDATE" "${lib.getExe opencode}"

    touch "$out"
  ''
