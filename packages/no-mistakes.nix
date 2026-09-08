{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "1.70.1";
  releases = {
    aarch64-darwin = {
      os = "darwin";
      arch = "arm64";
      hash = "sha256-7hOz3SnKXWA/up8E+UkhxgdwZB0VIW1zEHgs63jt8gs=";
    };
    x86_64-darwin = {
      os = "darwin";
      arch = "amd64";
      hash = "sha256-Hii9fCG5+FX/JGc5+OBnO86Dmnrf9MCOqPX0QFFPUS8=";
    };
    aarch64-linux = {
      os = "linux";
      arch = "arm64";
      hash = "sha256-seARcAsPYA/LZ/GfHp5me1B1+bXqgoB7dxx8EXKS6N0=";
    };
    x86_64-linux = {
      os = "linux";
      arch = "amd64";
      hash = "sha256-ntw6WpfHEksj812M+ot3l2u/ZlcGezajPj7WZw4mhms=";
    };
  };
  release =
    releases.${stdenvNoCC.hostPlatform.system}
      or (throw "no-mistakes is unsupported on ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "no-mistakes";
  inherit version;

  src = fetchurl {
    url = "https://github.com/kunchenguid/no-mistakes/releases/download/v${version}/no-mistakes-v${version}-${release.os}-${release.arch}.tar.gz";
    inherit (release) hash;
  };

  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 no-mistakes "$out/bin/no-mistakes"
    mkdir -p "$out/share/zsh/site-functions"
    HOME="$TMPDIR" NO_MISTAKES_NO_UPDATE_CHECK=1 \
      "$out/bin/no-mistakes" completion zsh \
      > "$out/share/zsh/site-functions/_no-mistakes"
    runHook postInstall
  '';

  meta = {
    description = "AI-driven validation gate for clean pull requests";
    homepage = "https://github.com/kunchenguid/no-mistakes";
    license = lib.licenses.mit;
    mainProgram = "no-mistakes";
    platforms = builtins.attrNames releases;
  };
}
