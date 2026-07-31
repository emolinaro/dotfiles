{ pkgs }:

let
  systemBwrap = pkgs.writeShellApplication {
    name = "bwrap";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      touch "$CODEX_BWRAP_MARKER"
    '';
  };
  conflictingBwrap = pkgs.writeShellApplication {
    name = "bwrap";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      touch "$CODEX_CONFLICTING_BWRAP_MARKER"
    '';
  };
  codexPackage = pkgs.callPackage ../packages/codex.nix {
    bwrapPath = "${systemBwrap}/bin/bwrap";
  };
in
pkgs.runCommand "codex-linux-system-bwrap-test"
  {
    nativeBuildInputs = [
      codexPackage
      conflictingBwrap
      pkgs.coreutils
    ];
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    export OPENAI_API_KEY=dummy
    export CODEX_BWRAP_MARKER="$TMPDIR/system-bwrap-called"
    export CODEX_CONFLICTING_BWRAP_MARKER="$TMPDIR/conflicting-bwrap-called"
    mkdir -p "$HOME"

    timeout 3 codex exec --skip-git-repo-check 'Reply with OK' \
      > "$TMPDIR/codex.log" 2>&1 || true

    if [[ ! -e "$CODEX_BWRAP_MARKER" ]]; then
      cat "$TMPDIR/codex.log" >&2
      echo "Codex did not probe the configured system bwrap" >&2
      exit 1
    fi
    if [[ -e "$CODEX_CONFLICTING_BWRAP_MARKER" ]]; then
      cat "$TMPDIR/codex.log" >&2
      echo "Codex selected a conflicting bwrap from the inherited PATH" >&2
      exit 1
    fi

    touch "$out"
  ''
