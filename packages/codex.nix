{
  bwrapPath ? "/usr/bin/bwrap",
  codex,
  lib,
  makeWrapper,
  ripgrep,
  symlinkJoin,
  writeShellScriptBin,
}:

let
  systemBwrap = writeShellScriptBin "bwrap" ''
    exec ${lib.escapeShellArg bwrapPath} "$@"
  '';
in
symlinkJoin {
  name = "codex-system-bwrap-${codex.version}";
  paths = [ codex ];
  nativeBuildInputs = [ makeWrapper ];
  meta = codex.meta;

  # Ubuntu's AppArmor profile authorizes /usr/bin/bwrap specifically.
  postBuild = ''
    rm "$out/bin/codex"
    makeWrapper "${codex}/bin/.codex-wrapped" "$out/bin/codex" \
      --prefix PATH : ${
        lib.makeBinPath [
          systemBwrap
          ripgrep
        ]
      }
  '';
}
