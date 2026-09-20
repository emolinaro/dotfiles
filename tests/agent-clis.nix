{ pkgs }:

pkgs.runCommand "agent-clis-test"
  {
    nativeBuildInputs = [
      (pkgs.callPackage ./../packages/claude-code.nix { })
      (pkgs.callPackage ./../packages/codex.nix { })
      (pkgs.callPackage ./../packages/opencode.nix { })
    ];
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    # Each CLI must expose its bin name and a --version that matches the pin.
    claude --version | grep -q "2\.1\.278"
    codex --version | grep -q "0\.155\.1"
    opencode --version | grep -q "1\.18\.31"

    touch "$out"
  ''
