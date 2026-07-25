{
  gnhfPackage,
  pkgs,
}:

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
    grep -F -- "--worktree" help.txt
    grep -F -- "--max-iterations <n>" help.txt
    grep -F -- "--stop-when <condition>" help.txt

    test -s "${gnhfPackage.passthru.skillPath}/SKILL.md"

    fixture_bin="$TMPDIR/fixture-bin"
    fixture_home="$TMPDIR/home"
    fixture_repo="$TMPDIR/repo"
    mkdir -p "$fixture_bin" "$fixture_home" "$fixture_repo"
    cp ${gnhfPackage.src}/e2e/fixtures/opencode "$fixture_bin/opencode"
    cp ${gnhfPackage.src}/e2e/fixtures/mock-opencode-server.mjs \
      "$fixture_bin/mock-opencode-server.mjs"
    chmod +x "$fixture_bin/opencode"

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
      --max-iterations 1 \
      --prevent-sleep off \
      > "$TMPDIR/gnhf-stdout.txt" \
      2> "$TMPDIR/gnhf-stderr.txt"
    popd

    test "$(git -C "$fixture_repo" rev-list --count HEAD)" = "2"
    git -C "$fixture_repo" log -1 --format=%s | grep -F "gnhf 1:"
    grep -F "gnhf stopped" "$TMPDIR/gnhf-stdout.txt"
    grep -F '"event":"server:start"' "$GNHF_MOCK_OPENCODE_LOG_PATH"

    mkdir "$out"
  ''
