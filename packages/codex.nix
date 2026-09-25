{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "0.155.1";
  releases = {
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-1sfmL71ojVLuBPOSnQYTcF0yqSCkLbehOeNm6vH0otc=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-oO+LLevDv3R+B7GgOTVN4xMArA3MInZJi6KBRwtdkRU=";
    };
  };
  release =
    releases.${stdenvNoCC.hostPlatform.system}
      or (throw "codex is unsupported on ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "codex";
  inherit version;

  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-${release.target}.tar.gz";
    inherit (release) hash;
  };

  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    # The tarball ships a platform-suffixed name; expose a plain `codex`.
    install -Dm755 codex-${release.target} "$out/bin/codex"
    runHook postInstall
  '';

  meta = {
    description = "OpenAI Codex CLI";
    homepage = "https://github.com/openai/codex";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    platforms = builtins.attrNames releases;
  };
}
