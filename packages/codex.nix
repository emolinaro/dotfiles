{
  codex,
  lib,
  makeWrapper,
  ripgrep,
  symlinkJoin,
}:

symlinkJoin {
  name = "codex-system-bwrap-${codex.version}";
  paths = [ codex ];
  nativeBuildInputs = [ makeWrapper ];
  meta = codex.meta;

  # Ubuntu's AppArmor profile authorizes /usr/bin/bwrap specifically. Keep
  # ripgrep available, but replace Nixpkgs' launcher so Codex resolves the
  # host's bwrap from PATH without rebuilding the Rust package.
  postBuild = ''
    rm "$out/bin/codex"
    makeWrapper "${codex}/bin/.codex-wrapped" "$out/bin/codex" \
      --prefix PATH : ${lib.makeBinPath [ ripgrep ]}
  '';
}
