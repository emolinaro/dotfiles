{
  lib,
  makeWrapper,
  runCommand,
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
      launcherFlags = lib.escapeShellArgs [
        "--agent"
        variant.agent
        "--agent-path"
        (toString variant.executable)
      ];
    in
    ''
      shim="$out/libexec/gnhf-agent-launchers/${variant.name}"
      mkdir -p "$shim"
      ln -s ${lib.escapeShellArg (toString variant.executable)} "$shim/${variant.agent}"
      makeWrapper ${lib.escapeShellArg (toString gnhfExecutable)} "$out/bin/gnhf-${variant.name}" \
        --prefix PATH : "$shim" \
        --add-flags ${lib.escapeShellArg launcherFlags}
    '';
in
assert lib.assertMsg (variants != [ ]) "GNHF requires at least one agent launcher variant";
assert lib.assertMsg (!duplicateNames) "GNHF agent launcher names must be unique";
assert lib.assertMsg (
  invalidVariants == [ ]
) "GNHF agent launchers require safe names and absolute executable paths";
runCommand "gnhf-agent-launchers" { nativeBuildInputs = [ makeWrapper ]; } ''
  set -euo pipefail

  mkdir -p "$out/bin" "$out/libexec/gnhf-agent-launchers"
  ${lib.concatMapStringsSep "\n" mkLauncher variants}
''
