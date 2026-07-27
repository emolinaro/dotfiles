{
  axiTools,
  fetchPnpmDeps,
  lib,
  makeWrapper,
  nodejs,
  pnpm_11,
  pnpmConfigHook,
  stdenvNoCC,
  symlinkJoin,
}:

let
  mkAxiTool =
    {
      pname,
      src,
      entryPoint,
      pnpmDepsHash,
    }:
    stdenvNoCC.mkDerivation {
      inherit pname src;
      version = (builtins.fromJSON (builtins.readFile "${src}/package.json")).version;

      pnpmDeps = fetchPnpmDeps {
        inherit pname src;
        pnpm = pnpm_11;
        fetcherVersion = 4;
        hash = pnpmDepsHash;
      };

      nativeBuildInputs = [
        makeWrapper
        nodejs
        pnpm_11
        pnpmConfigHook
      ];

      buildPhase = ''
        runHook preBuild
        pnpm build
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        install -dm755 "$out/lib/node_modules/${pname}"
        cp -r dist node_modules package.json "$out/lib/node_modules/${pname}/"
        makeWrapper ${lib.getExe nodejs} "$out/bin/${pname}" \
          --add-flags "$out/lib/node_modules/${pname}/${entryPoint}"
        runHook postInstall
      '';
    };
in
symlinkJoin {
  name = "axi-tools";
  paths = map mkAxiTool axiTools;
}
