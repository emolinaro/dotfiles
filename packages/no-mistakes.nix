{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "1.72.0";
  releases = {
    aarch64-darwin = {
      os = "darwin";
      arch = "arm64";
      hash = "sha256-w6OOleBQww7jA4BvIvvccI+UXijWsknY6VQN5lvstcc=";
    };
    x86_64-darwin = {
      os = "darwin";
      arch = "amd64";
      hash = "sha256-uCqHO+lHNnDzir4dmiGmSHfERTB9hd/Y0Q39jT4fkNI=";
    };
    aarch64-linux = {
      os = "linux";
      arch = "arm64";
      hash = "sha256-kvQCZUveqEXe2c68pB/VZeKuZUu4HJziKC4KJhDfhzY=";
    };
    x86_64-linux = {
      os = "linux";
      arch = "amd64";
      hash = "sha256-wia2m4uBFYJ9LkOOqLMur/m4kpGh0v3cXvJEkBe42Sc=";
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
