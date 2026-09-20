{
  autoPatchelfHook,
  fetchurl,
  lib,
  makeBinaryWrapper,
  stdenvNoCC,
}:

let
  version = "1.18.31";
  releases = {
    aarch64-linux = {
      os = "linux";
      arch = "arm64";
      hash = "sha256-1OMy9GsidEhYLA2fx19vgm3+lcn3UbwgEfxNk3oEK+Y=";
    };
    x86_64-linux = {
      os = "linux";
      arch = "x64";
      hash = "sha256-6TEr517YA7dBX8Kuq9ofT+k4kSo5Zzdi3Aw4wOEeveQ=";
    };
  };
  release =
    releases.${stdenvNoCC.hostPlatform.system}
      or (throw "opencode is unsupported on ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "opencode";
  inherit version;

  src = fetchurl {
    url = "https://github.com/sst/opencode/releases/download/v${version}/opencode-${release.os}-${release.arch}.tar.gz";
    inherit (release) hash;
  };

  sourceRoot = ".";
  dontBuild = true;
  # Bun single-file executable: stripping breaks the appended payload offset
  # and the binary degrades to running as plain Bun instead of opencode.
  dontStrip = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeBinaryWrapper
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 opencode "$out/bin/opencode"
    wrapProgram "$out/bin/opencode" --set OPENCODE_DISABLE_AUTOUPDATE 1
    runHook postInstall
  '';

  meta = {
    description = "OpenCode AI coding agent";
    homepage = "https://github.com/sst/opencode";
    license = lib.licenses.mit;
    mainProgram = "opencode";
    platforms = builtins.attrNames releases;
  };
}
