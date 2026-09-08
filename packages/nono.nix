{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
  stdenvNoCC,
}:

let
  version = "0.75.0";
  release =
    {
      aarch64-darwin = {
        target = "aarch64-apple-darwin";
        hash = "sha256-fzPxE7GTkAYAtUlRwwYTetfgQ0at66oUKDx1K3Zzx9A=";
      };
      x86_64-darwin = {
        target = "x86_64-apple-darwin";
        hash = "sha256-9GDpKoIHUqib4G7/Z7iIIn5NuvmeBa27Nt0CfOtJgj4=";
      };
      aarch64-linux = {
        target = "aarch64-unknown-linux-gnu";
        hash = "sha256-xdIUIHerCbA4Kc9aA8IU6rdh4mpEC5ZIWPWJUNuTzQA=";
      };
      x86_64-linux = {
        target = "x86_64-unknown-linux-gnu";
        hash = "sha256-L4gyaYJNhflqdfuHiPbDFhnmDSwIZek0AtLzR0YQVPo=";
      };
    }
    .${stdenvNoCC.hostPlatform.system}
      or (throw "Nono has no official release for ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "nono";
  inherit version;

  src = fetchurl {
    url = "https://github.com/nolabs-ai/nono/releases/download/v${version}/nono-v${version}-${release.target}.tar.gz";
    inherit (release) hash;
  };

  sourceRoot = ".";
  dontBuild = true;

  nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  installPhase = ''
    runHook preInstall
    install -Dm755 nono "$out/bin/nono"
    runHook postInstall
  '';

  passthru = {
    isOfficialRelease = true;
    isPatchedForNix = stdenvNoCC.hostPlatform.isLinux;
  };

  meta = {
    description = "Sandbox shell for AI agents and command-line tools";
    homepage = "https://github.com/nolabs-ai/nono";
    license = lib.licenses.asl20;
    mainProgram = "nono";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
