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

      test -z "''${DOTFILES_JOB_CONTROL_SOCKET:-}"
      test -z "''${DOTFILES_JOB_CONTROL_TOKEN:-}"

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
          attempted="$2"
          python3 - "$target" "$attempted" <<'PY'
      import os
      import sys
      import time

      if os.fork() != 0:
          raise SystemExit(0)
      os.setsid()
      if os.fork() != 0:
          os._exit(0)
      target_parent = os.path.dirname(sys.argv[1])
      for _ in range(1000):
          if os.path.isdir(target_parent):
              try:
                  with open(sys.argv[1], "w", encoding="utf-8") as target:
                      target.write("escaped\n")
              except OSError:
                  pass
              with open(sys.argv[2], "w", encoding="utf-8") as marker:
                  marker.write("attempted\n")
              break
          time.sleep(0.01)
      PY
          ;;
        stdin)
          expected="$1"
          IFS= read -r received
          test "$received" = "$expected"
          ;;
        suspend)
          printf '%s\n' READY
          IFS= read -r resume
          test "$resume" = resume
          printf '%s\n' DONE
          ;;
        logout)
          rm -f "$HOME/.codex/auth.json"
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
    cd "$repo"
    printf '%s\n' runtime-stdin | "${runtimeWrappers}/bin/codex" stdin runtime-stdin
    python3 - "${runtimeWrappers}/bin/codex" "$repo" <<'PY'
    import os
    import pty
    import select
    import signal
    import sys
    import time

    wrapper, repository = sys.argv[1:]
    child, descriptor = pty.fork()
    if child == 0:
        os.chdir(repository)
        os.execv(wrapper, [wrapper, "suspend"])

    output = bytearray()
    try:
        deadline = time.monotonic() + 20
        while b"READY" not in output and time.monotonic() < deadline:
            readable, _, _ = select.select([descriptor], [], [], 0.1)
            if readable:
                output.extend(os.read(descriptor, 4096))
        if b"READY" not in output:
            raise RuntimeError(f"suspend probe did not become ready: {output!r}")

        os.write(descriptor, b"\x1a")
        stopped = False
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            waited, status = os.waitpid(child, os.WNOHANG | os.WUNTRACED)
            if waited == child and os.WIFSTOPPED(status):
                stopped = True
                break
            time.sleep(0.05)
        if not stopped:
            raise RuntimeError("wrapper did not propagate terminal suspension")

        os.killpg(child, signal.SIGCONT)
        os.write(descriptor, b"resume\n")
        deadline = time.monotonic() + 20
        waited = 0
        status = 0
        while time.monotonic() < deadline:
            readable, _, _ = select.select([descriptor], [], [], 0.1)
            if readable:
                try:
                    output.extend(os.read(descriptor, 4096))
                except OSError:
                    pass
            waited, status = os.waitpid(child, os.WNOHANG)
            if waited == child:
                break
        if b"DONE" not in output:
            raise RuntimeError(f"suspend probe did not resume: {output!r}")
        if waited != child or not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
            raise RuntimeError(f"suspend probe exited unsuccessfully: {status}")
    finally:
        try:
            os.killpg(child, signal.SIGKILL)
        except OSError:
            pass
        try:
            os.close(descriptor)
        except OSError:
            pass
    PY

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
    recovery_ref="$(
      git for-each-ref --format='%(refname)' \
        "refs/nono/recovery/''${worktree_digest%% *}/" \
        | grep -F -- "$reflog_oid" | head -n 1
    )"
    test -n "$recovery_ref"
    test "$(git rev-parse "$recovery_ref")" = "$reflog_oid"
    old_recovery_ref="refs/nono/recovery/''${worktree_digest%% *}/1-$reflog_oid"
    git update-ref "$old_recovery_ref" "$reflog_oid"
    "${runtimeWrappers}/bin/codex" noop
    test -z "$(git for-each-ref --format='%(refname)' "$old_recovery_ref")"
    legacy_recovery_ref="refs/nono/recovery/''${worktree_digest%% *}/$reflog_oid"
    git update-ref "$legacy_recovery_ref" "$reflog_oid"
    "${runtimeWrappers}/bin/codex" noop
    test -z "$(git for-each-ref --format='%(refname)' "$legacy_recovery_ref")"
    test -n "$(
      git for-each-ref --points-at="$reflog_oid" --format='%(refname)' \
        "refs/nono/recovery/''${worktree_digest%% *}/"
    )"

    descendant_target="$repo/.git/hooks/descendant"
    descendant_attempted="$repo/descendant-attempted"
    "${runtimeWrappers}/bin/codex" descendant \
      "$descendant_target" "$descendant_attempted"
    for _ in $(seq 1 1000); do
      [[ -e "$descendant_attempted" ]] && break
      sleep 0.01
    done
    test -e "$descendant_attempted"
    if [[ -e "$descendant_target" ]]; then
      echo "detached sandbox descendant modified restored Git metadata" >&2
      exit 1
    fi
    rm -f "$descendant_attempted"

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
    recovery_metadata_parent="$HOME/.cache/nono/git-metadata"
    mkdir -p "$recovery_metadata_parent"
    recovery_metadata_parent="$(cd "$recovery_metadata_parent" && pwd -P)"
    recovery_metadata="$(mktemp -d "$recovery_metadata_parent/.nono-git-metadata.XXXXXXXXXX")"
    recovery_metadata="$(cd "$recovery_metadata" && pwd -P)"
    mv "$recovery_repo/.git" "$recovery_metadata/original-git"
    mkdir -m 0700 "$recovery_repo/.git"
    recovery_digest="$(printf '%s' "$recovery_repo" | sha256sum)"
    recovery_record="$HOME/.cache/nono/recovery/git-''${recovery_digest%% *}"
    recovery_session="$(mktemp -d "$HOME/.cache/nono/session.XXXXXXXXXX")"
    recovery_session="$(cd "$recovery_session" && pwd -P)"
    mkdir -p "$recovery_record"
    printf '%s\n' "$recovery_repo" > "$recovery_record/worktree"
    printf '%s\n' "$recovery_metadata" > "$recovery_record/metadata"
    printf '%s\n' "$recovery_metadata_parent" > "$recovery_record/metadata-parent"
    printf '%s\n' directory > "$recovery_record/kind"
    printf '%s\n' 999999999 > "$recovery_record/owner"
    printf '%s\n' "$recovery_session" > "$recovery_record/session"
    cd "$recovery_repo"
    "${runtimeWrappers}/bin/codex" noop
    test -d "$recovery_repo/.git"
    test ! -e "$recovery_record"
    test ! -e "$recovery_metadata"
    recovery_quarantine="$(
      find "$HOME/.cache/nono/recovery" -mindepth 1 -maxdepth 1 \
        -type d -name "quarantined-git-''${recovery_digest%% *}.*" -print -quit
    )"
    test -n "$recovery_quarantine"
    test -d "$recovery_quarantine"
    test ! -e "$recovery_session"

    repaired_repo="$HOME/repaired"
    create_repo "$repaired_repo"
    repaired_repo="$(cd "$repaired_repo" && pwd -P)"
    repaired_metadata="$(mktemp -d "$recovery_metadata_parent/.nono-git-metadata.XXXXXXXXXX")"
    repaired_metadata="$(cd "$repaired_metadata" && pwd -P)"
    mv "$repaired_repo/.git" "$repaired_metadata/original-git"
    mkdir -m 0700 "$repaired_repo/.git"
    repaired_digest="$(printf '%s' "$repaired_repo" | sha256sum)"
    repaired_record="$HOME/.cache/nono/recovery/git-''${repaired_digest%% *}"
    repaired_session="$(mktemp -d "$HOME/.cache/nono/session.XXXXXXXXXX")"
    repaired_session="$(cd "$repaired_session" && pwd -P)"
    mkdir -p "$repaired_record"
    printf '%s\n' "$repaired_repo" > "$repaired_record/worktree"
    printf '%s\n' "$repaired_metadata" > "$repaired_record/metadata"
    printf '%s\n' "$recovery_metadata_parent" > "$repaired_record/metadata-parent"
    printf '%s\n' directory > "$repaired_record/kind"
    printf '%s\n' 999999999 > "$repaired_record/owner"
    printf '%s\n' "$repaired_session" > "$repaired_record/session"
    printf '%s\n' manually-repaired > "$repaired_repo/.git/config"
    cd "$repaired_repo"
    set +e
    "${runtimeWrappers}/bin/codex" noop \
      > "$HOME/repaired.stdout" 2> "$HOME/repaired.stderr"
    repaired_status=$?
    set -e
    test "$repaired_status" -eq 78
    test "$(<"$repaired_repo/.git/config")" = manually-repaired
    test -d "$repaired_metadata/original-git"
    test -d "$repaired_record"
    test -d "$repaired_session"
    grep -F "refusing to replace repaired Git metadata" "$HOME/repaired.stderr"
    rm -rf "$repaired_repo/.git"
    mv "$repaired_metadata/original-git" "$repaired_repo/.git"
    rmdir "$repaired_metadata"
    rm -rf "$repaired_record" "$repaired_session"

    completed_repo="$HOME/completed"
    create_repo "$completed_repo"
    completed_repo="$(cd "$completed_repo" && pwd -P)"
    completed_metadata="$(mktemp -d "$recovery_metadata_parent/.nono-git-metadata.XXXXXXXXXX")"
    completed_metadata="$(cd "$completed_metadata" && pwd -P)"
    completed_digest="$(printf '%s' "$completed_repo" | sha256sum)"
    completed_record="$HOME/.cache/nono/recovery/completed-git-''${completed_digest%% *}.12345"
    completed_session="$(mktemp -d "$HOME/.cache/nono/session.XXXXXXXXXX")"
    completed_session="$(cd "$completed_session" && pwd -P)"
    mkdir -p "$completed_record"
    printf '%s\n' "$completed_repo" > "$completed_record/worktree"
    printf '%s\n' "$completed_metadata" > "$completed_record/metadata"
    printf '%s\n' "$recovery_metadata_parent" > "$completed_record/metadata-parent"
    printf '%s\n' directory > "$completed_record/kind"
    printf '%s\n' 999999999 > "$completed_record/owner"
    printf '%s\n' "$completed_session" > "$completed_record/session"
    cd "$repaired_repo"
    "${runtimeWrappers}/bin/codex" noop
    test -d "$completed_repo/.git"
    test ! -e "$completed_record"
    test ! -e "$completed_metadata"
    test ! -e "$completed_session"

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
    for _ in $(seq 1 1000); do
      [[ -e "$second_lock_ready" ]] && break
      sleep 0.01
    done
    test -e "$second_lock_ready"
    touch "$lock_release"
    wait "$lock_session"
    lock_session=
    wait "$second_session"
    second_session=
    test -e "$second_lock_ready"

    "${runtimeWrappers}/bin/codex-unsafe" logout
    test ! -e "$HOME/.codex/auth.json"
    test ! -e "$HOME/.local/state/nono-agent-auth/codex/.codex/auth.json"
    test "$(<"$HOME/.local/state/nono-agent-auth/codex/.synchronized-fingerprint")" = absent
    "${runtimeWrappers}/bin/codex" noop
    test ! -e "$HOME/.codex/auth.json"
    test ! -e "$HOME/.local/state/nono-agent-auth/codex/.codex/auth.json"

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
