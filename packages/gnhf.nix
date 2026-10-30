# Pinned npm artifact; refresh with scripts/update-npm-tool.sh gnhf
{ callPackage, lib }:
callPackage ./npm-tool.nix {
  pname = "gnhf";
  version = "0.1.51";
  entryPoint = "dist/cli.mjs";
  hash = "sha256-8rrtCWz0npY+V4tsd37SESPlIfElAN69lCIend0Yoew=";
  depsHash = "sha256-uQdWHrRvwa2kEEexVzI5ocMM7sgESe5ftzVu7Cb0bR8=";
  description = "Give coding agents a verification loop they must satisfy";
  homepage = "https://github.com/kunchenguid/gnhf";
}
