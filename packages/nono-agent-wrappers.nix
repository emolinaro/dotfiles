{
  bash,
  agentExecutables,
  coreutils,
  git,
  homeDirectory,
  lib,
  nonoPackage,
  profiles,
  runCommand,
  symlinkJoin,
  writeShellApplication,
  writeTextFile,
}:

let
  agentNames = [
    "claude"
    "codex"
    "opencode"
    "pi"
  ];
  missingAgents = builtins.filter (name: !(builtins.hasAttr name agentExecutables)) agentNames;
  relativeExecutables = builtins.filter (
    name: !(lib.hasPrefix "/" agentExecutables.${name})
  ) agentNames;
  nonoConfig = runCommand "nono-agent-config" { } ''
    mkdir -p "$out/nono"
    ln -s ${profiles} "$out/nono/profiles"
  '';

  mkNormalWrapper =
    name:
    let
      profile = "dotfiles-${name}";
      realExecutable = agentExecutables.${name};
      clientArguments =
        if name == "codex" then
          [
            "--sandbox"
            "danger-full-access"
            "--ask-for-approval"
            "on-request"
          ]
        else
          [ ];
    in
    writeTextFile {
      inherit name;
      destination = "/bin/${name}";
      executable = true;
      text = ''
        #!${lib.getExe bash} -p
        set -euo pipefail

        profile_path=${lib.escapeShellArg "${profiles}/${profile}.json"}
        real_executable=${lib.escapeShellArg realExecutable}
        configured_home=${lib.escapeShellArg homeDirectory}

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

        while IFS= read -r environment_entry; do
          variable="''${environment_entry%%=*}"
          if [[ "$variable" == BASH_ENV || "$variable" == GIT_* || "$variable" == NONO_* || "$variable" == TMPDIR || "$variable" == TMP || "$variable" == TEMP ]]; then
            unset "$variable"
          fi
        done < <(${lib.getExe' coreutils "env"})
        session_temp_root="$configured_home/.cache/nono"
        mkdir -p "$session_temp_root"
        export TMPDIR="$(mktemp -d "$session_temp_root/session.XXXXXXXXXX")"
        export NONO_NO_PACK_UPDATE_HINTS=1
        export NONO_NO_UPDATE_CHECK=1
        export XDG_CONFIG_HOME=${lib.escapeShellArg nonoConfig}

        current_directory="$(pwd -P)"
        if ! worktree_root="$(${lib.getExe git} -C "$current_directory" rev-parse --show-toplevel 2>/dev/null)" \
          || [[ -z "$worktree_root" ]]; then
          echo "error: ${name} must be launched inside a Git worktree" >&2
          exit 78
        fi
        worktree_root="$(cd "$worktree_root" && pwd -P)"
        if ! home_directory="$(cd "$configured_home" && pwd -P)"; then
          echo "error: configured home is unavailable: $configured_home" >&2
          exit 78
        fi
        if [[ "$worktree_root" == "/" \
          || "$home_directory" == "$worktree_root" \
          || "$home_directory" == "$worktree_root/"* ]]; then
          echo "error: refusing to sandbox a Git worktree that contains HOME: $worktree_root" >&2
          exit 78
        fi

        exec ${lib.escapeShellArg (lib.getExe nonoPackage)} \
          run \
          --profile "$profile_path" \
          --allow "$worktree_root" \
          --workdir "$current_directory" \
          -- \
          ${lib.escapeShellArgs ([ realExecutable ] ++ clientArguments)} \
          "$@"
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
  relativeExecutables == [ ]
) "agent executable paths must be absolute: ${lib.concatStringsSep ", " relativeExecutables}";
symlinkJoin {
  name = "nono-agent-wrappers";
  paths = builtins.concatMap (name: [
    (mkNormalWrapper name)
    (mkUnsafeWrapper name)
  ]) agentNames;
}
