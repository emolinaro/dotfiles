{
  launcherModule,
  pkgs,
}:

let
  mkAgent =
    marker:
    pkgs.writeShellScript "gnhf-test-agent-${marker}" ''
      set -euo pipefail
      printf '%s\n' '${marker}'
    '';
  fakeGnhf = pkgs.writeShellScript "gnhf-test-cli" ''
    set -euo pipefail

    agent=""
    args=()
    while (( $# > 0 )); do
      case "$1" in
        --agent)
          agent="$2"
          shift 2
          ;;
        *)
          args+=("$1")
          shift
          ;;
      esac
    done

    test -n "$agent"
    marker="$("$agent" --probe)"
    printf '%s|%s|%s|%s\n' \
      "$agent" \
      "$marker" \
      "''${args[0]-}" \
      "''${args[1]-}"
  '';
  launchers = (pkgs.callPackage launcherModule { }) {
    gnhfExecutable = fakeGnhf;
    variants = [
      {
        agent = "codex";
        executable = mkAgent "codex-direct";
        name = "codex";
      }
      {
        agent = "opencode";
        executable = mkAgent "opencode-direct";
        name = "opencode";
      }
      {
        agent = "codex";
        executable = mkAgent "codex-nono";
        name = "codex-nono";
      }
      {
        agent = "opencode";
        executable = mkAgent "opencode-nono";
        name = "opencode-nono";
      }
    ];
  };
in
pkgs.runCommand "gnhf-agent-launchers-test" { nativeBuildInputs = [ launchers ]; } ''
  set -euo pipefail

  test "$(gnhf-codex objective --max-iterations)" = \
    "codex|codex-direct|objective|--max-iterations"
  test "$(gnhf-opencode objective --max-iterations)" = \
    "opencode|opencode-direct|objective|--max-iterations"
  test "$(gnhf-codex-nono objective --max-iterations)" = \
    "codex|codex-nono|objective|--max-iterations"
  test "$(gnhf-opencode-nono objective --max-iterations)" = \
    "opencode|opencode-nono|objective|--max-iterations"

  mkdir "$out"
''
