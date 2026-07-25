{
  lib,
  runCommand,
  writeShellScript,
}:

{
  gnhfExecutable,
  variants,
}:

let
  names = map (variant: variant.name) variants;
  invalidVariants = builtins.filter (
    variant:
    builtins.match "^[a-z0-9][a-z0-9-]*$" variant.name == null
    || builtins.match "^[a-z0-9][a-z0-9-]*$" variant.agent == null
    || !(lib.hasPrefix "/" (toString variant.executable))
  ) variants;
  duplicateNames = builtins.length names != builtins.length (lib.unique names);
  mkLauncher =
    variant:
    let
      launcherName = "gnhf-${variant.name}";
    launcher = writeShellScript launcherName ''
        set -euo pipefail

        ${lib.optionalString (variant.name == "opencode-nono") ''
          has_required_worktree=0
        ''}

        for argument in "$@"; do
          case "$argument" in
            --)
              break
              ;;
            --worktree | --worktree=*)
              ${lib.optionalString (variant.name == "opencode-nono") ''
                has_required_worktree=1
              ''}
              ;;
            --agent | --agent=* | --agent-path | --agent-path=*)
              echo \
                "error: ${launcherName} controls --agent and --agent-path; remove $argument" \
                >&2
              exit 64
              ;;
          esac
        done

        ${lib.optionalString (variant.name == "opencode-nono") ''
          if [[ "$has_required_worktree" -ne 1 ]]; then
            echo "error: ${launcherName} requires --worktree when routing through opencode-nono" >&2
            echo "error: ${launcherName} avoids shared worktree mutation with OpenCode's long-lived serve process" >&2
            exit 64
          fi
        ''}

        exec ${lib.escapeShellArg (toString gnhfExecutable)} \
          --agent ${lib.escapeShellArg variant.agent} \
          --agent-path ${lib.escapeShellArg (toString variant.executable)} \
          "$@"
      '';
    in
    ''
      ln -s ${lib.escapeShellArg launcher} "$out/bin/${launcherName}"
    '';
in
assert lib.assertMsg (variants != [ ]) "GNHF requires at least one agent launcher variant";
assert lib.assertMsg (!duplicateNames) "GNHF agent launcher names must be unique";
assert lib.assertMsg (
  invalidVariants == [ ]
) "GNHF agent launchers require safe names and absolute executable paths";
runCommand "gnhf-agent-launchers" { } ''
  set -euo pipefail

  mkdir -p "$out/bin"
  ${lib.concatMapStringsSep "\n" mkLauncher variants}
''
