{
  nodejs,
  symlinkJoin,
  writeShellScriptBin,
}:

symlinkJoin {
  name = "axi-tools";
  paths = map (
    name:
    writeShellScriptBin name ''
      exec ${nodejs}/bin/npx --yes ${name} "$@"
    ''
  ) [
    "chrome-devtools-axi"
    "gh-axi"
    "lavish-axi"
    "quota-axi"
    "tasks-axi"
  ];
}
