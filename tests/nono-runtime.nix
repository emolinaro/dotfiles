{
  agentRegistry,
  nonoPackage,
  pkgs,
  profiles,
  wrapperModule,
}:

let
  configuredHome = "/tmp/nono-production-wrapper-runtime";
  runtimeRegistry = {
    codex = agentRegistry.codex // {
      clientArguments = [ ];
    };
    pi = agentRegistry.pi;
  };
  runtimeProbe = pkgs.writeShellApplication {
    name = "nono-runtime-probe";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.git
      pkgs.jq
      pkgs.python3
    ];
    text = ''
      mode="$1"
      shift

      case "$mode" in
        standard)
          host_config="$1"
          shared_temp="$2"
          unrelated_secret="$3"
          socket_path="$4"
          victim_directory="$5"

          test "$(git config user.name)" = "Runtime Test"
          test "$(git config user.email)" = "runtime@example.com"
          test "$(jq -r .token "$HOME/.codex/auth.json")" = legacy
          if printf '%s\n' compromised > "$host_config"; then
            exit 41
          fi
          if touch "$shared_temp/escaped"; then
            exit 42
          fi
          if cat "$unrelated_secret" >/dev/null; then
            exit 43
          fi
          if python3 - "$socket_path" <<'PY'
      import socket
      import sys

      client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
      client.connect(sys.argv[1])
      PY
          then
            exit 44
          fi

          common_directory="$(git rev-parse --path-format=absolute --git-common-dir)"
          mkdir -p "$common_directory/modules/example/hooks"
          printf '%s\n' malicious > "$common_directory/modules/example/hooks/pre-push"
          rm -rf "$common_directory/info"
          ln -s "$victim_directory" "$common_directory/info"

          printf '%s\n' changed >> tracked
          git add tracked
          git commit -qm runtime
          git branch sandbox-created
          printf '%s\n' '{"token":"refreshed"}' > "$HOME/.codex/auth.json"
          ;;
        linked)
          test "$(jq -r .token "$HOME/.codex/auth.json")" = refreshed
          printf '%s\n' linked >> tracked
          git add tracked
          git commit -qm linked
          ;;
        credential)
          expected="$1"
          replacement="$2"
          ready="$3"
          release="$4"
          test "$(jq -r .token "$HOME/.codex/auth.json")" = "$expected"
          printf '%s\n' ready > "$ready"
          if [[ "$release" != "-" ]]; then
            for _ in $(seq 1 1000); do
              [[ -e "$release" ]] && break
              sleep 0.01
            done
            test -e "$release"
          fi
          printf '{"token":"%s"}\n' "$replacement" > "$HOME/.codex/auth.json"
          ;;
        lock)
          ready="$1"
          release="$2"
          printf '%s\n' ready > "$ready"
          if [[ "$release" != "-" ]]; then
            for _ in $(seq 1 1000); do
              [[ -e "$release" ]] && break
              sleep 0.01
            done
            test -e "$release"
          fi
          ;;
        pi-symlink)
          host_codex_directory="$1"
          rm -rf "$HOME/.pi/agent"
          ln -s "$host_codex_directory" "$HOME/.pi/agent"
          ;;
        *)
          exit 64
          ;;
      esac
    '';
  };
  runtimeWrappers = pkgs.callPackage wrapperModule {
    agentExecutables = {
      codex = "${runtimeProbe}/bin/nono-runtime-probe";
      pi = "${runtimeProbe}/bin/nono-runtime-probe";
    };
    agentRegistry = runtimeRegistry;
    homeDirectory = configuredHome;
    inherit nonoPackage profiles;
  };
