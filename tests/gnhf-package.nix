{ gnhfPackage, pkgs }:

pkgs.runCommand "gnhf-package-test"
  {
    nativeBuildInputs = [ gnhfPackage ];
  }
  ''
    set -euo pipefail

    test "$(gnhf --version)" = "${gnhfPackage.version}"
    test -x "${gnhfPackage}/bin/gnhf"

    runtime_root="${gnhfPackage}/lib/node_modules/gnhf"
    test -x "$runtime_root/dist/cli.mjs"
    test -d "$runtime_root/node_modules/commander"
    test -d "$runtime_root/node_modules/js-yaml"
    test ! -e "$runtime_root/node_modules/typescript"

    touch "$out"
  ''
