{ codexPackage, pkgs }:

let
  systemBwrap = pkgs.writeShellApplication {
    name = "bwrap";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      touch "$CODEX_BWRAP_MARKER"
    '';
  };
in
pkgs.runCommand "codex-linux-system-bwrap-test"
  {
    nativeBuildInputs = [
      codexPackage
      pkgs.coreutils
      systemBwrap
    ];
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    export OPENAI_API_KEY=dummy
    export CODEX_BWRAP_MARKER="$TMPDIR/system-bwrap-called"
    mkdir -p "$HOME"

    timeout 3 codex exec --skip-git-repo-check 'Reply with OK' \
      > "$TMPDIR/codex.log" 2>&1 || true

    if [[ ! -e "$CODEX_BWRAP_MARKER" ]]; then
      cat "$TMPDIR/codex.log" >&2
      echo "Codex did not probe the system bwrap from PATH" >&2
      exit 1
    fi

    touch "$out"
  ''
