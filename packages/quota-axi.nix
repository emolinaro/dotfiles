# Pinned npm artifact; refresh with scripts/update-npm-tool.sh quota-axi
{ callPackage, lib }:
callPackage ./npm-tool.nix {
  pname = "quota-axi";
  version = "0.1.69";
  entryPoint = "dist/bin/quota-axi.js";
  hash = "sha256-1pSKI20ggK811yHtFGBViHpZDj3yP/a7lmVO6zyiaPU=";
  depsHash = "sha256-OUcoX6cHkFidnVSbSrOmw1KaHyybP1BdMoN2YNjELwo=";
  description = "Report local AI provider quota windows";
  homepage = "https://github.com/kunchenguid/quota-axi";
}
