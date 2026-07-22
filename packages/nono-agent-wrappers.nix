{
  agentExecutables,
  lib,
  nonoPackage,
  symlinkJoin,
  writeShellApplication,
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
    writeShellApplication {
      inherit name;
      text = ''
        profile_path="$HOME/.config/nono/profiles/${profile}.json"
        real_executable=${lib.escapeShellArg realExecutable}

        if [[ ! -r "$profile_path" ]]; then
          echo "error: missing Nono profile: $profile_path" >&2
          exit 78
        fi
        if [[ ! -x "$real_executable" ]]; then
          echo "error: real ${name} executable is unavailable: $real_executable" >&2
          exit 127
        fi

        exec ${lib.escapeShellArg (lib.getExe nonoPackage)} \
          run \
          --profile ${lib.escapeShellArg profile} \
          --workdir "$PWD" \
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
