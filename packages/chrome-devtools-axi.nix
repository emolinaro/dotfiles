# Pinned npm artifact; refresh with scripts/update-npm-tool.sh chrome-devtools-axi
{ callPackage, lib }:
callPackage ./npm-tool.nix {
  pname = "chrome-devtools-axi";
  version = "0.1.46";
  entryPoint = "dist/bin/chrome-devtools-axi.js";
  hash = "sha256-YhP9z87gIt3J13LGJNPAMShzELeFXdg9K9rfoOm5DfE=";
  depsHash = "sha256-JzBrwJbCcqBMZTyzME7CRa97axAPYV43LxPCe0k+PeY=";
  description = "Drive a Chrome browser session over the DevTools protocol";
  homepage = "https://github.com/kunchenguid/chrome-devtools-axi";
}
