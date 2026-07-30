{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
  stdenvNoCC,
}:

let
  version = "0.70.0";
  release =
    {
      aarch64-darwin = {
        target = "aarch64-apple-darwin";
        hash = "sha256-lhD2K3TkFbjTZeAB9V9kiPSbG1hypg+6MlB1n2X0TlM=";
      };
      x86_64-darwin = {
        target = "x86_64-apple-darwin";
        hash = "sha256-8J1i7n1dimb2EcM8XDtwt2yYhw9sUh0F5WRqO/jZ1XQ=";
      };
      aarch64-linux = {
        target = "aarch64-unknown-linux-gnu";
        hash = "sha256-+qQeaiCxm1kx6GuBWcTAAxk2EJz3IY7JK21jamXu1EU=";
      };
      x86_64-linux = {
        target = "x86_64-unknown-linux-gnu";
        hash = "sha256-3ofJkRlNiWAN5A3nycdxKjNIQWLgpKu+bxTppHUuFWc=";
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
