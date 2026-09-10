{
  fetchurl,
  lib,
  makeWrapper,
  nodejs,
  stdenvNoCC,
}:

let
  version = "0.10.0";
in
stdenvNoCC.mkDerivation {
  pname = "dsh-tui";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@deepseek-harness-tui/dsh-tui/-/dsh-tui-${version}.tgz";
    hash = "sha256-NqQLMp0uQjIoe7DD1HqYJZokylEAT6zwO2XwDOHa228=";
  };

  # The launcher is dependency-free by design (a migration contract of
  # dsh-tui's update flow), so no npm resolution happens here.
  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -dm755 "$out/lib/node_modules/@deepseek-harness-tui/dsh-tui"
    cp -r bin lib presets cordis.yml cordis.patch.yml dsh-ecosystem-spec package.json \
      "$out/lib/node_modules/@deepseek-harness-tui/dsh-tui/"
    for binary in dsh-tui dst; do
      makeWrapper ${lib.getExe nodejs} "$out/bin/$binary" \
        --add-flags "$out/lib/node_modules/@deepseek-harness-tui/dsh-tui/bin/dsh-tui.js"
    done

    runHook postInstall
  '';

  meta = {
    description = "Interactive terminal interface for DeepSeek Harness agents, sessions and tools";
    homepage = "https://github.com/ccch1mneyyy/dsh-TUI";
    license = lib.licenses.mit;
    mainProgram = "dsh-tui";
    platforms = lib.platforms.unix;
  };
}
