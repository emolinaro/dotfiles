{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
  stdenvNoCC,
}:

let
  version = "3.1.7";
  releases = {
    aarch64-darwin = {
      os = "darwin";
      arch = "arm64";
      hash = "sha256-6btd6HJFQa8q+m2Eb9PIDYuXQc8snZd9/i6jInRB1Nk=";
    };
    x86_64-darwin = {
      os = "darwin";
      arch = "amd64";
      hash = "sha256-c+EMmrtF6n+HQO8Qy68U37ujtQYZLQw2reDTKelHKPE=";
    };
    aarch64-linux = {
      os = "linux";
      arch = "arm64";
      hash = "sha256-Lb2rmv8lXRmMWqw+kbd7fUJs1NjgJ7PZVsHZKv7/5zI=";
    };
    x86_64-linux = {
      os = "linux";
      arch = "amd64";
      hash = "sha256-Zk+ocPOIfIuUTECBhTkUMlm6tPbw1pBVDZ/GpLizpu4=";
    };
  };
  release =
    releases.${stdenvNoCC.hostPlatform.system}
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

  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 treehouse "$out/bin/treehouse"
    ${lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
      autoPatchelf -- "$out/bin/treehouse"
    ''}
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
