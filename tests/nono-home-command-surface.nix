{
  agentRegistry,
  homePath,
  pkgs,
}:

let
  agentNames = builtins.attrNames agentRegistry;
in
pkgs.runCommand "nono-home-command-surface-test" { } ''
  set -euo pipefail
  for agent in ${pkgs.lib.escapeShellArgs agentNames}; do
    test -x "${homePath}/bin/$agent"
    test -x "${homePath}/bin/$agent-nono"
  done
  touch "$out"
''
