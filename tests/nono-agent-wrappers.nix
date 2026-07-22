{
  pkgs,
  wrapperModule,
}:

let
  mkRecorder =
    name:
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        : "''${NONO_TEST_TRACE:?NONO_TEST_TRACE must name a trace file}"
        printf '%s\n' "$@" > "$NONO_TEST_TRACE"
        exit "''${NONO_TEST_EXIT_CODE:-0}"
      '';
    };

  fakeNono = mkRecorder "nono";
  fakeAgents = {
    claude = mkRecorder "claude";
    codex = mkRecorder "codex";
    opencode = mkRecorder "opencode";
    pi = mkRecorder "pi";
  };
  agentExecutables = pkgs.lib.mapAttrs (name: package: "${package}/bin/${name}") fakeAgents;

  wrappers = pkgs.callPackage wrapperModule {
    inherit agentExecutables;
    nonoPackage = fakeNono;
  };
  wrappersWithMissingPi = pkgs.callPackage wrapperModule {
    agentExecutables = agentExecutables // {
      pi = "/definitely/missing/pi";
    };
    nonoPackage = fakeNono;
  };
in
pkgs.runCommand "nono-agent-wrappers-test"
  {
    nativeBuildInputs = [
      pkgs.diffutils
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail

    export HOME="$TMPDIR/home"
    profiles="$HOME/.config/nono/profiles"
    mkdir -p "$profiles"
    for agent in claude codex opencode pi; do
      touch "$profiles/dotfiles-$agent.json"
    done

    assert_normal_wrapper() {
      local agent="$1"
      local real_executable="$2"
      shift 2

      export NONO_TEST_TRACE="$TMPDIR/$agent.trace"
      unset NONO_TEST_EXIT_CODE
      "${wrappers}/bin/$agent" "argument with spaces" -- literal

      expected=(
        run
        --profile
        "dotfiles-$agent"
        --workdir
        "$PWD"
        --
        "$real_executable"
      )
      if [[ "$agent" == codex ]]; then
        expected+=(
          --sandbox
          danger-full-access
          --ask-for-approval
          on-request
        )
      fi
      expected+=("argument with spaces" -- literal)
      printf '%s\n' "''${expected[@]}" > "$TMPDIR/$agent.expected"
      diff -u "$TMPDIR/$agent.expected" "$NONO_TEST_TRACE"
    }

    assert_normal_wrapper claude ${agentExecutables.claude}
    assert_normal_wrapper codex ${agentExecutables.codex}
    assert_normal_wrapper opencode ${agentExecutables.opencode}
    assert_normal_wrapper pi ${agentExecutables.pi}

    rm "$profiles/dotfiles-opencode.json"
    export NONO_TEST_TRACE="$TMPDIR/missing-profile.trace"
    if "${wrappers}/bin/opencode" > "$TMPDIR/missing-profile.stdout" 2> "$TMPDIR/missing-profile.stderr"; then
      echo "opencode unexpectedly started without its local profile" >&2
      exit 1
    fi
    test ! -e "$NONO_TEST_TRACE"
    grep -F "missing Nono profile" "$TMPDIR/missing-profile.stderr"

    export NONO_TEST_TRACE="$TMPDIR/unsafe.trace"
    export NONO_TEST_EXIT_CODE=23
    set +e
    "${wrappers}/bin/pi-unsafe" "unsafe argument" 2> "$TMPDIR/unsafe.stderr"
    unsafe_status=$?
    set -e
    test "$unsafe_status" -eq 23
    printf '%s\n' "unsafe argument" > "$TMPDIR/unsafe.expected"
    diff -u "$TMPDIR/unsafe.expected" "$NONO_TEST_TRACE"
    grep -F "UNSANDBOXED" "$TMPDIR/unsafe.stderr"

    unset NONO_TEST_EXIT_CODE
    set +e
    "${wrappersWithMissingPi}/bin/pi" > "$TMPDIR/missing-executable.stdout" 2> "$TMPDIR/missing-executable.stderr"
    missing_status=$?
    set -e
    test "$missing_status" -eq 127
    grep -F "real pi executable is unavailable" "$TMPDIR/missing-executable.stderr"

    touch "$out"
  ''
