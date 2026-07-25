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

    if [[ -n "''${GNHF_TEST_INVOCATION_TRACE:-}" ]]; then
      printf '%s\n' invoked > "$GNHF_TEST_INVOCATION_TRACE"
    fi

    agent=""
    agent_path=""
    args=()
    while (( $# > 0 )); do
      case "$1" in
        --agent)
          agent="$2"
          shift 2
          ;;
        --agent-path)
          agent_path="$2"
          shift 2
          ;;
        --)
          args+=("$@")
          break
          ;;
        *)
          args+=("$1")
          shift
          ;;
      esac
    done

    test -n "$agent"
    test -n "$agent_path"
    marker="$("$agent_path" --probe)"
    printf '%s|%s|%s|%s\n' \
      "$agent" \
      "$marker" \
      "''${args[0]-}" \
      "''${args[1]-}"
  '';
  overrideAgent = mkAgent "caller-override";
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
  test "$(gnhf-codex -- --agent)" = \
    "codex|codex-direct|--|--agent"

  rejection_failures=0
  assert_rejects_controlled_option() {
    local launcher="$1"
    shift
    local trace="$TMPDIR/$launcher.invoked"
    local stdout="$TMPDIR/$launcher.stdout"
    local stderr="$TMPDIR/$launcher.stderr"

    if GNHF_TEST_INVOCATION_TRACE="$trace" \
      "$launcher" "$@" > "$stdout" 2> "$stderr"; then
      echo "$launcher accepted a caller-controlled worker option" >&2
      rejection_failures=$((rejection_failures + 1))
      return
    fi
    if [[ -e "$trace" ]]; then
      echo "$launcher invoked GNHF before rejecting a worker option" >&2
      rejection_failures=$((rejection_failures + 1))
    fi
    if ! ${pkgs.gnugrep}/bin/grep -Fq \
      "error: $launcher controls --agent and --agent-path" "$stderr"; then
      echo "$launcher did not explain its controlled worker options" >&2
      rejection_failures=$((rejection_failures + 1))
    fi
  }

  assert_rejects_controlled_option \
    gnhf-codex objective --agent opencode
  assert_rejects_controlled_option \
    gnhf-opencode objective --agent=codex
  assert_rejects_controlled_option \
    gnhf-codex-nono objective --agent-path ${overrideAgent}
  assert_rejects_controlled_option \
    gnhf-opencode-nono objective --agent-path=${overrideAgent}
  test "$rejection_failures" -eq 0

  mkdir "$out"
''
