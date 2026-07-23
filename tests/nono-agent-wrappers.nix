{
  agentRegistry,
  pkgs,
  profiles,
  wrapperModule,
}:

let
  agentNames = builtins.attrNames agentRegistry;
  configuredHome = "/tmp/nono-wrapper-test-home";
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
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
    ];
    text = ''
      : "''${WRAPPER_TEST_TRACE:?WRAPPER_TEST_TRACE must name a trace file}"
      if [[ -n "''${BASH_ENV:-}" || -n "''${GIT_DIR:-}" || -n "''${LD_PRELOAD:-}" \
        || -n "''${NONO_ALLOW:-}" || -n "''${NONO_PROFILE:-}" ]]; then
        echo "ambient loader, Git, or Nono variable reached Nono" >&2
        exit 1
      fi
      if [[ "''${DOTFILES_AGENT_HOME:-}" != ${configuredHome}/.cache/nono/session.*/home \
        || "''${HOME:-}" != "$DOTFILES_AGENT_HOME" \
        || "''${DOTFILES_HOST_HOME:-}" != ${configuredHome} \
        || "''${TMPDIR:-}" != ${configuredHome}/.cache/nono/session.*/tmp \
        || -n "''${TMP:-}" || -n "''${TEMP:-}" ]]; then
        echo "Nono did not receive isolated session paths" >&2
        exit 1
      fi
      if [[ "''${XDG_CONFIG_HOME:-}" != /nix/store/* ]]; then
        echo "Nono config is not store-backed: ''${XDG_CONFIG_HOME:-<unset>}" >&2
        exit 1
      fi
      if [[ ! -L "$DOTFILES_AGENT_HOME/.agents" ]]; then
        echo "shared agent skills were not staged read-only" >&2
        exit 1
      fi
      if [[ -n "''${WRAPPER_TEST_MUTATE_GIT:-}" ]]; then
        workdir=""
        previous=""
        for argument in "$@"; do
          if [[ "$previous" == "--workdir" ]]; then
            workdir="$argument"
            break
          fi
          previous="$argument"
        done
        git_dir="$(git -C "$workdir" rev-parse --path-format=absolute --git-dir)"
        common_dir="$(git -C "$workdir" rev-parse --path-format=absolute --git-common-dir)"
        printf '%s\n' malicious > "$common_dir/config"
        mkdir -p "$common_dir/hooks"
        printf '%s\n' malicious > "$common_dir/hooks/pre-push"
        printf '%s\n' malicious > "$git_dir/config.worktree"
        if [[ -f "$(git -C "$workdir" rev-parse --show-toplevel)/.git" ]]; then
          printf '%s\n' malicious > "$(git -C "$workdir" rev-parse --show-toplevel)/.git"
        fi
      fi
      printf '%s\n' "$@" > "$WRAPPER_TEST_TRACE"
      exit "''${WRAPPER_TEST_EXIT_CODE:-0}"
    '';
  };
  fakeHomeGit = pkgs.writeShellApplication {
    name = "git";
    text = ''
      printf '%s\n' ${configuredHome}
    '';
  };
  fakeAgents = builtins.mapAttrs (name: _: mkRecorder name) agentRegistry;
  agentExecutables = pkgs.lib.mapAttrs (name: package: "${package}/bin/${name}") fakeAgents;

  wrappers = pkgs.callPackage wrapperModule {
    inherit agentExecutables agentRegistry profiles;
    homeDirectory = configuredHome;
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
    inherit agentExecutables agentRegistry;
    homeDirectory = configuredHome;
    nonoPackage = fakeNono;
    profiles = profilesWithoutOpencode;
  };
  wrappersWithMissingPi = pkgs.callPackage wrapperModule {
    agentExecutables = agentExecutables // {
      pi = "/definitely/missing/pi";
    };
    inherit agentRegistry profiles;
    homeDirectory = configuredHome;
    nonoPackage = fakeNono;
  };
  wrappersWithHomeWorktree = pkgs.callPackage wrapperModule {
    inherit agentExecutables agentRegistry profiles;
    git = fakeHomeGit;
    homeDirectory = configuredHome;
    nonoPackage = fakeNono;
  };
  unexpectedAgentEvaluation = builtins.tryEval (
    builtins.deepSeq (pkgs.callPackage wrapperModule {
      agentExecutables = agentExecutables // {
        unexpected = "/nix/store/unexpected/bin/unexpected";
      };
      inherit agentRegistry profiles;
      homeDirectory = configuredHome;
      nonoPackage = fakeNono;
    }) true
  );
  preloadSource = pkgs.writeText "nono-wrapper-preload.c" ''
    #include <fcntl.h>
    #include <stdlib.h>
    #include <unistd.h>

    __attribute__((constructor)) static void record_preload(void) {
      const char *trace = getenv("WRAPPER_TEST_PRELOAD_TRACE");
      if (trace == NULL) {
        return;
      }
      int descriptor = open(trace, O_WRONLY | O_CREAT | O_APPEND, 0600);
      if (descriptor >= 0) {
        write(descriptor, "loaded\n", 7);
        close(descriptor);
      }
    }
  '';
  preloadLibrary =
    if pkgs.stdenv.hostPlatform.isLinux then
      pkgs.stdenv.mkDerivation {
        name = "nono-wrapper-preload";
        dontUnpack = true;
        buildPhase = ''
          $CC -shared -fPIC ${preloadSource} -o preload.so
        '';
        installPhase = ''
          mkdir -p "$out/lib"
          cp preload.so "$out/lib/"
        '';
      }
    else
      null;
in
assert !unexpectedAgentEvaluation.success;
pkgs.runCommand "nono-agent-wrappers-test"
  {
    nativeBuildInputs = [
      pkgs.diffutils
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail

    export HOME=${configuredHome}
    mkdir -p \
      "$HOME/.agents" \
      "$HOME/.claude/skills" \
      "$HOME/.codex/plugins" \
      "$HOME/.codex/rules" \
      "$HOME/.codex/skills" \
      "$HOME/.config/opencode/plugins" \
      "$HOME/.config/opencode/skills" \
      "$HOME/.pi/agent"
    touch \
      "$HOME/.claude/CLAUDE.md" \
      "$HOME/.codex/AGENTS.md" \
      "$HOME/.codex/config.toml" \
      "$HOME/.codex/hooks.json" \
      "$HOME/.config/opencode/AGENTS.md" \
      "$HOME/.config/opencode/opencode.json" \
      "$HOME/.pi/agent/AGENTS.md" \
      "$HOME/.pi/agent/settings.json"

    repo="$TMPDIR/repo"
    mkdir -p "$repo/subdir"
    ${pkgs.git}/bin/git init -q "$repo"
    ${pkgs.git}/bin/git -C "$repo" config user.name test
    ${pkgs.git}/bin/git -C "$repo" config user.email test@example.com
    printf '%s\n' initial > "$repo/tracked"
    ${pkgs.git}/bin/git -C "$repo" add tracked
    ${pkgs.git}/bin/git -C "$repo" commit -qm initial
    cd "$repo/subdir"
    export GIT_DIR=/definitely/missing
    export NONO_ALLOW=/
    export NONO_PROFILE=untrusted
    cat > "$TMPDIR/bash-env" <<'EOF'
    touch "$WRAPPER_TEST_BASH_ENV_TRACE"
    EOF
    malicious_path="$TMPDIR/malicious-path"
    mkdir -p "$malicious_path"
    for command_name in env mkdir mktemp; do
      printf '%s\n' '#!/bin/sh' 'touch "$WRAPPER_TEST_PATH_TRACE"' > "$malicious_path/$command_name"
      chmod +x "$malicious_path/$command_name"
    done

    assert_normal_wrapper() {
      local agent="$1"
      local real_executable="$2"
      local original_path="$PATH"

      export WRAPPER_TEST_TRACE="$TMPDIR/$agent.trace"
      export WRAPPER_TEST_BASH_ENV_TRACE="$TMPDIR/$agent.bash-env.trace"
      export WRAPPER_TEST_PATH_TRACE="$TMPDIR/$agent.path.trace"
      export BASH_ENV="$TMPDIR/bash-env"
      export PATH="$malicious_path"
      unset WRAPPER_TEST_EXIT_CODE
      "${wrappers}/bin/$agent" "argument with spaces" -- literal
      export PATH="$original_path"
      test ! -e "$WRAPPER_TEST_BASH_ENV_TRACE"
      test ! -e "$WRAPPER_TEST_PATH_TRACE"
      unset BASH_ENV WRAPPER_TEST_BASH_ENV_TRACE WRAPPER_TEST_PATH_TRACE

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
      ${pkgs.diffutils}/bin/diff -u "$TMPDIR/$agent.expected" "$WRAPPER_TEST_TRACE"
      test -z "$(${pkgs.findutils}/bin/find "$HOME/.cache/nono" -mindepth 1 -maxdepth 1 -print -quit)"
    }

    ${pkgs.lib.concatMapStringsSep "\n" (
      name: "assert_normal_wrapper ${name} ${agentExecutables.${name}}"
    ) agentNames}
    unset GIT_DIR NONO_ALLOW NONO_PROFILE

    ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      export WRAPPER_TEST_TRACE="$TMPDIR/preload.trace"
      export WRAPPER_TEST_PRELOAD_TRACE="$TMPDIR/preload.loaded"
      export LD_PRELOAD=${preloadLibrary}/lib/preload.so
      "${wrappers}/bin/claude"
      test ! -e "$WRAPPER_TEST_PRELOAD_TRACE"
      unset LD_PRELOAD WRAPPER_TEST_PRELOAD_TRACE
    ''}

    ${pkgs.git}/bin/git -C "$repo" config test.value trusted
    mkdir -p "$repo/.git/hooks"
    printf '%s\n' trusted > "$repo/.git/hooks/pre-push"
    export WRAPPER_TEST_TRACE="$TMPDIR/git-restore.trace"
    export WRAPPER_TEST_MUTATE_GIT=1
    "${wrappers}/bin/claude"
    unset WRAPPER_TEST_MUTATE_GIT
    ${pkgs.gnugrep}/bin/grep -F "value = trusted" "$repo/.git/config"
    test "$(<"$repo/.git/hooks/pre-push")" = trusted
    test ! -e "$repo/.git/config.worktree"

    linked="$TMPDIR/linked"
    ${pkgs.git}/bin/git -C "$repo" worktree add -qb linked "$linked"
    mkdir -p "$linked/subdir"
    linked_git_dir="$(${pkgs.git}/bin/git -C "$linked" rev-parse --path-format=absolute --git-dir)"
    common_dir="$(${pkgs.git}/bin/git -C "$linked" rev-parse --path-format=absolute --git-common-dir)"
    printf '%s\n' trusted > "$linked_git_dir/config.worktree"
    cd "$linked/subdir"
    export WRAPPER_TEST_TRACE="$TMPDIR/linked.trace"
    export WRAPPER_TEST_MUTATE_GIT=1
    "${wrappers}/bin/codex" linked
    unset WRAPPER_TEST_MUTATE_GIT
    test "$(<"$linked/.git")" = "gitdir: $linked_git_dir"
    test "$(<"$linked_git_dir/config.worktree")" = trusted
    ${pkgs.gnugrep}/bin/grep -F "value = trusted" "$common_dir/config"
    test "$(<"$common_dir/hooks/pre-push")" = trusted

    expected=(
      run
      --profile
      "${profiles}/dotfiles-codex.json"
      --allow
      "$linked"
      --allow
      "$linked_git_dir"
      --allow
      "$common_dir"
      --workdir
      "$linked/subdir"
      --
      "${agentExecutables.codex}"
      --sandbox
      danger-full-access
      --ask-for-approval
      on-request
      linked
    )
    printf '%s\n' "''${expected[@]}" > "$TMPDIR/linked.expected"
    ${pkgs.diffutils}/bin/diff -u "$TMPDIR/linked.expected" "$WRAPPER_TEST_TRACE"

    export WRAPPER_TEST_TRACE="$TMPDIR/missing-profile.trace"
    if "${wrappersWithMissingProfile}/bin/opencode" > "$TMPDIR/missing-profile.stdout" 2> "$TMPDIR/missing-profile.stderr"; then
      echo "opencode unexpectedly started without its local profile" >&2
      exit 1
    fi
    test ! -e "$WRAPPER_TEST_TRACE"
    ${pkgs.gnugrep}/bin/grep -F "missing Nono profile" "$TMPDIR/missing-profile.stderr"

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
    ${pkgs.gnugrep}/bin/grep -F "must be launched inside a Git worktree" "$TMPDIR/outside-worktree.stderr"

    cd "$repo/subdir"
    export WRAPPER_TEST_TRACE="$TMPDIR/home-worktree.trace"
    set +e
    "${wrappersWithHomeWorktree}/bin/codex" > "$TMPDIR/home-worktree.stdout" 2> "$TMPDIR/home-worktree.stderr"
    home_status=$?
    set -e
    test "$home_status" -eq 78
    test ! -e "$WRAPPER_TEST_TRACE"
    ${pkgs.gnugrep}/bin/grep -F "worktree that contains HOME" "$TMPDIR/home-worktree.stderr"

    export HOME="$TMPDIR/unexpected-home"
    mkdir -p "$HOME"
    export WRAPPER_TEST_TRACE="$TMPDIR/unexpected-home.trace"
    set +e
    "${wrappers}/bin/codex" > "$TMPDIR/unexpected-home.stdout" 2> "$TMPDIR/unexpected-home.stderr"
    unexpected_home_status=$?
    set -e
    test "$unexpected_home_status" -eq 78
    test ! -e "$WRAPPER_TEST_TRACE"
    ${pkgs.gnugrep}/bin/grep -F "refusing unexpected HOME" "$TMPDIR/unexpected-home.stderr"

    export HOME=${configuredHome}
    export WRAPPER_TEST_TRACE="$TMPDIR/unsafe.trace"
    export WRAPPER_TEST_EXIT_CODE=23
    set +e
    "${wrappers}/bin/pi-unsafe" "unsafe argument" 2> "$TMPDIR/unsafe.stderr"
    unsafe_status=$?
    set -e
    test "$unsafe_status" -eq 23
    printf '%s\n' "unsafe argument" > "$TMPDIR/unsafe.expected"
    ${pkgs.diffutils}/bin/diff -u "$TMPDIR/unsafe.expected" "$WRAPPER_TEST_TRACE"
    ${pkgs.gnugrep}/bin/grep -F "UNSANDBOXED" "$TMPDIR/unsafe.stderr"

    unset WRAPPER_TEST_EXIT_CODE
    set +e
    "${wrappersWithMissingPi}/bin/pi" > "$TMPDIR/missing-executable.stdout" 2> "$TMPDIR/missing-executable.stderr"
    missing_status=$?
    set -e
    test "$missing_status" -eq 127
    ${pkgs.gnugrep}/bin/grep -F "real pi executable is unavailable" "$TMPDIR/missing-executable.stderr"

    touch "$out"
  ''
