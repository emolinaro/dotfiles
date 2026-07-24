{ fetchurl, lib, stdenvNoCC }:

let
  version = "2.1.0";
  releases = {
    aarch64-darwin = {
      os = "darwin";
      arch = "arm64";
      hash = "sha256-oum8uojWQ6goBi80Jdz2AYhjcvwqyoe1QrNvyLvyyZI=";
    };
    x86_64-darwin = {
      os = "darwin";
      arch = "amd64";
      hash = "sha256-jrLrO2P0CaMWvZwZr10wNeW3L2/v/Jjw+sZY4e0zo5c=";
    };
    aarch64-linux = {
      os = "linux";
      arch = "arm64";
      hash = "sha256-1ON60R1Q+2OBwGDTTnNy6UTgGveLDGcHxtD/lmx8LEQ=";
    };
    x86_64-linux = {
      os = "linux";
      arch = "amd64";
      hash = "sha256-/wMCVWY7tdOEMJzfGzoL1iAG4KyXg0DSkgOWl8twwiU=";
    };
  };
  release = releases.${stdenvNoCC.hostPlatform.system}
    or (throw "treehouse is unsupported on ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "treehouse";
  inherit version;

  src = fetchurl {
    url = "https://github.com/kunchenguid/treehouse/releases/download/v${version}/treehouse-v${version}-${release.os}-${release.arch}.tar.gz";
    inherit (release) hash;
  };

  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 treehouse "$out/bin/treehouse"
    mkdir -p "$out/share/zsh/site-functions"
    HOME="$TMPDIR" "$out/bin/treehouse" completion zsh \
      > "$out/share/zsh/site-functions/_treehouse"
    runHook postInstall
  '';

  meta = {
    description = "Git worktree manager for parallel agent workflows";
    homepage = "https://github.com/kunchenguid/treehouse";
    license = lib.licenses.mit;
    mainProgram = "treehouse";
    platforms = builtins.attrNames releases;
  };
}
