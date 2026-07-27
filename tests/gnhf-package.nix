{ gnhfCli, gnhfPackage, pkgs }:

pkgs.runCommand "gnhf-package-test"
  {
    nativeBuildInputs = [ gnhfPackage ];
  }
  ''
    set -euo pipefail

    test "$(gnhf --version)" = "${gnhfPackage.version}"
    runtime_root="${gnhfCli}/lib/node_modules/gnhf"
    test -x "$runtime_root/dist/cli.mjs"
    test -d "$runtime_root/node_modules/commander"
    test -d "$runtime_root/node_modules/js-yaml"
    test ! -e "$runtime_root/node_modules/typescript"

    for command_name in \
      gnhf \
      gnhf-codex \
      gnhf-codex-nono \
      gnhf-opencode \
      gnhf-opencode-nono
    do
      test -x "${gnhfPackage}/bin/$command_name"
    done

    touch "$out"
  ''
