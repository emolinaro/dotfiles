{ fetchurl, lib, stdenvNoCC }:

let
  version = "1.40.0";
  releases = {
    aarch64-darwin = {
      os = "darwin";
      arch = "arm64";
      hash = "sha256-jU6Avifov7BB/E7X6TW/SysO76HZTllmNMlPxtyU+m0=";
    };
    x86_64-darwin = {
      os = "darwin";
      arch = "amd64";
      hash = "sha256-jxOq0KiSdiz6huHgXLG+VVUomp2Lo9OrkEwfZ1cMSyk=";
    };
    aarch64-linux = {
      os = "linux";
      arch = "arm64";
      hash = "sha256-5nk3DM/iDjAoxZ7ZhFEOcHeZag0XuNwZblsZkhjx250=";
    };
    x86_64-linux = {
      os = "linux";
      arch = "amd64";
      hash = "sha256-JEW2UXnQ6Om79AgyL1cZDzRPmUbP7TlxyE+hbOQSLpE=";
    };
  };
  release = releases.${stdenvNoCC.hostPlatform.system}
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
