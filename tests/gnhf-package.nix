{ gnhfPackage
, pkgs
,
}:

let
  conflictingOpencode = pkgs.writeShellScript "gnhf-conflicting-opencode" ''
    printf '%s\n' "conflicting agentPathOverride was used" >&2
    exit 97
  '';
in
pkgs.runCommand "gnhf-package-test"
{
  nativeBuildInputs = [
    gnhfPackage
    pkgs.git
    pkgs.nodejs
  ];
}
  ''
    set -euo pipefail

    test "$(gnhf --version)" = "${gnhfPackage.version}"

    gnhf --help > help.txt
    grep -F -- "--agent <agent>" help.txt
    grep -F -- "--agent-path <path>" help.txt
    grep -F -- "--worktree" help.txt
    grep -F -- "--max-iterations <n>" help.txt
    grep -F -- "--stop-when <condition>" help.txt

    test -s "${gnhfPackage.passthru.skillPath}/SKILL.md"

    fixture_bin="$TMPDIR/fixture-bin"
    fixture_home="$TMPDIR/home"
    fixture_repo="$TMPDIR/repo"
    mkdir -p "$fixture_bin" "$fixture_home" "$fixture_repo"
    mkdir -p "$fixture_home/.gnhf"
    cp ${gnhfPackage.src}/e2e/fixtures/opencode "$fixture_bin/opencode"
    cp ${gnhfPackage.src}/e2e/fixtures/mock-opencode-server.mjs \
      "$fixture_bin/mock-opencode-server.mjs"
    chmod +x "$fixture_bin/opencode"
    printf 'agentPathOverride:\n  opencode: %s\n' \
      ${pkgs.lib.escapeShellArg (toString conflictingOpencode)} \
      > "$fixture_home/.gnhf/config.yml"
    config_before="$(<"$fixture_home/.gnhf/config.yml")"

    touch "$TMPDIR/empty-gitconfig"
    export GIT_CONFIG_GLOBAL="$TMPDIR/empty-gitconfig"
    export GIT_CONFIG_SYSTEM="$TMPDIR/empty-gitconfig"
    export GIT_TERMINAL_PROMPT=0
    export GNHF_MOCK_OPENCODE_LOG_PATH="$TMPDIR/mock-opencode.jsonl"
    export GNHF_TELEMETRY=0
    export HOME="$fixture_home"
    export PATH="$fixture_bin:$PATH"

    git -C "$fixture_repo" init -b main
    git -C "$fixture_repo" config user.name "GNHF package test"
    git -C "$fixture_repo" config user.email "gnhf-package-test@example.com"
    echo "# fixture" > "$fixture_repo/README.md"
    git -C "$fixture_repo" add README.md
    git -C "$fixture_repo" commit -m "init"

    pushd "$fixture_repo"
    gnhf "ship it" \
      --agent opencode \
      --agent-path "$fixture_bin/opencode" \
      --max-iterations 1 \
      --prevent-sleep off \
      > "$TMPDIR/gnhf-stdout.txt" \
      2> "$TMPDIR/gnhf-stderr.txt" || {
        sed -n '1,200p' "$TMPDIR/gnhf-stdout.txt"
        sed -n '1,200p' "$TMPDIR/gnhf-stderr.txt" >&2
        exit 1
      }
    popd

    commit_count="$(git -C "$fixture_repo" rev-list --count HEAD)"
    if [[ "$commit_count" != 2 ]]; then
      sed -n '1,200p' "$TMPDIR/gnhf-stdout.txt"
      sed -n '1,200p' "$TMPDIR/gnhf-stderr.txt" >&2
      sed -n '1,200p' "$GNHF_MOCK_OPENCODE_LOG_PATH" >&2
      git -C "$fixture_repo" log --oneline >&2
      exit 1
    fi
    git -C "$fixture_repo" log -1 --format=%s | grep -F "gnhf 1:"
    grep -F "gnhf stopped" "$TMPDIR/gnhf-stdout.txt"
    grep -F '"event":"server:start"' "$GNHF_MOCK_OPENCODE_LOG_PATH"
    test "$(<"$fixture_home/.gnhf/config.yml")" = "$config_before"

    mkdir "$out"
  ''
