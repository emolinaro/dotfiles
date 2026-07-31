{ pkgs }:

let
  apparmorParser = pkgs.writeShellApplication {
    name = "apparmor_parser";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      test "$1" = -r
      test "$2" = "$CODEX_APPARMOR_PROFILE_TARGET"
      touch "$CODEX_APPARMOR_PROFILE_LOADED"
    '';
  };
  bwrap = pkgs.writeShellApplication {
    name = "bwrap";
    text = ''
      test -e "$CODEX_APPARMOR_PROFILE_TARGET"
      test -e "$CODEX_APPARMOR_PROFILE_LOADED"
    '';
  };
  profile = pkgs.writeText "bwrap-userns-restrict" "test AppArmor profile\n";
  sudo = pkgs.writeShellApplication {
    name = "sudo";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      if [[ "$1" == apt-get ]]; then
        if [[ "$2" == install ]]; then
          install -Dm755 "$CODEX_TEST_BWRAP_TEMPLATE" "$CODEX_TEST_BWRAP_TARGET"
          install -Dm644 "$CODEX_TEST_PROFILE_TEMPLATE" "$CODEX_TEST_PROFILE_SOURCE"
        fi
        exit 0
      fi
      exec "$@"
    '';
  };
in
pkgs.runCommand "codex-sandbox-setup-test"
  {
    nativeBuildInputs = [
      apparmorParser
      pkgs.coreutils
      sudo
    ];
  }
  ''
    set -euo pipefail
    export CODEX_APPARMOR_PROFILE_TARGET="$TMPDIR/etc/apparmor.d/bwrap-userns-restrict"
    export CODEX_APPARMOR_PROFILE_LOADED="$TMPDIR/apparmor-profile-loaded"
    mkdir -p "$(dirname "$CODEX_APPARMOR_PROFILE_TARGET")"

    setup_library=${../scripts}/lib-codex-sandbox.sh
    if [[ ! -r "$setup_library" ]]; then
      echo "Codex sandbox setup library is missing" >&2
      exit 1
    fi
    # shellcheck disable=SC1090
    . "$setup_library"

    configure_codex_sandbox \
      "${bwrap}/bin/bwrap" \
      "${profile}" \
      "$CODEX_APPARMOR_PROFILE_TARGET" \
      sudo

    cmp "${profile}" "$CODEX_APPARMOR_PROFILE_TARGET"
    test -e "$CODEX_APPARMOR_PROFILE_LOADED"

    missing_root="$TMPDIR/missing-prerequisites"
    export CODEX_TEST_BWRAP_TEMPLATE="${bwrap}/bin/bwrap"
    export CODEX_TEST_BWRAP_TARGET="$missing_root/usr/bin/bwrap"
    export CODEX_TEST_PROFILE_TEMPLATE="${profile}"
    export CODEX_TEST_PROFILE_SOURCE="$missing_root/usr/share/apparmor/extra-profiles/bwrap-userns-restrict"
    export CODEX_APPARMOR_PROFILE_TARGET="$missing_root/etc/apparmor.d/bwrap-userns-restrict"
    export CODEX_APPARMOR_PROFILE_LOADED="$missing_root/apparmor-profile-loaded"
    mkdir -p "$(dirname "$CODEX_APPARMOR_PROFILE_TARGET")"

    ensure_codex_sandbox \
      "$CODEX_TEST_BWRAP_TARGET" \
      "$CODEX_TEST_PROFILE_SOURCE" \
      "$CODEX_APPARMOR_PROFILE_TARGET" \
      sudo

    test -x "$CODEX_TEST_BWRAP_TARGET"
    cmp "${profile}" "$CODEX_TEST_PROFILE_SOURCE"
    cmp "${profile}" "$CODEX_APPARMOR_PROFILE_TARGET"
    test -e "$CODEX_APPARMOR_PROFILE_LOADED"
    touch "$out"
  ''
