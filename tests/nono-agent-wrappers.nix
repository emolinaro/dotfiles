{
  agentRegistry,
  pkgs,
  profiles,
  wrapperModule,
}:

let
  agentNames = builtins.attrNames agentRegistry;
  configuredHome = "/@NONO_TEST_HOME@";
  mkRecorder =
    name:
    let
      authRelative = builtins.head agentRegistry.${name}.persistentFiles;
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.git
        pkgs.jq
      ];
      text = ''
        : "''${WRAPPER_TEST_AGENT_TRACE:?WRAPPER_TEST_AGENT_TRACE must name a trace file}"
        printf '%s\n' "$@" > "$WRAPPER_TEST_AGENT_TRACE"

        auth_path="$HOME/${authRelative}"
        if [[ -n "''${WRAPPER_TEST_AUTH_EXPECT:-}" ]]; then
          test "$(jq -r .token "$auth_path")" = "$WRAPPER_TEST_AUTH_EXPECT"
        fi
        if [[ -n "''${WRAPPER_TEST_AUTH_REPLACEMENT:-}" ]]; then
          mkdir -p "$(dirname "$auth_path")"
          printf '{"token":"%s"}\n' "$WRAPPER_TEST_AUTH_REPLACEMENT" > "$auth_path"
        fi
        if [[ -n "''${WRAPPER_TEST_AUTH_DELETE:-}" ]]; then
          rm -f -- "$auth_path"
        fi
        if [[ -n "''${WRAPPER_TEST_STDIN_EXPECT:-}" ]]; then
          IFS= read -r stdin_value
          test "$stdin_value" = "$WRAPPER_TEST_STDIN_EXPECT"
        fi
        if [[ -n "''${WRAPPER_TEST_HOLD_READY:-}" ]]; then
          printf '%s\n' ready > "$WRAPPER_TEST_HOLD_READY"
          for _ in $(seq 1 1000); do
            [[ -e "$WRAPPER_TEST_HOLD_RELEASE" ]] && break
            sleep 0.01
          done
          test -e "$WRAPPER_TEST_HOLD_RELEASE"
        fi

        if [[ -n "''${WRAPPER_TEST_MUTATE_GIT:-}" ]]; then
          git_directory="$(git rev-parse --path-format=absolute --git-dir)"
          common_directory="$(git rev-parse --path-format=absolute --git-common-dir)"
          git config --file "$common_directory/config" test.value malicious
          mkdir -p "$common_directory/hooks" "$common_directory/modules/example/hooks"
          printf '%s\n' malicious > "$common_directory/hooks/pre-push"
          printf '%s\n' malicious > "$common_directory/modules/example/hooks/pre-push"
          printf '%s\n' malicious > "$git_directory/config.worktree"
          rm -rf "$common_directory/info"
          ln -s "$WRAPPER_TEST_VICTIM" "$common_directory/info"
        fi

        if [[ -n "''${WRAPPER_TEST_SWITCH_BRANCH:-}" ]]; then
          git switch -qc session-branch
          printf '%s\n' switched >> tracked
          git add tracked
          git commit -qm switched
        fi

        if [[ -n "''${WRAPPER_TEST_CHANGE_SYMREF:-}" ]]; then
          git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/other
        fi

        if [[ -n "''${WRAPPER_TEST_DESCENDANT_TARGET:-}" ]]; then
          (
            (
              descendant_git="$(
                dirname "$(dirname "$WRAPPER_TEST_DESCENDANT_TARGET")"
              )"
              for _ in $(seq 1 1000); do
                if [[ -d "$descendant_git" ]]; then
                  printf '%s\n' escaped > "$WRAPPER_TEST_DESCENDANT_TARGET"
                  exit
                fi
                sleep 0.01
              done
            ) </dev/null >/dev/null 2>&1 &
          ) &
        fi

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
      : "''${WRAPPER_TEST_NONO_TRACE:?WRAPPER_TEST_NONO_TRACE must name a trace file}"
      : "''${WRAPPER_TEST_CONFIGURED_HOME:?WRAPPER_TEST_CONFIGURED_HOME must name the test home}"
      if [[ -n "''${BASH_ENV:-}" || -n "''${LD_PRELOAD:-}" \
        || -n "''${NONO_ALLOW:-}" || -n "''${NONO_PROFILE:-}" ]]; then
        echo "ambient loader, Git, or Nono variable reached Nono" >&2
        exit 1
      fi
      if [[ "''${DOTFILES_AGENT_HOME:-}" != "$WRAPPER_TEST_CONFIGURED_HOME"/.cache/nono/session.*/home \
        || "''${HOME:-}" != "$DOTFILES_AGENT_HOME" \
        || "''${DOTFILES_HOST_HOME:-}" != "$WRAPPER_TEST_CONFIGURED_HOME" \
        || "''${DOTFILES_WORKTREE_ROOT:-}" != "$(${pkgs.git}/bin/git rev-parse --show-toplevel)" \
        || "''${GIT_DIR:-}" != "$DOTFILES_AGENT_HOME/.run/git" \
        || "''${GIT_WORK_TREE:-}" != "$DOTFILES_WORKTREE_ROOT" \
        || "''${XDG_STATE_HOME:-}" != "$WRAPPER_TEST_CONFIGURED_HOME"/.nono-s/* \
        || "''${TMPDIR:-}" != "$WRAPPER_TEST_CONFIGURED_HOME"/.cache/nono/session.*/tmp \
        || -n "''${TMP:-}" || -n "''${TEMP:-}" ]]; then
        echo "Nono did not receive isolated session paths" >&2
        exit 1
      fi
      if [[ "''${XDG_CONFIG_HOME:-}" != "$DOTFILES_AGENT_HOME/.config" ]]; then
        echo "Nono config is not session-local: ''${XDG_CONFIG_HOME:-<unset>}" >&2
        exit 1
      fi
      if [[ ! -L "$DOTFILES_AGENT_HOME/.agents" \
        || ! -f "$DOTFILES_AGENT_HOME/.config/git/config" \
        || -L "$DOTFILES_AGENT_HOME/.config/git/config" \
        || ! -d "$DOTFILES_AGENT_HOME/.gstack" ]]; then
        echo "shared session state was not staged" >&2
        exit 1
      fi

      arguments=("$@")
      command_index=-1
      profile=
      for ((index = 0; index < ''${#arguments[@]}; index++)); do
        if [[ "''${arguments[$index]}" == "--profile" ]]; then
          profile="''${arguments[$((index + 1))]}"
        elif [[ "''${arguments[$index]}" == "--" ]]; then
          command_index=$((index + 1))
          break
        fi
      done
      [[ "$command_index" -ge 0 ]]

      case "$profile" in
        *dotfiles-claude.json)
          test -d "$DOTFILES_AGENT_HOME/.cache/claude"
          test -d "$DOTFILES_AGENT_HOME/.cache/claude-cli-nodejs"
          test -d "$DOTFILES_AGENT_HOME/.local/state/claude/locks"
          test -f "$DOTFILES_AGENT_HOME/.claude.json"
          ;;
        *dotfiles-codex.json)
          test -d "$DOTFILES_AGENT_HOME/.codex"
          ;;
        *dotfiles-opencode.json)
          test -d "$DOTFILES_AGENT_HOME/.opencode"
          test -d "$DOTFILES_AGENT_HOME/.config/opencode"
          test -d "$DOTFILES_AGENT_HOME/.cache/opencode"
          test -d "$DOTFILES_AGENT_HOME/.local/share/opencode"
          test -d "$DOTFILES_AGENT_HOME/.local/share/opentui"
          test -d "$DOTFILES_AGENT_HOME/.local/state/opencode"
          ;;
        *dotfiles-pi.json)
          test -d "$DOTFILES_AGENT_HOME/.pi"
          ;;
        *)
          exit 1
          ;;
      esac

      printf '%s\n' "$@" > "$WRAPPER_TEST_NONO_TRACE"
      "''${arguments[@]:$command_index}"
    '';
  };
  fakeHomeGit = pkgs.writeShellApplication {
    name = "git";
    text = ''
      printf '%s\n' "$WRAPPER_TEST_CONFIGURED_HOME"
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
      pkgs.findutils
      pkgs.gnugrep
      pkgs.jq
    ];
  }
  ''
    set -euo pipefail

    test_home="$TMPDIR/nono-wrapper-test-home"
    export HOME="$test_home"
    export WRAPPER_TEST_CONFIGURED_HOME="$test_home"
    materialize_wrappers() {
      local source="$1"
      local target="$2"
      local wrapper
      mkdir -p "$target/bin"
      for wrapper in "$source"/bin/*; do
        cp -L "$wrapper" "$target/bin/"
        chmod u+w "$target/bin/$(basename "$wrapper")"
        if grep -Fq ${pkgs.lib.escapeShellArg configuredHome} \
          "$target/bin/$(basename "$wrapper")"; then
          substituteInPlace "$target/bin/$(basename "$wrapper")" \
            --replace-fail ${pkgs.lib.escapeShellArg configuredHome} "$test_home"
        fi
      done
    }
    materialize_wrappers ${wrappers} "$TMPDIR/wrappers"
    materialize_wrappers ${wrappersWithMissingProfile} "$TMPDIR/wrappers-missing-profile"
    materialize_wrappers ${wrappersWithMissingPi} "$TMPDIR/wrappers-missing-pi"
    materialize_wrappers ${wrappersWithHomeWorktree} "$TMPDIR/wrappers-home-worktree"
    wrappers_dir="$TMPDIR/wrappers"
    mkdir -p \
      "$HOME/.agents" \
      "$HOME/.claude/skills" \
      "$HOME/.codex/plugins" \
      "$HOME/.codex/rules" \
      "$HOME/.codex/skills" \
      "$HOME/.config/git" \
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
    cat > "$HOME/.config/git/config" <<'EOF'
    [user]
      name = Wrapper Test
      email = wrapper@example.com
    EOF

    ${pkgs.lib.concatMapStringsSep "\n" (
      name:
      let
        authRelative = builtins.head agentRegistry.${name}.persistentFiles;
      in
      ''
        mkdir -p "$HOME/$(${pkgs.coreutils}/bin/dirname ${pkgs.lib.escapeShellArg authRelative})"
        printf '%s\n' ${pkgs.lib.escapeShellArg ''{"token":"legacy-${name}"}''} \
          > "$HOME/${authRelative}"
      ''
    ) agentNames}

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
    printf '%s\n' 'touch "$WRAPPER_TEST_BASH_ENV_TRACE"' > "$TMPDIR/bash-env"
    malicious_path="$TMPDIR/malicious-path"
    mkdir -p "$malicious_path"
    for command_name in env mkdir mktemp; do
      printf '%s\n' '#!/bin/sh' 'touch "$WRAPPER_TEST_PATH_TRACE"' > "$malicious_path/$command_name"
      chmod +x "$malicious_path/$command_name"
    done

    assert_normal_wrapper() {
      local agent="$1"
      local real_executable="$2"
      local auth_relative="$3"
      local original_path="$PATH"

      export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/$agent.agent.trace"
      export WRAPPER_TEST_NONO_TRACE="$TMPDIR/$agent.nono.trace"
      export WRAPPER_TEST_BASH_ENV_TRACE="$TMPDIR/$agent.bash-env.trace"
      export WRAPPER_TEST_PATH_TRACE="$TMPDIR/$agent.path.trace"
      export WRAPPER_TEST_AUTH_EXPECT="legacy-$agent"
      export WRAPPER_TEST_AUTH_REPLACEMENT="refreshed-$agent"
      export BASH_ENV="$TMPDIR/bash-env"
      export PATH="$malicious_path"
      unset WRAPPER_TEST_EXIT_CODE
      "$wrappers_dir/bin/$agent" "argument with spaces" -- literal
      export PATH="$original_path"
      test ! -e "$WRAPPER_TEST_BASH_ENV_TRACE"
      test ! -e "$WRAPPER_TEST_PATH_TRACE"
      unset BASH_ENV WRAPPER_TEST_BASH_ENV_TRACE WRAPPER_TEST_PATH_TRACE
      unset WRAPPER_TEST_AUTH_EXPECT WRAPPER_TEST_AUTH_REPLACEMENT

      expected=("$real_executable")
      if [[ "$agent" == codex ]]; then
        expected+=(
          --sandbox
          danger-full-access
          --ask-for-approval
          on-request
        )
      fi
      expected+=("argument with spaces" -- literal)
      printf '%s\n' "''${expected[@]:1}" > "$TMPDIR/$agent.expected"
      ${pkgs.diffutils}/bin/diff -u "$TMPDIR/$agent.expected" "$WRAPPER_TEST_AGENT_TRACE"
      test "$(${pkgs.jq}/bin/jq -r .token \
        "$HOME/.local/state/nono-agent-auth/$agent/$auth_relative")" = "refreshed-$agent"
      test "$(${pkgs.jq}/bin/jq -r .token "$HOME/$auth_relative")" = "refreshed-$agent"
      test -s "$HOME/.local/state/nono-agent-auth/$agent/.synchronized-fingerprint"
      ${pkgs.gnugrep}/bin/grep -Fx -- "--read" "$WRAPPER_TEST_NONO_TRACE"
      ${pkgs.gnugrep}/bin/grep -Fx -- "--allow" "$WRAPPER_TEST_NONO_TRACE"
      test -z "$(${pkgs.findutils}/bin/find "$HOME/.cache/nono" \
        -mindepth 1 -maxdepth 1 -name 'session.*' -print -quit)"
    }

    ${pkgs.lib.concatMapStringsSep "\n" (
      name:
      "assert_normal_wrapper ${name} ${agentExecutables.${name}} "
      + pkgs.lib.escapeShellArg (builtins.head agentRegistry.${name}.persistentFiles)
    ) agentNames}
    unset GIT_DIR NONO_ALLOW NONO_PROFILE

    export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/stdin.agent.trace"
    export WRAPPER_TEST_NONO_TRACE="$TMPDIR/stdin.nono.trace"
    export WRAPPER_TEST_STDIN_EXPECT=wrapper-stdin
    printf '%s\n' wrapper-stdin | "$wrappers_dir/bin/codex"
    unset WRAPPER_TEST_STDIN_EXPECT

    ${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
      export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/preload.agent.trace"
      export WRAPPER_TEST_NONO_TRACE="$TMPDIR/preload.nono.trace"
      export WRAPPER_TEST_PRELOAD_TRACE="$TMPDIR/preload.loaded"
      export LD_PRELOAD=${preloadLibrary}/lib/preload.so
      "$wrappers_dir/bin/claude"
      test ! -e "$WRAPPER_TEST_PRELOAD_TRACE"
      unset LD_PRELOAD WRAPPER_TEST_PRELOAD_TRACE
    ''}

    ${pkgs.git}/bin/git -C "$repo" config test.value trusted
    mkdir -p "$repo/.git/hooks" "$repo/.git/info" "$repo/.git/modules/example/hooks"
    printf '%s\n' trusted > "$repo/.git/hooks/pre-push"
    printf '%s\n' trusted > "$repo/.git/info/attributes"
    printf '%s\n' trusted > "$repo/.git/modules/example/hooks/pre-push"
    mkdir -p "$HOME/victim"
    printf '%s\n' victim > "$HOME/victim/attributes"
    export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/git-isolation.agent.trace"
    export WRAPPER_TEST_NONO_TRACE="$TMPDIR/git-isolation.nono.trace"
    export WRAPPER_TEST_MUTATE_GIT=1
    export WRAPPER_TEST_VICTIM="$HOME/victim"
    "$wrappers_dir/bin/claude"
    unset WRAPPER_TEST_MUTATE_GIT WRAPPER_TEST_VICTIM
    ${pkgs.gnugrep}/bin/grep -F "value = trusted" "$repo/.git/config"
    test "$(<"$repo/.git/hooks/pre-push")" = trusted
    test "$(<"$repo/.git/info/attributes")" = trusted
    test "$(<"$repo/.git/modules/example/hooks/pre-push")" = trusted
    test "$(<"$HOME/victim/attributes")" = victim
    test ! -e "$repo/.git/config.worktree"

    export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/descendant.agent.trace"
    export WRAPPER_TEST_NONO_TRACE="$TMPDIR/descendant.nono.trace"
    export WRAPPER_TEST_DESCENDANT_TARGET="$repo/.git/hooks/descendant"
    "$wrappers_dir/bin/claude"
    unset WRAPPER_TEST_DESCENDANT_TARGET
    sleep 0.2
    test ! -e "$repo/.git/hooks/descendant"

    ${pkgs.git}/bin/git -C "$repo" update-ref refs/remotes/origin/main HEAD
    ${pkgs.git}/bin/git -C "$repo" update-ref refs/remotes/origin/other HEAD
    ${pkgs.git}/bin/git -C "$repo" symbolic-ref \
      refs/remotes/origin/HEAD refs/remotes/origin/main
    main_oid="$(${pkgs.git}/bin/git -C "$repo" rev-parse refs/remotes/origin/main)"
    export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/symref.agent.trace"
    export WRAPPER_TEST_NONO_TRACE="$TMPDIR/symref.nono.trace"
    export WRAPPER_TEST_CHANGE_SYMREF=1
    "$wrappers_dir/bin/claude"
    unset WRAPPER_TEST_CHANGE_SYMREF
    test "$(${pkgs.git}/bin/git -C "$repo" symbolic-ref refs/remotes/origin/HEAD)" = \
      refs/remotes/origin/other
    test "$(${pkgs.git}/bin/git -C "$repo" rev-parse refs/remotes/origin/main)" = "$main_oid"

    export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/head-transition.agent.trace"
    export WRAPPER_TEST_NONO_TRACE="$TMPDIR/head-transition.nono.trace"
    export WRAPPER_TEST_SWITCH_BRANCH=1
    "$wrappers_dir/bin/claude"
    unset WRAPPER_TEST_SWITCH_BRANCH
    test "$(${pkgs.git}/bin/git -C "$repo" symbolic-ref HEAD)" = refs/heads/session-branch
    test "$(${pkgs.git}/bin/git -C "$repo" log -1 --format=%s)" = switched

    printf '%s\n' '{"token":"unsafe-codex"}' > "$HOME/.codex/auth.json"
    export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/auth-legacy.agent.trace"
    export WRAPPER_TEST_NONO_TRACE="$TMPDIR/auth-legacy.nono.trace"
    export WRAPPER_TEST_AUTH_EXPECT=unsafe-codex
    "$wrappers_dir/bin/codex"
    unset WRAPPER_TEST_AUTH_EXPECT
    test "$(${pkgs.jq}/bin/jq -r .token \
      "$HOME/.local/state/nono-agent-auth/codex/.codex/auth.json")" = unsafe-codex

    printf '%s\n' '{"token":"persistent-codex"}' \
      > "$HOME/.local/state/nono-agent-auth/codex/.codex/auth.json"
    export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/auth-persistent.agent.trace"
    export WRAPPER_TEST_NONO_TRACE="$TMPDIR/auth-persistent.nono.trace"
    export WRAPPER_TEST_AUTH_EXPECT=persistent-codex
    "$wrappers_dir/bin/codex"
    unset WRAPPER_TEST_AUTH_EXPECT
    test "$(${pkgs.jq}/bin/jq -r .token "$HOME/.codex/auth.json")" = persistent-codex

    export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/auth-logout.agent.trace"
    export WRAPPER_TEST_AUTH_DELETE=1
    "$wrappers_dir/bin/codex-unsafe"
    unset WRAPPER_TEST_AUTH_DELETE
    test ! -e "$HOME/.codex/auth.json"
    test ! -e "$HOME/.local/state/nono-agent-auth/codex/.codex/auth.json"
    test "$(<"$HOME/.local/state/nono-agent-auth/codex/.synchronized-fingerprint")" = absent

    rm -rf "$HOME/.pi/agent"
    export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/auth-missing-parent.agent.trace"
    export WRAPPER_TEST_NONO_TRACE="$TMPDIR/auth-missing-parent.nono.trace"
    export WRAPPER_TEST_AUTH_EXPECT=refreshed-pi
    "$wrappers_dir/bin/pi"
    unset WRAPPER_TEST_AUTH_EXPECT
    test "$(${pkgs.jq}/bin/jq -r .token "$HOME/.pi/agent/auth.json")" = refreshed-pi

    unsupported_repo="$TMPDIR/unsupported"
    ${pkgs.git}/bin/git init -q "$unsupported_repo"
    ${pkgs.git}/bin/git -C "$unsupported_repo" config user.name test
    ${pkgs.git}/bin/git -C "$unsupported_repo" config user.email test@example.com
    printf '%s\n' initial > "$unsupported_repo/tracked"
    ${pkgs.git}/bin/git -C "$unsupported_repo" add tracked
    ${pkgs.git}/bin/git -C "$unsupported_repo" commit -qm initial
    printf '%s\n' blocked > "$unsupported_repo/.git/MERGE_HEAD"
    cd "$unsupported_repo"
    rm -f "$WRAPPER_TEST_NONO_TRACE"
    set +e
    "$wrappers_dir/bin/codex" \
      > "$TMPDIR/unsupported-state.stdout" 2> "$TMPDIR/unsupported-state.stderr"
    unsupported_status=$?
    set -e
    test "$unsupported_status" -eq 78
    test ! -e "$WRAPPER_TEST_NONO_TRACE"
    ${pkgs.gnugrep}/bin/grep -F "unsupported Git state" \
      "$TMPDIR/unsupported-state.stderr"

    alternate_source="$TMPDIR/alternate-source"
    alternate_repo="$TMPDIR/alternate-repo"
    ${pkgs.git}/bin/git init -q "$alternate_source"
    ${pkgs.git}/bin/git -C "$alternate_source" config user.name test
    ${pkgs.git}/bin/git -C "$alternate_source" config user.email test@example.com
    printf '%s\n' alternate > "$alternate_source/tracked"
    ${pkgs.git}/bin/git -C "$alternate_source" add tracked
    ${pkgs.git}/bin/git -C "$alternate_source" commit -qm alternate
    ${pkgs.git}/bin/git clone -q --shared "$alternate_source" "$alternate_repo"
    cd "$alternate_repo"
    rm -f "$WRAPPER_TEST_NONO_TRACE"
    set +e
    "$wrappers_dir/bin/codex" \
      > "$TMPDIR/alternates.stdout" 2> "$TMPDIR/alternates.stderr"
    alternates_status=$?
    set -e
    test "$alternates_status" -eq 78
    test ! -e "$WRAPPER_TEST_NONO_TRACE"
    ${pkgs.gnugrep}/bin/grep -F "object-alternates" "$TMPDIR/alternates.stderr"

    outer_repo="$TMPDIR/outer"
    nested_repo="$outer_repo/nested"
    ${pkgs.git}/bin/git init -q "$outer_repo"
    ${pkgs.git}/bin/git -C "$outer_repo" config user.name test
    ${pkgs.git}/bin/git -C "$outer_repo" config user.email test@example.com
    printf '%s\n' outer > "$outer_repo/tracked"
    ${pkgs.git}/bin/git -C "$outer_repo" add tracked
    ${pkgs.git}/bin/git -C "$outer_repo" commit -qm outer
    ${pkgs.git}/bin/git init -q "$nested_repo"
    ${pkgs.git}/bin/git -C "$nested_repo" config user.name test
    ${pkgs.git}/bin/git -C "$nested_repo" config user.email test@example.com
    printf '%s\n' nested > "$nested_repo/tracked"
    ${pkgs.git}/bin/git -C "$nested_repo" add tracked
    ${pkgs.git}/bin/git -C "$nested_repo" commit -qm nested
    nested_ready="$TMPDIR/nested-ready"
    nested_release="$TMPDIR/nested-release"
    (
      cd "$nested_repo"
      export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/nested.agent.trace"
      export WRAPPER_TEST_NONO_TRACE="$TMPDIR/nested.nono.trace"
      export WRAPPER_TEST_HOLD_READY="$nested_ready"
      export WRAPPER_TEST_HOLD_RELEASE="$nested_release"
      "$wrappers_dir/bin/codex"
    ) &
    nested_pid=$!
    for _ in $(seq 1 1000); do
      [[ -e "$nested_ready" ]] && break
      sleep 0.01
    done
    test -e "$nested_ready"
    test -z "$(${pkgs.findutils}/bin/find "$outer_repo" -maxdepth 2 \
      -name '.nono-git-metadata.*' -print -quit)"
    touch "$nested_release"
    wait "$nested_pid"

    linked="$TMPDIR/linked"
    linked_two="$TMPDIR/linked-two"
    ${pkgs.git}/bin/git -C "$repo" worktree add -qb linked "$linked"
    ${pkgs.git}/bin/git -C "$repo" worktree add -qb linked-two "$linked_two"
    linked_git_directory="$(${pkgs.git}/bin/git -C "$linked" \
      rev-parse --path-format=absolute --git-dir)"
    common_directory="$(${pkgs.git}/bin/git -C "$linked" \
      rev-parse --path-format=absolute --git-common-dir)"
    printf '%s\n' trusted > "$linked_git_directory/config.worktree"
    cd "$linked"
    export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/linked.agent.trace"
    export WRAPPER_TEST_NONO_TRACE="$TMPDIR/linked.nono.trace"
    "$wrappers_dir/bin/codex" linked
    test "$(<"$linked/.git")" = "gitdir: $linked_git_directory"
    test "$(<"$linked_git_directory/config.worktree")" = trusted
    ${pkgs.gnugrep}/bin/grep -F "value = trusted" "$common_directory/config"
    test "$(<"$common_directory/hooks/pre-push")" = trusted

    linked_ready="$TMPDIR/linked-ready"
    linked_release="$TMPDIR/linked-release"
    linked_two_ready="$TMPDIR/linked-two-ready"
    linked_two_release="$TMPDIR/linked-two-release"
    (
      cd "$linked"
      export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/linked-hold.agent.trace"
      export WRAPPER_TEST_NONO_TRACE="$TMPDIR/linked-hold.nono.trace"
      export WRAPPER_TEST_HOLD_READY="$linked_ready"
      export WRAPPER_TEST_HOLD_RELEASE="$linked_release"
      "$wrappers_dir/bin/codex"
    ) &
    linked_pid=$!
    for _ in $(seq 1 1000); do
      [[ -e "$linked_ready" ]] && break
      sleep 0.01
    done
    test -e "$linked_ready"
    (
      cd "$linked_two"
      export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/linked-two-hold.agent.trace"
      export WRAPPER_TEST_NONO_TRACE="$TMPDIR/linked-two-hold.nono.trace"
      export WRAPPER_TEST_HOLD_READY="$linked_two_ready"
      export WRAPPER_TEST_HOLD_RELEASE="$linked_two_release"
      "$wrappers_dir/bin/codex"
    ) &
    linked_two_pid=$!
    for _ in $(seq 1 1000); do
      [[ -e "$linked_two_ready" ]] && break
      sleep 0.01
    done
    test -e "$linked_two_ready"
    touch "$linked_release" "$linked_two_release"
    wait "$linked_pid"
    wait "$linked_two_pid"

    cd "$repo"
    export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/main-linked.agent.trace"
    export WRAPPER_TEST_NONO_TRACE="$TMPDIR/main-linked.nono.trace"
    rm -f "$WRAPPER_TEST_AGENT_TRACE" "$WRAPPER_TEST_NONO_TRACE"
    set +e
    "$wrappers_dir/bin/codex" \
      > "$TMPDIR/main-linked.stdout" 2> "$TMPDIR/main-linked.stderr"
    main_linked_status=$?
    set -e
    test "$main_linked_status" -eq 78
    test ! -e "$WRAPPER_TEST_NONO_TRACE"
    ${pkgs.git}/bin/git -C "$linked" status --short >/dev/null
    ${pkgs.gnugrep}/bin/grep -F "main worktree with linked worktrees" \
      "$TMPDIR/main-linked.stderr"

    export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/missing-profile.agent.trace"
    export WRAPPER_TEST_NONO_TRACE="$TMPDIR/missing-profile.nono.trace"
    rm -f "$WRAPPER_TEST_AGENT_TRACE" "$WRAPPER_TEST_NONO_TRACE"
    if "$TMPDIR/wrappers-missing-profile/bin/opencode" \
      > "$TMPDIR/missing-profile.stdout" 2> "$TMPDIR/missing-profile.stderr"; then
      echo "opencode unexpectedly started without its local profile" >&2
      exit 1
    fi
    test ! -e "$WRAPPER_TEST_NONO_TRACE"
    ${pkgs.gnugrep}/bin/grep -F "missing Nono profile" "$TMPDIR/missing-profile.stderr"

    outside="$TMPDIR/outside"
    mkdir -p "$outside"
    cd "$outside"
    rm -f "$WRAPPER_TEST_AGENT_TRACE" "$WRAPPER_TEST_NONO_TRACE"
    if "$wrappers_dir/bin/claude" \
      > "$TMPDIR/outside-worktree.stdout" 2> "$TMPDIR/outside-worktree.stderr"; then
      echo "claude unexpectedly started outside a worktree" >&2
      exit 1
    fi
    test ! -e "$WRAPPER_TEST_NONO_TRACE"
    ${pkgs.gnugrep}/bin/grep -F "must be launched inside a Git worktree" \
      "$TMPDIR/outside-worktree.stderr"

    cd "$repo/subdir"
    rm -f "$WRAPPER_TEST_AGENT_TRACE" "$WRAPPER_TEST_NONO_TRACE"
    set +e
    "$TMPDIR/wrappers-home-worktree/bin/codex" \
      > "$TMPDIR/home-worktree.stdout" 2> "$TMPDIR/home-worktree.stderr"
    home_status=$?
    set -e
    test "$home_status" -eq 78
    test ! -e "$WRAPPER_TEST_NONO_TRACE"
    ${pkgs.gnugrep}/bin/grep -F "worktree that contains HOME" \
      "$TMPDIR/home-worktree.stderr"

    export HOME="$TMPDIR/unexpected-home"
    mkdir -p "$HOME"
    rm -f "$WRAPPER_TEST_AGENT_TRACE" "$WRAPPER_TEST_NONO_TRACE"
    set +e
    "$wrappers_dir/bin/codex" \
      > "$TMPDIR/unexpected-home.stdout" 2> "$TMPDIR/unexpected-home.stderr"
    unexpected_home_status=$?
    set -e
    test "$unexpected_home_status" -eq 78
    test ! -e "$WRAPPER_TEST_NONO_TRACE"
    ${pkgs.gnugrep}/bin/grep -F "refusing unexpected HOME" \
      "$TMPDIR/unexpected-home.stderr"

    export HOME="$test_home"
    export WRAPPER_TEST_AGENT_TRACE="$TMPDIR/unsafe.agent.trace"
    export WRAPPER_TEST_EXIT_CODE=23
    set +e
    "$wrappers_dir/bin/pi-unsafe" "unsafe argument" 2> "$TMPDIR/unsafe.stderr"
    unsafe_status=$?
    set -e
    test "$unsafe_status" -eq 23
    printf '%s\n' "unsafe argument" > "$TMPDIR/unsafe.expected"
    ${pkgs.diffutils}/bin/diff -u "$TMPDIR/unsafe.expected" "$WRAPPER_TEST_AGENT_TRACE"
    ${pkgs.gnugrep}/bin/grep -F "UNSANDBOXED" "$TMPDIR/unsafe.stderr"

    unset WRAPPER_TEST_EXIT_CODE
    set +e
    "$TMPDIR/wrappers-missing-pi/bin/pi" \
      > "$TMPDIR/missing-executable.stdout" 2> "$TMPDIR/missing-executable.stderr"
    missing_status=$?
    set -e
    test "$missing_status" -eq 127
    ${pkgs.gnugrep}/bin/grep -F "real pi executable is unavailable" \
      "$TMPDIR/missing-executable.stderr"
    test -z "$(${pkgs.findutils}/bin/find "$TMPDIR" \
      -mindepth 1 -maxdepth 1 -name '.nono-git-metadata.*' -print -quit)"
    if [[ -d "$HOME/.nono-s" ]]; then
      test -z "$(${pkgs.findutils}/bin/find "$HOME/.nono-s" \
        -mindepth 1 -maxdepth 1 -type d -print -quit)"
    fi

    touch "$out"
  ''
