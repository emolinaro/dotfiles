{ axiToolsPackage, pkgs }:

pkgs.runCommand "axi-tools-test"
  {
    nativeBuildInputs = [ axiToolsPackage ];
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    for command_name in \
      chrome-devtools-axi \
      gh-axi \
      lavish-axi \
      quota-axi \
      tasks-axi
    do
      "$command_name" --help > /dev/null
    done

    touch "$out"
  ''
