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
        git-state)
          git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/other
          git switch -qc runtime-switch
          printf '%s\n' switched >> tracked
          git add tracked
          git commit -qm switched
          ;;
        reflog-only)
          output="$1"
          starting_branch="$(git symbolic-ref --short HEAD)"
          git switch -qc disposable
          printf '%s\n' disposable >> tracked
          git add tracked
          git commit -qm disposable
          disposable_oid="$(git rev-parse HEAD)"
          git switch -q "$starting_branch"
          git branch -qD disposable
          printf '%s\n' "$disposable_oid" > "$output"
          ;;
        descendant)
          target="$1"
          if [[ "$(uname -s)" == Linux ]]; then
            python3 - "$target" <<'PY'
      import os
      import sys
      import time

      if os.fork() != 0:
          raise SystemExit(0)
      os.setsid()
      if os.fork() != 0:
          os._exit(0)
      git_directory = os.path.dirname(os.path.dirname(sys.argv[1]))
      for _ in range(1000):
          if os.path.isdir(git_directory):
              with open(sys.argv[1], "w", encoding="utf-8") as target:
                  target.write("escaped\n")
              break
          time.sleep(0.01)
      PY
          else
            (
            (
                descendant_git="$(dirname "$(dirname "$target")")"
                for _ in $(seq 1 1000); do
                  if [[ -d "$descendant_git" ]]; then
                    printf '%s\n' escaped > "$target"
                    exit
                  fi
                  sleep 0.01
                done
              ) </dev/null >/dev/null 2>&1 &
            ) &
          fi
          ;;
        noop)
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
    pkgs.findutils
    pkgs.git
    pkgs.gnugrep
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

    git -C "$repo" update-ref refs/remotes/origin/main HEAD
    git -C "$repo" update-ref refs/remotes/origin/other HEAD
    git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    main_oid="$(git -C "$repo" rev-parse refs/remotes/origin/main)"
    cd "$repo"
    "${runtimeWrappers}/bin/codex" git-state
    test "$(git symbolic-ref refs/remotes/origin/HEAD)" = refs/remotes/origin/other
    test "$(git rev-parse refs/remotes/origin/main)" = "$main_oid"
    test "$(git symbolic-ref HEAD)" = refs/heads/runtime-switch
    test "$(git log -1 --format=%s)" = switched

    reflog_oid_file="$repo/reflog-oid"
    "${runtimeWrappers}/bin/codex" reflog-only "$reflog_oid_file"
    reflog_oid="$(<"$reflog_oid_file")"
    canonical_repo="$(cd "$repo" && pwd -P)"
    worktree_digest="$(printf '%s' "$canonical_repo" | sha256sum)"
    recovery_ref="refs/nono/recovery/''${worktree_digest%% *}/$reflog_oid"
    test "$(git rev-parse "$recovery_ref")" = "$reflog_oid"

    descendant_target="$repo/.git/hooks/descendant"
    "${runtimeWrappers}/bin/codex" descendant "$descendant_target"
    sleep 0.2
    test ! -e "$descendant_target"

    linked="$HOME/linked"
    git -C "$repo" worktree add -qb linked "$linked"
    cd "$linked"
    "${runtimeWrappers}/bin/codex" linked
    test "$(git log -1 --format=%s)" = linked
    test -f "$linked/.git"
    cd "$repo"
    set +e
    "${runtimeWrappers}/bin/codex" noop \
      > "$HOME/main-linked.stdout" 2> "$HOME/main-linked.stderr"
    main_linked_status=$?
    set -e
    test "$main_linked_status" -eq 78
    git -C "$linked" status --short >/dev/null
    grep -F "main worktree with linked worktrees" "$HOME/main-linked.stderr"

    unsupported_repo="$HOME/unsupported"
    create_repo "$unsupported_repo"
    printf '%s\n' blocked > "$unsupported_repo/.git/MERGE_HEAD"
    cd "$unsupported_repo"
    set +e
    "${runtimeWrappers}/bin/codex" noop \
      > "$HOME/unsupported.stdout" 2> "$HOME/unsupported.stderr"
    unsupported_status=$?
    set -e
    test "$unsupported_status" -eq 78
    test -d "$unsupported_repo/.git"
    grep -F "unsupported Git state" "$HOME/unsupported.stderr"

    recovery_repo="$HOME/recovery"
    create_repo "$recovery_repo"
    recovery_repo="$(cd "$recovery_repo" && pwd -P)"
    recovery_metadata="$(mktemp -d "$HOME/.nono-git-metadata.XXXXXXXXXX")"
    recovery_metadata="$(cd "$recovery_metadata" && pwd -P)"
    mv "$recovery_repo/.git" "$recovery_metadata/original-git"
    recovery_digest="$(printf '%s' "$recovery_repo" | sha256sum)"
    recovery_record="$HOME/.cache/nono/recovery/git-''${recovery_digest%% *}"
    recovery_session="$(mktemp -d "$HOME/.cache/nono/session.XXXXXXXXXX")"
    recovery_session="$(cd "$recovery_session" && pwd -P)"
    mkdir -p "$recovery_record"
    printf '%s\n' "$recovery_repo" > "$recovery_record/worktree"
    printf '%s\n' "$recovery_metadata" > "$recovery_record/metadata"
    printf '%s\n' directory > "$recovery_record/kind"
    printf '%s\n' 999999999 > "$recovery_record/owner"
    printf '%s\n' "$recovery_session" > "$recovery_record/session"
    cd "$recovery_repo"
    "${runtimeWrappers}/bin/codex" noop
    test -d "$recovery_repo/.git"
    test ! -e "$recovery_record"
    test ! -e "$recovery_metadata"
    test ! -e "$recovery_session"

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

    linked_two="$HOME/linked-two"
    git -C "$repo" worktree add -qb linked-two "$linked_two"
    lock_ready="$linked/lock-ready"
    lock_release="$linked/lock-release"
    second_lock_ready="$linked_two/second-lock-ready"
    (
      cd "$linked"
      "${runtimeWrappers}/bin/codex" lock "$lock_ready" "$lock_release"
    ) &
    lock_session=$!
    for _ in $(seq 1 1000); do
      [[ -e "$lock_ready" ]] && break
      sleep 0.01
    done
    test -e "$lock_ready"
    (
      cd "$linked_two"
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