in
pkgs.writeShellApplication {
  name = "nono-runtime-test";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.git
    pkgs.jq
    pkgs.python3
  ];
  text = ''
    if [[ -e ${configuredHome} ]]; then
      echo "runtime test home already exists: ${configuredHome}" >&2
      exit 73
    fi

    socket_server=
    first_session=
    second_session=
    lock_session=
    cleanup() {
      status=$?
      trap - EXIT HUP INT TERM
      for process in "$first_session" "$second_session" "$lock_session" "$socket_server"; do
        if [[ -n "$process" ]]; then
          kill "$process" 2>/dev/null || true
          wait "$process" 2>/dev/null || true
        fi
      done
      rm -rf -- ${configuredHome}
      exit "$status"
    }
    trap cleanup EXIT HUP INT TERM

    export HOME=${configuredHome}
    mkdir -p \
      "$HOME/.codex" \
      "$HOME/.config/git" \
      "$HOME/.config/nono/profiles" \
      "$HOME/unrelated" \
      "$HOME/victim"
    cp -R ${profiles}/. "$HOME/.config/nono/profiles/"
    printf '%s\n' trusted > "$HOME/.codex/config.toml"
    printf '%s\n' '{"token":"legacy"}' > "$HOME/.codex/auth.json"
    printf '%s\n' private > "$HOME/unrelated/secret"
    printf '%s\n' victim > "$HOME/victim/attributes"
    cat > "$HOME/.config/git/config" <<'EOF'
    [user]
      name = Runtime Test
      email = runtime@example.com
    [rerere]
      enabled = true
    EOF

    create_repo() {
      local repository="$1"
      git init -q "$repository"
      printf '%s\n' initial > "$repository/tracked"
      git -C "$repository" add tracked
      git -C "$repository" commit -qm initial
    }

    repo="$HOME/regular"
    create_repo "$repo"
    mkdir -p "$repo/.git/hooks" "$repo/.git/info" "$repo/.git/modules/example/hooks"
    printf '%s\n' trusted > "$repo/.git/hooks/pre-push"
    printf '%s\n' trusted > "$repo/.git/info/attributes"
    printf '%s\n' trusted > "$repo/.git/modules/example/hooks/pre-push"

    socket_path="$HOME/control.sock"
    python3 - "$socket_path" <<'PY' &
    import socket
    import sys
    import time

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(sys.argv[1])
    server.listen(4)
    time.sleep(30)
    PY
    socket_server=$!
    for _ in $(seq 1 1000); do
      [[ -S "$socket_path" ]] && break
      sleep 0.01
    done
    test -S "$socket_path"

    shared_temp="$HOME/shared-temp"
    mkdir -p "$shared_temp"
    cd "$repo"
    "${runtimeWrappers}/bin/codex" \
      standard \
      "$HOME/.codex/config.toml" \
      "$shared_temp" \
      "$HOME/unrelated/secret" \
      "$socket_path" \
      "$HOME/victim"

    test "$(git log -1 --format=%s)" = runtime
    test "$(git log -1 --format=%s sandbox-created)" = runtime
    test "$(git config user.name)" = "Runtime Test"
    test "$(<"$repo/.git/hooks/pre-push")" = trusted
    test "$(<"$repo/.git/info/attributes")" = trusted
    test "$(<"$repo/.git/modules/example/hooks/pre-push")" = trusted
    test "$(<"$HOME/victim/attributes")" = victim
    test "$(jq -r .token "$HOME/.local/state/nono-agent-auth/codex/.codex/auth.json")" = refreshed
    test -d "$repo/.git"
    test -z "$(find "$HOME/.cache/nono" -mindepth 1 -maxdepth 1 -name 'session.*' -print -quit)"

    linked="$HOME/linked"
    git -C "$repo" worktree add -qb linked "$linked"
    cd "$linked"
    "${runtimeWrappers}/bin/codex" linked
    test "$(git log -1 --format=%s)" = linked
    test -f "$linked/.git"

    first_repo="$HOME/first"
    second_repo="$HOME/second"
    create_repo "$first_repo"
    create_repo "$second_repo"
    first_ready="$first_repo/ready"
    first_release="$first_repo/release"
    second_ready="$second_repo/ready"

    (
      cd "$first_repo"
      "${runtimeWrappers}/bin/codex" credential refreshed stale "$first_ready" "$first_release"
    ) &
    first_session=$!
    for _ in $(seq 1 1000); do
      [[ -e "$first_ready" ]] && break
      sleep 0.01
    done
    test -e "$first_ready"

    (
      cd "$second_repo"
      "${runtimeWrappers}/bin/codex" credential refreshed newer "$second_ready" -
    )
    test -e "$second_ready"
    touch "$first_release"
    set +e
    wait "$first_session"
    first_status=$?
    set -e
    first_session=
    test "$first_status" -ne 0
    test "$(jq -r .token "$HOME/.local/state/nono-agent-auth/codex/.codex/auth.json")" = newer
    test "$(jq -r .token "$HOME/.codex/auth.json")" = newer

    lock_ready="$repo/lock-ready"
    lock_release="$repo/lock-release"
    second_lock_ready="$repo/second-lock-ready"
    (
      cd "$repo"
      "${runtimeWrappers}/bin/codex" lock "$lock_ready" "$lock_release"
    ) &
    lock_session=$!
    for _ in $(seq 1 1000); do
      [[ -e "$lock_ready" ]] && break
      sleep 0.01
    done
    test -e "$lock_ready"
    (
      cd "$repo"
      "${runtimeWrappers}/bin/codex" lock "$second_lock_ready" -
    ) &
    second_session=$!
    sleep 0.2
    test ! -e "$second_lock_ready"
    touch "$lock_release"
    wait "$lock_session"
    lock_session=
    wait "$second_session"
    second_session=
    test -e "$second_lock_ready"

    pi_repo="$HOME/pi-repo"
    create_repo "$pi_repo"
    printf '%s\n' '{"token":"host-codex-secret"}' > "$HOME/.codex/auth.json"
    cd "$pi_repo"
    set +e
    "${runtimeWrappers}/bin/pi" pi-symlink "$HOME/.codex"
    pi_status=$?
    set -e
    test "$pi_status" -ne 0
    pi_persistent="$HOME/.local/state/nono-agent-auth/pi/.pi/agent/auth.json"
    if [[ -e "$pi_persistent" ]]; then
      test "$(jq -r .token "$pi_persistent")" != host-codex-secret
    fi
    test -z "$(find "$HOME" \
      -mindepth 1 -maxdepth 1 -name '.nono-git-metadata.*' -print -quit)"
  '';
}
