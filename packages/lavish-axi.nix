# Pinned npm artifact; refresh with scripts/update-npm-tool.sh lavish-axi
{ callPackage, lib }:
callPackage ./npm-tool.nix {
  pname = "lavish-axi";
  version = "0.1.96";
  entryPoint = "dist/cli.mjs";
  hash = "sha256-4Q1X1LIkerZxSDWJsi8jBf6d7NmLq+TURqzDLtTm5wI=";
  depsHash = "sha256-Y20MlvFQeqLep5HtSe2Jp8nlXpK9qb4vUpwydFKzrsM=";
  description = "Render agent responses as reviewable HTML artifacts";
  homepage = "https://github.com/kunchenguid/lavish-axi";
}
