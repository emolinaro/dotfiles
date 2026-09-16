{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
  stdenvNoCC,
}:

let
  version = "0.78.0";
  release =
    {
      aarch64-darwin = {
        target = "aarch64-apple-darwin";
        hash = "sha256-rBYbVR4U7m9d+06VWTlk6a9F25ydAQdMvn1r9BEGgLQ=";
      };
      x86_64-darwin = {
        target = "x86_64-apple-darwin";
        hash = "sha256-uuQCyQ6djyXpTmwhtW5UpnTr//P6G9w8KY4b/C9+gtw=";
      };
      aarch64-linux = {
        target = "aarch64-unknown-linux-gnu";
        hash = "sha256-cwi0EJlA8W7A0CTrS7z6zhz+LqHoMz3RR6tPC+dwYHE=";
      };
      x86_64-linux = {
        target = "x86_64-unknown-linux-gnu";
        hash = "sha256-r16DeXPVR6r208370S45UiJNG7d7cpKWLqGRgDmcONs=";
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
