{
  pkgs,
  zshInitContent,
}:

let
  initContentFile = pkgs.writeText "aic-zsh-init-content" zshInitContent;
in
pkgs.runCommand "aic-test"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.git
      pkgs.jq
      pkgs.zsh
    ];
  }
  ''
    set -euo pipefail
    zsh ${./aic.zsh} ${initContentFile}
    touch "$out"
  ''
