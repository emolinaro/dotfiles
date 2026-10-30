# Pinned npm artifact; refresh with scripts/update-npm-tool.sh tasks-axi
{ callPackage, lib }:
callPackage ./npm-tool.nix {
  pname = "tasks-axi";
  version = "0.2.6";
  entryPoint = "dist/bin/tasks-axi.js";
  hash = "sha256-kzQv5sga9RZpvYonP56ImjY0KISHc8yQe64fcak5Cdk=";
  depsHash = "sha256-WCojRhSbYU1n8RffjOGQro0+mbdmTUgp859ldAK+QYg=";
  description = "Manage a task backlog with dependencies and a ready queue";
  homepage = "https://github.com/kunchenguid/tasks-axi";
}
