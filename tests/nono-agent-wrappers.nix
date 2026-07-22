{
  pkgs,
  profiles,
  wrapperModule,
}:

let
  mkRecorder =
    name:
    pkgs.writeShellApplication {
      inherit name;
      text = ''
        : "''${WRAPPER_TEST_TRACE:?WRAPPER_TEST_TRACE must name a trace file}"
        printf '%s\n' "$@" > "$WRAPPER_TEST_TRACE"
        exit "''${WRAPPER_TEST_EXIT_CODE:-0}"
      '';
    };

  fakeNono = pkgs.writeShellApplication {
    name = "nono";
    text = ''
      : "''${WRAPPER_TEST_TRACE:?WRAPPER_TEST_TRACE must name a trace file}"
      if [[ -n "''${GIT_DIR:-}" || -n "''${NONO_ALLOW:-}" || -n "''${NONO_PROFILE:-}" ]]; then
        echo "ambient Git or Nono policy variable reached Nono" >&2
        exit 1
      fi
      if [[ "''${XDG_CONFIG_HOME:-}" != /nix/store/* ]]; then
        echo "Nono config is not store-backed: ''${XDG_CONFIG_HOME:-<unset>}" >&2
        exit 1
      fi
      printf '%s\n' "$@" > "$WRAPPER_TEST_TRACE"
      exit "''${WRAPPER_TEST_EXIT_CODE:-0}"
    '';
  };
  fakeHomeGit = pkgs.writeShellApplication {
    name = "git";
    text = ''
      printf '%s\n' /tmp
    '';
  };
  fakeAgents = {
    claude = mkRecorder "claude";
    codex = mkRecorder "codex";
    opencode = mkRecorder "opencode";
    pi = mkRecorder "pi";
  };
  agentExecutables = pkgs.lib.mapAttrs (name: package: "${package}/bin/${name}") fakeAgents;

  wrappers = pkgs.callPackage wrapperModule {
    inherit agentExecutables profiles;
    homeDirectory = "/tmp";
    nonoPackage = fakeNono;
  };
  profilesWithoutOpencode = pkgs.runCommand "nono-test-profiles-without-opencode" { } ''
    mkdir -p "$out"
    cp ${profiles}/dotfiles-agent-base.json "$out/"
    for agent in claude codex pi; do
      cp "${profiles}/dotfiles-$agent.json" "$out/"
    done
  '';
  wrappersWithMissingProfile = pkgs.callPackage wrapperModule {
    inherit agentExecutables;
    homeDirectory = "/tmp";
    nonoPackage = fakeNono;
    profiles = profilesWithoutOpencode;
  };
  wrappersWithMissingPi = pkgs.callPackage wrapperModule {
    agentExecutables = agentExecutables // {
      pi = "/definitely/missing/pi";
    };
    homeDirectory = "/tmp";
    nonoPackage = fakeNono;
    inherit profiles;
  };
  wrappersWithHomeWorktree = pkgs.callPackage wrapperModule {
    inherit agentExecutables profiles;
    git = fakeHomeGit;
    homeDirectory = "/tmp";
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

    export HOME=/tmp
    repo="$TMPDIR/repo"
    mkdir -p "$repo/subdir"
    ${pkgs.git}/bin/git init -q "$repo"
    cd "$repo/subdir"
    export GIT_DIR=/definitely/missing
    export NONO_ALLOW=/
    export NONO_PROFILE=untrusted

    assert_normal_wrapper() {
      local agent="$1"
      local real_executable="$2"
      shift 2

      export WRAPPER_TEST_TRACE="$TMPDIR/$agent.trace"
      unset WRAPPER_TEST_EXIT_CODE
      "${wrappers}/bin/$agent" "argument with spaces" -- literal

      expected=(
        run
        --profile
        "${profiles}/dotfiles-$agent.json"
        --allow
        "$repo"
        --workdir
        "$repo/subdir"
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
      diff -u "$TMPDIR/$agent.expected" "$WRAPPER_TEST_TRACE"
    }

    assert_normal_wrapper claude ${agentExecutables.claude}
    assert_normal_wrapper codex ${agentExecutables.codex}
    assert_normal_wrapper opencode ${agentExecutables.opencode}
    assert_normal_wrapper pi ${agentExecutables.pi}

    export WRAPPER_TEST_TRACE="$TMPDIR/missing-profile.trace"
    if "${wrappersWithMissingProfile}/bin/opencode" > "$TMPDIR/missing-profile.stdout" 2> "$TMPDIR/missing-profile.stderr"; then
      echo "opencode unexpectedly started without its local profile" >&2
      exit 1
    fi
    test ! -e "$WRAPPER_TEST_TRACE"
    grep -F "missing Nono profile" "$TMPDIR/missing-profile.stderr"

    outside="$TMPDIR/outside"
    mkdir -p "$outside"
    cd "$outside"
    export WRAPPER_TEST_TRACE="$TMPDIR/outside-worktree.trace"
    set +e
    "${wrappers}/bin/claude" > "$TMPDIR/outside-worktree.stdout" 2> "$TMPDIR/outside-worktree.stderr"
    outside_status=$?
    set -e
    test "$outside_status" -eq 78
    test ! -e "$WRAPPER_TEST_TRACE"
    grep -F "must be launched inside a Git worktree" "$TMPDIR/outside-worktree.stderr"

    cd "$repo/subdir"
    export WRAPPER_TEST_TRACE="$TMPDIR/home-worktree.trace"
    set +e
    "${wrappersWithHomeWorktree}/bin/codex" > "$TMPDIR/home-worktree.stdout" 2> "$TMPDIR/home-worktree.stderr"
    home_status=$?
    set -e
    test "$home_status" -eq 78
    test ! -e "$WRAPPER_TEST_TRACE"
    grep -F "worktree that contains HOME" "$TMPDIR/home-worktree.stderr"

    export HOME="$TMPDIR/unexpected-home"
    mkdir -p "$HOME"
    export WRAPPER_TEST_TRACE="$TMPDIR/unexpected-home.trace"
    set +e
    "${wrappers}/bin/codex" > "$TMPDIR/unexpected-home.stdout" 2> "$TMPDIR/unexpected-home.stderr"
    unexpected_home_status=$?
    set -e
    test "$unexpected_home_status" -eq 78
    test ! -e "$WRAPPER_TEST_TRACE"
    grep -F "refusing unexpected HOME" "$TMPDIR/unexpected-home.stderr"

    export WRAPPER_TEST_TRACE="$TMPDIR/unsafe.trace"
    export WRAPPER_TEST_EXIT_CODE=23
    set +e
    "${wrappers}/bin/pi-unsafe" "unsafe argument" 2> "$TMPDIR/unsafe.stderr"
    unsafe_status=$?
    set -e
    test "$unsafe_status" -eq 23
    printf '%s\n' "unsafe argument" > "$TMPDIR/unsafe.expected"
    diff -u "$TMPDIR/unsafe.expected" "$WRAPPER_TEST_TRACE"
    grep -F "UNSANDBOXED" "$TMPDIR/unsafe.stderr"

    unset WRAPPER_TEST_EXIT_CODE
    set +e
    "${wrappersWithMissingPi}/bin/pi" > "$TMPDIR/missing-executable.stdout" 2> "$TMPDIR/missing-executable.stderr"
    missing_status=$?
    set -e
    test "$missing_status" -eq 127
    grep -F "real pi executable is unavailable" "$TMPDIR/missing-executable.stderr"

    touch "$out"
  ''
