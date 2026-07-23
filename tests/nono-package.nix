{
  nonoPackage,
  pkgs,
}:

let
  isOfficialRelease = nonoPackage.passthru.isOfficialRelease or false;
  linuxIsPatched =
    (!pkgs.stdenv.hostPlatform.isLinux) || (nonoPackage.passthru.isPatchedForNix or false);
in
assert pkgs.lib.assertMsg isOfficialRelease "Nono must use the official prebuilt release artifact";
assert pkgs.lib.assertMsg linuxIsPatched
  "The official Linux Nono binary must be patched for the Nix runtime";
pkgs.runCommand "nono-package-test" { nativeBuildInputs = [ nonoPackage ]; } ''
  set -euo pipefail

  test "$(nono --version)" = "nono ${nonoPackage.version}"
  touch "$out"
''
