{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
  stdenvNoCC,
}:

let
  version = "0.80.0";
  release =
    {
      aarch64-darwin = {
        target = "aarch64-apple-darwin";
        hash = "sha256-roJBZ7PZBTG4MEKbqSt3gTebHC15+bEf3Yiw/SZ+TjI=";
      };
      x86_64-darwin = {
        target = "x86_64-apple-darwin";
        hash = "sha256-s1TmdOa0ZDrVxXLRSK42e7DFwQNBD7wikjxVk6b30LI=";
      };
      aarch64-linux = {
        target = "aarch64-unknown-linux-gnu";
        hash = "sha256-0qJMjDdxT4XIKbVYb/2B/CrPM2yVNy2IG6YhQIhPIss=";
      };
      x86_64-linux = {
        target = "x86_64-unknown-linux-gnu";
        hash = "sha256-baZlthmZVwwQ3/x9p4go/h+388rFMxnlBc6+yu8XA38=";
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
