{ gnhfPackage, pkgs }:

pkgs.runCommand "gnhf-wrapper-test"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      gnhfPackage
    ];
  }
  ''
    set -euo pipefail

    for command_name in \
      gnhf \
      gnhf-codex \
      gnhf-codex-nono \
      gnhf-opencode \
      gnhf-opencode-nono
    do
      command_path="${gnhfPackage}/bin/$command_name"
      test -x "$command_path"
      ! grep --fixed-strings --quiet npx "$command_path"
      ! grep --fixed-strings --quiet npm "$command_path"
    done

    grep --fixed-strings --quiet -- "--agent codex" "${gnhfPackage}/bin/gnhf"
    grep --fixed-strings --quiet -- "--agent codex" "${gnhfPackage}/bin/gnhf-codex"
    grep --fixed-strings --quiet -- "--agent codex" "${gnhfPackage}/bin/gnhf-codex-nono"
    grep --fixed-strings --quiet -- "--agent opencode" "${gnhfPackage}/bin/gnhf-opencode"
    grep --fixed-strings --quiet -- "--agent opencode" "${gnhfPackage}/bin/gnhf-opencode-nono"

    touch "$out"
  ''
