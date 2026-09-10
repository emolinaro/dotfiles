{
  dshPackage,
  dshTuiPackage,
  pkgs,
}:

let
  inherit (pkgs.lib) getExe;
in
pkgs.runCommand "dsh-package-test"
  {
    nativeBuildInputs = [
      dshPackage
      dshTuiPackage
      pkgs.nodejs
    ];
  }
  ''
    set -euo pipefail

    test "$(dsh --version)" = "${dshPackage.version}"

    # The launcher runs with zero dependencies; version and doctor answer
    # without a DEEPSEEK_API_KEY or a bootstrapped profile.
    DSH_HOME="$TMPDIR/dsh-home" dsh-tui version | grep -F "dsh-tui ${dshTuiPackage.version} (launcher)"

    runtime_root="${dshPackage}/lib/node_modules/@deepseek-ai/dsh"
    test -x "$runtime_root/lib/bin.js"
    test -d "$runtime_root/node_modules/commander"
    test -d "$runtime_root/node_modules/node-pty"
    test -d "$runtime_root/node_modules/koffi"
    test ! -e "$runtime_root/node_modules/typescript"

    # A shipped-template profile boots offline from the installation's own
    # dependency tree through the module-fallback links, no pnpm needed. With
    # no credentials configured, the harness reports MISSING_CREDENTIAL and
    # exits non-zero - proof the plugin tree loaded without any resolution
    # against the network.
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export DSH_HOME="$TMPDIR/dsh-boot-home"
    export CI=true
    export TERM=dumb
    set +e
    dsh --profile headless "say OK" 2>"$TMPDIR/dsh-headless.err"
    headless_status=$?
    set -e
    test "$headless_status" -ne 0
    grep -F "MISSING_CREDENTIAL" "$TMPDIR/dsh-headless.err"

    touch "$out"
  ''
