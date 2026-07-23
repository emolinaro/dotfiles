{
  nonoPackage,
  pkgs,
  profiles,
}:

let
  probe = pkgs.writeShellApplication {
    name = "nono-runtime-probe";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
    ];
    text = ''
      host_config="$1"
      shared_temp="$2"

      if printf "%s\n" compromised > "$host_config"; then
        exit 41
      fi
      if touch "$shared_temp/escaped"; then
        exit 42
      fi
      printf "%s\n" runtime > "$HOME/.codex/runtime"
      git status --short >/dev/null
      printf "%s\n" changed >> tracked
      git add tracked
    '';
  };
in
pkgs.writeShellApplication {
  name = "nono-runtime-test";
  runtimeInputs = [
    nonoPackage
    pkgs.coreutils
    pkgs.git
    pkgs.python3
  ];
  text = ''
    build_root="$(mktemp -d "''${TMPDIR:-/tmp}/nono-runtime.XXXXXX")"
    socket_server=

    cleanup() {
      status=$?
      trap - EXIT HUP INT TERM
      if [[ -n "$socket_server" ]]; then
        kill "$socket_server" 2>/dev/null || true
        wait "$socket_server" 2>/dev/null || true
      fi
      rm -rf -- "$build_root"
      exit "$status"
    }
    trap cleanup EXIT HUP INT TERM

    export HOME="$build_root/host-home"
    export DOTFILES_HOST_HOME="$HOME"
    export DOTFILES_AGENT_HOME="$build_root/agent-home"
    export XDG_CONFIG_HOME="$build_root/nono-config"
    export SSH_AUTH_SOCK="$build_root/ssh-agent.sock"
    session_temp="$build_root/session-temp"
    shared_temp="$build_root/shared-temp"
    profile_dir="$XDG_CONFIG_HOME/nono/profiles"
    host_config="$DOTFILES_HOST_HOME/.codex/config.toml"
    mkdir -p \
      "$DOTFILES_AGENT_HOME/.codex" \
      "$DOTFILES_HOST_HOME/.cache/herdr" \
      "$DOTFILES_HOST_HOME/.codex" \
      "$profile_dir" \
      "$session_temp" \
      "$shared_temp"
    cp -R ${profiles}/. "$profile_dir/"
    printf '%s\n' trusted > "$host_config"

    repo="$build_root/regular"
    linked="$build_root/linked"
    git init -q "$repo"
    git -C "$repo" config user.name test
    git -C "$repo" config user.email test@example.com
    printf '%s\n' initial > "$repo/tracked"
    git -C "$repo" add tracked
    git -C "$repo" commit -qm initial
    git -C "$repo" worktree add -qb linked "$linked"

    run_probe() {
      local worktree="$1"
      local git_dir
      local common_dir
      git_dir="$(git -C "$worktree" rev-parse --path-format=absolute --git-dir)"
      common_dir="$(git -C "$worktree" rev-parse --path-format=absolute --git-common-dir)"

      HOME="$DOTFILES_AGENT_HOME" TMPDIR="$session_temp" nono run --silent \
        --profile dotfiles-codex \
        --allow "$worktree" \
        --allow "$git_dir" \
        --allow "$common_dir" \
        --workdir "$worktree" \
        -- \
        ${probe}/bin/nono-runtime-probe "$host_config" "$shared_temp"
    }

    run_probe "$repo"
    run_probe "$linked"

    test "$(<"$host_config")" = trusted
    test ! -e "$shared_temp/escaped"
    test "$(<"$DOTFILES_AGENT_HOME/.codex/runtime")" = runtime
    if git -C "$repo" diff --cached --quiet -- tracked; then
      exit 43
    fi
    if git -C "$linked" diff --cached --quiet -- tracked; then
      exit 44
    fi

    socket_path="$DOTFILES_HOST_HOME/.cache/herdr/herdr.sock"
    python3 - "$socket_path" <<'PY' &
    import socket
    import sys
    import time

    socket_path = sys.argv[1]
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(socket_path)
    server.listen(1)
    time.sleep(30)
    PY
    socket_server=$!
    for _ in $(seq 1 100); do
      [[ -S "$socket_path" ]] && break
      sleep 0.01
    done
    test -S "$socket_path"

    set +e
    HOME="$DOTFILES_AGENT_HOME" TMPDIR="$session_temp" nono run --silent \
      --profile dotfiles-codex \
      --allow "$repo" \
      --workdir "$repo" \
      -- \
      python3 - "$socket_path" <<'PY'
    import socket
    import sys

    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.connect(sys.argv[1])
    PY
    socket_status=$?
    set -e
    kill "$socket_server" 2>/dev/null || true
    wait "$socket_server" 2>/dev/null || true
    socket_server=
    test "$socket_status" -ne 0
  '';
}
