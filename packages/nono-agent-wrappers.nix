{
  agentExecutables,
  agentRegistry,
  bash,
  coreutils,
  git,
  homeDirectory,
  jq,
  lib,
  nonoPackage,
  pkgsStatic,
  profiles,
  runCommand,
  stdenv,
  symlinkJoin,
  writeShellApplication,
  writeTextFile,
}:

let
  agentNames = builtins.attrNames agentRegistry;
  executableNames = builtins.attrNames agentExecutables;
  missingAgents = builtins.filter (name: !(builtins.hasAttr name agentExecutables)) agentNames;
  unexpectedAgents = builtins.filter (name: !(builtins.hasAttr name agentRegistry)) executableNames;
  relativeExecutables = builtins.filter (
    name: !(lib.hasPrefix "/" agentExecutables.${name})
  ) agentNames;
  launcherBashPath = if stdenv.hostPlatform.isLinux then lib.getExe pkgsStatic.bash else "/bin/bash";
  trustedPath =
    lib.makeBinPath [
      bash
      coreutils
      git
      jq
      nonoPackage
    ]
    + ":"
    + lib.concatStringsSep ":" (
      lib.unique (
        (map builtins.dirOf (builtins.attrValues agentExecutables))
        ++ [
          "${homeDirectory}/.nix-profile/bin"
          "/etc/profiles/per-user/${builtins.baseNameOf homeDirectory}/bin"
          "/run/current-system/sw/bin"
          "/nix/var/nix/profiles/default/bin"
          "/opt/homebrew/bin"
          "/usr/local/bin"
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ]
      )
    );
  nonoConfig = runCommand "nono-agent-config" { } ''
    mkdir -p "$out/nono"
    ln -s ${profiles} "$out/nono/profiles"
  '';

  mkNormalWrapper =
    name:
    let
      definition = agentRegistry.${name};
      profile = definition.profile;
      realExecutable = agentExecutables.${name};
      stagePaths = lib.concatMapStrings (
        stagedPath:
        let
          source = "${homeDirectory}/${stagedPath.source}";
        in
        ''
          staged_source=${lib.escapeShellArg source}
          staged_target="$session_home"/${lib.escapeShellArg stagedPath.target}
          if [[ -e "$staged_source" || -L "$staged_source" ]]; then
            ${lib.getExe' coreutils "mkdir"} -p -- "$(${lib.getExe' coreutils "dirname"} "$staged_target")"
            ${lib.getExe' coreutils "ln"} -s -- "$staged_source" "$staged_target"
          fi
        ''
      ) definition.stagedPaths;
      stagePersistentFiles = lib.concatMapStrings (persistentFile: ''
        persistent_source="$persistent_state_root"/${lib.escapeShellArg persistentFile}
        persistent_target="$session_home"/${lib.escapeShellArg persistentFile}
        if [[ -f "$persistent_source" && ! -L "$persistent_source" ]]; then
          ${lib.getExe' coreutils "mkdir"} -p -- \
            "$(${lib.getExe' coreutils "dirname"} "$persistent_target")"
          ${lib.getExe' coreutils "cp"} -- "$persistent_source" "$persistent_target"
          ${lib.getExe' coreutils "chmod"} 0600 -- "$persistent_target"
        fi
      '') definition.persistentFiles;
      stageFilteredJsonPaths = lib.concatMapStrings (filteredPath: ''
        filtered_source="$configured_home"/${lib.escapeShellArg filteredPath.source}
        filtered_target="$session_home"/${lib.escapeShellArg filteredPath.target}
        if [[ -f "$filtered_source" ]]; then
          ${lib.getExe' coreutils "mkdir"} -p -- \
            "$(${lib.getExe' coreutils "dirname"} "$filtered_target")"
          ${lib.getExe jq} ${lib.escapeShellArg filteredPath.filter} \
            "$filtered_source" > "$filtered_target"
        fi
      '') definition.filteredJsonPaths;
      persistFiles = lib.concatMapStrings (persistentFile: ''
        persistent_source="$session_home"/${lib.escapeShellArg persistentFile}
        persistent_target="$persistent_state_root"/${lib.escapeShellArg persistentFile}
        if [[ -f "$persistent_source" && ! -L "$persistent_source" ]]; then
          ${lib.getExe' coreutils "mkdir"} -p -m 0700 -- \
            "$(${lib.getExe' coreutils "dirname"} "$persistent_target")"
          persistent_temporary="$persistent_target.tmp.$$"
          ${lib.getExe' coreutils "cp"} -- "$persistent_source" "$persistent_temporary"
          ${lib.getExe' coreutils "chmod"} 0600 -- "$persistent_temporary"
          ${lib.getExe' coreutils "mv"} -f -- "$persistent_temporary" "$persistent_target"
        elif [[ ! -e "$persistent_source" && ! -L "$persistent_source" ]]; then
          ${lib.getExe' coreutils "rm"} -f -- "$persistent_target"
        fi
      '') definition.persistentFiles;
      sshSocketSetup = lib.optionalString stdenv.hostPlatform.isDarwin ''
        if [[ -z "$inherited_ssh_auth_sock" ]]; then
          inherited_ssh_auth_sock=/nonexistent/nono-ssh-agent.sock
        elif [[ "$inherited_ssh_auth_sock" != /* ]]; then
          echo "error: refusing relative SSH_AUTH_SOCK: $inherited_ssh_auth_sock" >&2
          exit 78
        fi
        export SSH_AUTH_SOCK="$inherited_ssh_auth_sock"
      '';
    in
    writeTextFile {
      inherit name;
      destination = "/bin/${name}";
      executable = true;
      text = ''
        #!${launcherBashPath} -p
        set -euo pipefail

        readonly profile_path=${lib.escapeShellArg "${profiles}/${profile}.json"}
        readonly real_executable=${lib.escapeShellArg realExecutable}
        readonly configured_home=${lib.escapeShellArg homeDirectory}
        inherited_ssh_auth_sock="''${SSH_AUTH_SOCK:-}"
        export PATH=${lib.escapeShellArg trustedPath}

        while IFS= read -r environment_variable; do
          case "$environment_variable" in
            BASH_ENV | ENV | GIT_* | LD_* | DYLD_* | NONO_* | SSH_* | TMPDIR | TMP | TEMP | \
              DOTFILES_AGENT_HOME | DOTFILES_HOST_HOME | XDG_CACHE_HOME | XDG_CONFIG_HOME | \
              XDG_DATA_HOME | XDG_RUNTIME_DIR | XDG_STATE_HOME)
              unset "$environment_variable"
              ;;
          esac
        done < <(compgen -e)

        ${sshSocketSetup}

        if [[ ! -r "$profile_path" ]]; then
          echo "error: missing Nono profile: $profile_path" >&2
          exit 78
        fi
        if [[ ! -x "$real_executable" ]]; then
          echo "error: real ${name} executable is unavailable: $real_executable" >&2
          exit 127
        fi
        if [[ "''${HOME:-}" != "$configured_home" ]]; then
          echo "error: refusing unexpected HOME: ''${HOME:-<unset>}" >&2
          exit 78
        fi

        readonly current_directory="$(pwd -P)"
        if ! worktree_root="$(${lib.getExe git} -C "$current_directory" rev-parse --show-toplevel 2>/dev/null)" \
          || [[ -z "$worktree_root" ]]; then
          echo "error: ${name} must be launched inside a Git worktree" >&2
          exit 78
        fi
        readonly worktree_root="$(cd "$worktree_root" && pwd -P)"
        if ! home_directory="$(cd "$configured_home" && pwd -P)"; then
          echo "error: configured home is unavailable: $configured_home" >&2
          exit 78
        fi
        readonly home_directory
        if [[ "$worktree_root" == "/" \
          || "$home_directory" == "$worktree_root" \
          || "$home_directory" == "$worktree_root/"* ]]; then
          echo "error: refusing to sandbox a Git worktree that contains HOME: $worktree_root" >&2
          exit 78
        fi

        if ! git_directory="$(${lib.getExe git} -C "$current_directory" \
          rev-parse --path-format=absolute --git-dir 2>/dev/null)" \
          || ! common_directory="$(${lib.getExe git} -C "$current_directory" \
            rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
          echo "error: unable to resolve Git metadata for $worktree_root" >&2
          exit 78
        fi
        readonly git_directory="$(cd "$git_directory" && pwd -P)"
        readonly common_directory="$(cd "$common_directory" && pwd -P)"

        readonly session_temp_root="$configured_home/.cache/nono"
        ${lib.getExe' coreutils "mkdir"} -p -m 0700 -- "$session_temp_root"
        readonly session_root="$(${lib.getExe' coreutils "mktemp"} \
          -d "$session_temp_root/session.XXXXXXXXXX")"
        readonly session_home="$session_root/home"
        readonly session_temp="$session_root/tmp"
        readonly git_backup_root="$session_root/git-control"
        readonly persistent_state_root="$configured_home/.local/state/nono-agent-auth/${name}"
        ${lib.getExe' coreutils "mkdir"} -m 0700 -- \
          "$session_home" \
          "$session_temp" \
          "$session_home/.run" \
          "$git_backup_root"

        git_control_targets=()
        git_control_backups=()
        git_control_present=()

        protect_git_control() {
          local target="$1"
          local existing
          for existing in "''${git_control_targets[@]:-}"; do
            [[ "$existing" == "$target" ]] && return
          done
          local index="''${#git_control_targets[@]}"
          local backup="$git_backup_root/$index"
          git_control_targets+=("$target")
          git_control_backups+=("$backup")
          if [[ -e "$target" || -L "$target" ]]; then
            ${lib.getExe' coreutils "cp"} -a -- "$target" "$backup"
            git_control_present+=(1)
          else
            git_control_present+=(0)
          fi
        }

        restore_git_control() {
          local index
          local target
          local backup
          for ((index = ''${#git_control_targets[@]} - 1; index >= 0; index--)); do
            target="''${git_control_targets[$index]}"
            backup="''${git_control_backups[$index]}"
            ${lib.getExe' coreutils "rm"} -rf -- "$target"
            if [[ "''${git_control_present[$index]}" -eq 1 ]]; then
              ${lib.getExe' coreutils "mkdir"} -p -- \
                "$(${lib.getExe' coreutils "dirname"} "$target")"
              ${lib.getExe' coreutils "cp"} -a -- "$backup" "$target"
            fi
          done
        }

        cleanup() {
          local status=$?
          trap - EXIT HUP INT TERM
          set +e
          restore_git_control
          ${persistFiles}
          ${lib.getExe' coreutils "rm"} -rf -- "$session_root"
          exit "$status"
        }
        trap cleanup EXIT HUP INT TERM

        protect_git_control "$common_directory/config"
        protect_git_control "$common_directory/hooks"
        protect_git_control "$common_directory/info/attributes"
        protect_git_control "$git_directory/config.worktree"
        if [[ -f "$worktree_root/.git" || -L "$worktree_root/.git" ]]; then
          protect_git_control "$worktree_root/.git"
        fi
        if hooks_directory="$(${lib.getExe git} -C "$current_directory" \
          rev-parse --path-format=absolute --git-path hooks 2>/dev/null)" \
          && [[ -n "$hooks_directory" ]]; then
          protect_git_control "$hooks_directory"
        fi

        ${stagePaths}
        ${stageFilteredJsonPaths}
        ${stagePersistentFiles}

        export DOTFILES_AGENT_HOME="$session_home"
        export DOTFILES_HOST_HOME="$configured_home"
        export TMPDIR="$session_temp"
        export NONO_NO_PACK_UPDATE_HINTS=1
        export NONO_NO_UPDATE_CHECK=1
        export XDG_CONFIG_HOME=${lib.escapeShellArg nonoConfig}
        export HOME="$session_home"

        nono_arguments=(
          run
          --profile "$profile_path"
          --allow "$worktree_root"
        )
        if [[ "$git_directory" != "$worktree_root" \
          && "$git_directory" != "$worktree_root/"* ]]; then
          nono_arguments+=(--allow "$git_directory")
        fi
        if [[ "$common_directory" != "$git_directory" \
          && "$common_directory" != "$worktree_root" \
          && "$common_directory" != "$worktree_root/"* ]]; then
          nono_arguments+=(--allow "$common_directory")
        fi
        nono_arguments+=(
          --workdir "$current_directory"
          --
          "$real_executable"
          ${lib.escapeShellArgs definition.clientArguments}
          "$@"
        )

        ${lib.escapeShellArg (lib.getExe nonoPackage)} "''${nono_arguments[@]}"
      '';
    };

  mkUnsafeWrapper =
    name:
    let
      realExecutable = agentExecutables.${name};
    in
    writeShellApplication {
      name = "${name}-unsafe";
      text = ''
        real_executable=${lib.escapeShellArg realExecutable}

        if [[ ! -x "$real_executable" ]]; then
          echo "error: real ${name} executable is unavailable: $real_executable" >&2
          exit 127
        fi

        echo "warning: launching ${name} UNSANDBOXED" >&2
        exec "$real_executable" "$@"
      '';
    };
in
assert lib.assertMsg (
  missingAgents == [ ]
) "agentExecutables is missing: ${lib.concatStringsSep ", " missingAgents}";
assert lib.assertMsg (
  unexpectedAgents == [ ]
) "agentExecutables has unexpected entries: ${lib.concatStringsSep ", " unexpectedAgents}";
assert lib.assertMsg (
  relativeExecutables == [ ]
) "agent executable paths must be absolute: ${lib.concatStringsSep ", " relativeExecutables}";
symlinkJoin {
  name = "nono-agent-wrappers";
  paths = builtins.concatMap (name: [
    (mkNormalWrapper name)
    (mkUnsafeWrapper name)
  ]) agentNames;
}
