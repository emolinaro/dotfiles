{
  autoPatchelfHook,
  fetchurl,
  lib,
  makeBinaryWrapper,
  stdenvNoCC,
}:

let
  version = "2.1.278";
  releases = {
    aarch64-linux = {
      os = "linux";
      arch = "arm64";
      hash = "sha256-XjzDZ/mXhHyJzbo/WxzW/1qruOlOFLGbrUARJMDoOO0=";
    };
    x86_64-linux = {
      os = "linux";
      arch = "x64";
      hash = "sha256-HR+ZULlqy1pQvzQqPTvVHN9AsXFLLKPOIxm6jo5/NjM=";
    };
  };
  release =
    releases.${stdenvNoCC.hostPlatform.system}
      or (throw "claude-code is unsupported on ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "claude-code";
  inherit version;

  src = fetchurl {
    url = "https://github.com/anthropics/claude-code/releases/download/v${version}/claude-${release.os}-${release.arch}.tar.gz";
    inherit (release) hash;
  };

  sourceRoot = ".";
  dontBuild = true;
  # The bun runtime is embedded; stripping confuses it into executing the
  # wrong entrypoint.
  dontStrip = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeBinaryWrapper
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 claude "$out/bin/claude"
    wrapProgram "$out/bin/claude" \
      --set DISABLE_AUTOUPDATER 1 \
      --set DISABLE_INSTALLATION_CHECKS 1
    runHook postInstall
  '';

  meta = {
    description = "Anthropic Claude Code CLI";
    homepage = "https://github.com/anthropics/claude-code";
    license = lib.licenses.unfree;
    mainProgram = "claude";
    platforms = builtins.attrNames releases;
  };
}
