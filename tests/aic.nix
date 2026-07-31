{
  aicPackage,
  pkgs,
}:

pkgs.runCommand "aic-test"
  {
    nativeBuildInputs = [
      aicPackage
      pkgs.bash
      pkgs.coreutils
      pkgs.gawk
      pkgs.git
      pkgs.zsh
    ];
  }
  ''
    set -euo pipefail
    zsh ${./aic.zsh} ${pkgs.lib.getExe aicPackage}
    touch "$out"
  ''
