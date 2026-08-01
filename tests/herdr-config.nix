{
  configFile,
  herdrPackage,
  pkgs,
}:

let
  config = builtins.fromTOML (builtins.readFile configFile);
  expectedAgentRows = [
    [
      "state_icon"
      "workspace"
      "tab"
    ]
    [
      "state_text"
      "agent"
    ]
  ];
in
assert pkgs.lib.assertMsg (
  config.ui.sidebar.agents.rows == expectedAgentRows
) "Herdr's expanded agent rows must show state text before the agent label";
pkgs.runCommand "herdr-config-test" { nativeBuildInputs = [ herdrPackage ]; } ''
  HERDR_CONFIG_PATH=${configFile} herdr config check
  touch "$out"
''
