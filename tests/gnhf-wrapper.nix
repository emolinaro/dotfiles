{ packageModule, pkgs }:

let
  fakeNodejs = pkgs.runCommand "gnhf-test-nodejs" { } ''
    mkdir -p "$out/bin"
    cat > "$out/bin/npx" <<'EOF'
    #!${pkgs.runtimeShell}
    set -eu
    : "''${GNHF_TEST_TRACE:?GNHF_TEST_TRACE must name a trace file}"
    printf '%s\n' "$@" > "$GNHF_TEST_TRACE"
    EOF
    chmod +x "$out/bin/npx"
  '';

  wrappers = pkgs.callPackage packageModule {
    nodejs = fakeNodejs;
  };
in
pkgs.runCommand "gnhf-wrapper-test"
  {
    nativeBuildInputs = [ pkgs.diffutils ];
  }
  ''
    set -euo pipefail

    assert_args() {
      local command_name="$1"
      local expected_agent="$2"
      local trace="$TMPDIR/$command_name.trace"
      GNHF_TEST_TRACE="$trace" \
        "${wrappers}/bin/$command_name" --max-iterations 1 "Make README file less verbose"

      cat > "$TMPDIR/$command_name.expected" <<EOF
    -y
    gnhf
    --agent
    $expected_agent
    --max-iterations
    1
    Make README file less verbose
    EOF
      diff -u "$TMPDIR/$command_name.expected" "$trace"
    }

    assert_args gnhf codex
    assert_args gnhf-codex codex
    assert_args gnhf-opencode opencode
    assert_args gnhf-codex-nono codex
    assert_args gnhf-opencode-nono opencode

    touch "$out"
  ''
