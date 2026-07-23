{
  agentExecutables,
  agentRegistry,
  bash,
  coreutils,
  git,
  homeDirectory,
  jq,
  lib,
  nonoPackage,
  pkgsStatic,
  profiles,
  stdenv,
  symlinkJoin,
  writeShellApplication,
  writeTextFile,
}:

let
  agentNames = builtins.attrNames agentRegistry;
  executableNames = builtins.attrNames agentExecutables;
  missingAgents = builtins.filter (name: !(builtins.hasAttr name agentExecutables)) agentNames;
  unexpectedAgents = builtins.filter (name: !(builtins.hasAttr name agentRegistry)) executableNames;
  relativeExecutables = builtins.filter (
    name: !(lib.hasPrefix "/" agentExecutables.${name})
  ) agentNames;
  invalidPersistentAgents = builtins.filter (
    name: builtins.length agentRegistry.${name}.persistentFiles != 1
  ) agentNames;
  invalidPersistentPaths = builtins.filter (
    name:
    let
      paths = agentRegistry.${name}.persistentFiles;
      path = if builtins.length paths == 1 then builtins.head paths else "";
      components = lib.splitString "/" path;
    in
    path == ""
    || lib.hasPrefix "/" path
    || builtins.any (component: component == "" || component == "." || component == "..") components
  ) agentNames;
  launcherBashPath = if stdenv.hostPlatform.isLinux then lib.getExe pkgsStatic.bash else "/bin/bash";
  trustedPath =
    lib.makeBinPath [
      bash
      coreutils
      git
      jq
      nonoPackage
    ]
    + ":"
    + lib.concatStringsSep ":" (
      lib.unique (
        (map builtins.dirOf (builtins.attrValues agentExecutables))
        ++ [
          "${homeDirectory}/.nix-profile/bin"
          "/etc/profiles/per-user/${builtins.baseNameOf homeDirectory}/bin"
          "/run/current-system/sw/bin"
          "/nix/var/nix/profiles/default/bin"
          "/opt/homebrew/bin"
          "/usr/local/bin"
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ]
      )
    );
  sandboxSupervisor = writeShellApplication {
    name = "nono-agent-session";
    runtimeInputs = [
      coreutils
      git
    ];
    text = ''
      session_git="$1"
      worktree="$2"
      git_export="$3"
      session_home="$4"
      auth_relative="$5"
      auth_export="$6"
      auth_status="$7"
      shift 7

      export_git() {
        local head_mode
        local head_oid
        local head_ref
        local index_state
        local object
        local revisions="$git_export/revisions.tmp"
        local pack_temporary="$git_export/objects.pack.tmp"
        local index_temporary="$git_export/index.tmp"
        local refs_temporary="$git_export/refs.tmp"
        local git_command=(
          ${lib.getExe git}
          -c core.hooksPath=/dev/null
          -c core.fsmonitor=false
          --git-dir="$session_git"
          --work-tree="$worktree"
        )

        ${lib.getExe' coreutils "rm"} -f -- \
          "$git_export/status" \
          "$git_export/head-mode" \
          "$git_export/head-ref" \
          "$git_export/head-oid" \
          "$git_export/index-state" \
          "$git_export/index" \
          "$git_export/refs" \
          "$git_export/objects.pack" \
          "$revisions" \
          "$pack_temporary" \
          "$index_temporary" \
          "$refs_temporary"

        if head_ref="$("''${git_command[@]}" symbolic-ref -q HEAD)"; then
          head_mode=symbolic
        else
          head_mode=detached
          head_ref=
        fi
        head_oid="$("''${git_command[@]}" rev-parse --verify HEAD 2>/dev/null || true)"

        "''${git_command[@]}" rev-parse --all > "$revisions"
        if [[ -n "$head_oid" ]]; then
          printf '%s\n' "$head_oid" >> "$revisions"
        fi
        if [[ -f "$session_git/index" && ! -L "$session_git/index" ]]; then
          "''${git_command[@]}" ls-files --stage >/dev/null
          while read -r _ object _; do
            [[ -n "$object" ]] && printf '%s\n' "$object"
          done < <("''${git_command[@]}" ls-files --stage) >> "$revisions"
          ${lib.getExe' coreutils "cp"} -- "$session_git/index" "$index_temporary"
          ${lib.getExe' coreutils "mv"} -f -- "$index_temporary" "$git_export/index"
          index_state=present
        else
          index_state=absent
        fi

        if [[ -s "$revisions" ]]; then
          "''${git_command[@]}" pack-objects --stdout --revs \
            < "$revisions" > "$pack_temporary"
        else
          : > "$pack_temporary"
        fi
        "''${git_command[@]}" for-each-ref \
          --format='%(refname) %(objectname)' > "$refs_temporary"
        ${lib.getExe' coreutils "mv"} -f -- "$pack_temporary" "$git_export/objects.pack"
        ${lib.getExe' coreutils "mv"} -f -- "$refs_temporary" "$git_export/refs"
        printf '%s\n' "$head_mode" > "$git_export/head-mode"
        printf '%s\n' "$head_ref" > "$git_export/head-ref"
        printf '%s\n' "$head_oid" > "$git_export/head-oid"
        printf '%s\n' "$index_state" > "$git_export/index-state"
        printf '%s\n' ok > "$git_export/status"
        ${lib.getExe' coreutils "rm"} -f -- "$revisions"
      }

      export_auth() {
        local candidate="$session_home/$auth_relative"
        local component
        local current="$session_home"
        local status_temporary="$auth_status.tmp"
        local export_temporary="$auth_export.tmp"
        local -a components

        ${lib.getExe' coreutils "rm"} -f -- \
          "$auth_export" \
          "$auth_status" \
          "$status_temporary" \
          "$export_temporary"

        IFS=/ read -r -a components <<< "$auth_relative"
        for component in "''${components[@]}"; do
          if [[ -z "$component" || "$component" == "." || "$component" == ".." ]]; then
            printf '%s\n' invalid > "$status_temporary"
            ${lib.getExe' coreutils "mv"} -f -- "$status_temporary" "$auth_status"
            return 1
          fi
          current="$current/$component"
          if [[ -L "$current" ]]; then
            printf '%s\n' invalid > "$status_temporary"
            ${lib.getExe' coreutils "mv"} -f -- "$status_temporary" "$auth_status"
            return 1
          fi
        done

        if [[ -f "$candidate" && ! -L "$candidate" ]]; then
          ${lib.getExe' coreutils "cp"} -- "$candidate" "$export_temporary"
          ${lib.getExe' coreutils "chmod"} 0600 -- "$export_temporary"
          ${lib.getExe' coreutils "mv"} -f -- "$export_temporary" "$auth_export"
          printf '%s\n' present > "$status_temporary"
        elif [[ ! -e "$candidate" && ! -L "$candidate" ]]; then
          printf '%s\n' absent > "$status_temporary"
        else
          printf '%s\n' invalid > "$status_temporary"
          ${lib.getExe' coreutils "mv"} -f -- "$status_temporary" "$auth_status"
          return 1
        fi
        ${lib.getExe' coreutils "mv"} -f -- "$status_temporary" "$auth_status"
      }

      set +e
      "$@"
      agent_status=$?
      set -e

      set +e
      (
        set -e
        export_git
      )
      git_export_status=$?
      (
        set -e
        export_auth
      )
      auth_export_status=$?
      set -e
      if [[ "$agent_status" -ne 0 ]]; then
        exit "$agent_status"
      fi
      if [[ "$git_export_status" -ne 0 ]]; then
        exit 74
      fi
      if [[ "$auth_export_status" -ne 0 ]]; then
        exit 75
      fi
    '';
  };

  mkNormalWrapper =
    name:
    let
      definition = agentRegistry.${name};
      profile = definition.profile;
      realExecutable = agentExecutables.${name};
      persistentFile = builtins.head definition.persistentFiles;
      createWritableDirectories = lib.concatMapStrings (relativePath: ''
        ${lib.getExe' coreutils "mkdir"} -p -m 0700 -- \
          "$session_home"/${lib.escapeShellArg relativePath}
      '') definition.writableDirectories;
      createWritableFiles = lib.concatMapStrings (relativePath: ''
        writable_file="$session_home"/${lib.escapeShellArg relativePath}
        ${lib.getExe' coreutils "mkdir"} -p -m 0700 -- \
          "$(${lib.getExe' coreutils "dirname"} "$writable_file")"
        ${lib.getExe' coreutils "touch"} -- "$writable_file"
        ${lib.getExe' coreutils "chmod"} 0600 -- "$writable_file"
      '') definition.writableFiles;
      stagePaths = lib.concatMapStrings (
        stagedPath:
        let
          source = "${homeDirectory}/${stagedPath.source}";
          stageCommand =
            if stagedPath.copy or false then
              ''
                ${lib.getExe' coreutils "cp"} -L -- "$staged_source" "$staged_target"
                ${lib.getExe' coreutils "chmod"} 0400 -- "$staged_target"
              ''
            else
              ''
                ${lib.getExe' coreutils "ln"} -s -- "$staged_source" "$staged_target"
              '';
        in
        ''
          staged_source=${lib.escapeShellArg source}
          staged_target="$session_home"/${lib.escapeShellArg stagedPath.target}
          if [[ -e "$staged_source" || -L "$staged_source" ]]; then
            ${lib.getExe' coreutils "mkdir"} -p -- "$(${lib.getExe' coreutils "dirname"} "$staged_target")"
            ${stageCommand}
          fi
        ''
      ) definition.stagedPaths;
      stageFilteredJsonPaths = lib.concatMapStrings (filteredPath: ''
        filtered_source="$configured_home"/${lib.escapeShellArg filteredPath.source}
        filtered_target="$session_home"/${lib.escapeShellArg filteredPath.target}
        if [[ -f "$filtered_source" && ! -L "$filtered_source" ]]; then
          ${lib.getExe' coreutils "mkdir"} -p -- \
            "$(${lib.getExe' coreutils "dirname"} "$filtered_target")"
          ${lib.getExe jq} ${lib.escapeShellArg filteredPath.filter} \
            "$filtered_source" > "$filtered_target"
        fi
      '') definition.filteredJsonPaths;
      sshSocketSetup = lib.optionalString stdenv.hostPlatform.isDarwin ''
        if [[ -z "$inherited_ssh_auth_sock" ]]; then
          inherited_ssh_auth_sock=/nonexistent/nono-ssh-agent.sock
        elif [[ "$inherited_ssh_auth_sock" != /* ]]; then
          echo "error: refusing relative SSH_AUTH_SOCK: $inherited_ssh_auth_sock" >&2
          exit 78
        fi
        export SSH_AUTH_SOCK="$inherited_ssh_auth_sock"
      '';
    in
    writeTextFile {
      inherit name;
      destination = "/bin/${name}";
      executable = true;
      text = ''
        #!${launcherBashPath} -p
        set -euo pipefail

        readonly profile_path=${lib.escapeShellArg "${profiles}/${profile}.json"}
        readonly real_executable=${lib.escapeShellArg realExecutable}
        readonly configured_home=${lib.escapeShellArg homeDirectory}
        readonly persistent_file=${lib.escapeShellArg persistentFile}
        inherited_ssh_auth_sock="''${SSH_AUTH_SOCK:-}"
        export PATH=${lib.escapeShellArg trustedPath}

        while IFS= read -r environment_variable; do
          case "$environment_variable" in
            BASH_ENV | ENV | GIT_* | LD_* | DYLD_* | NONO_* | SSH_* | TMPDIR | TMP | TEMP | \
              DOTFILES_AGENT_HOME | DOTFILES_HOST_HOME | XDG_CACHE_HOME | XDG_CONFIG_HOME | \
              XDG_DATA_HOME | XDG_RUNTIME_DIR | XDG_STATE_HOME)
              unset "$environment_variable"
              ;;
          esac
        done < <(compgen -e)

        ${sshSocketSetup}

        if [[ ! -r "$profile_path" ]]; then
          echo "error: missing Nono profile: $profile_path" >&2
          exit 78
        fi
        if [[ ! -x "$real_executable" ]]; then
          echo "error: real ${name} executable is unavailable: $real_executable" >&2
          exit 127
        fi
        if [[ "''${HOME:-}" != "$configured_home" ]]; then
          echo "error: refusing unexpected HOME: ''${HOME:-<unset>}" >&2
          exit 78
        fi
        if ! configured_home_canonical="$(cd "$configured_home" && pwd -P)"; then
          echo "error: configured home is unavailable: $configured_home" >&2
          exit 78
        fi
        readonly configured_home_canonical

        readonly current_directory="$(pwd -P)"
        if ! worktree_root="$(${lib.getExe git} -C "$current_directory" rev-parse --show-toplevel 2>/dev/null)" \
          || [[ -z "$worktree_root" ]]; then
          echo "error: ${name} must be launched inside a Git worktree" >&2
          exit 78
        fi
        readonly worktree_root="$(cd "$worktree_root" && pwd -P)"
        if [[ "$worktree_root" == "/" \
          || "$configured_home_canonical" == "$worktree_root" \
          || "$configured_home_canonical" == "$worktree_root/"* ]]; then
          echo "error: refusing to sandbox a Git worktree that contains HOME: $worktree_root" >&2
          exit 78
        fi

        held_locks=()
        session_root=
        metadata_root=
        dotgit_kind=
        dotgit_restored=0
        nono_invoked=0
        cleanup_failed=0
        recovery_required=0
        command_status=0

        acquire_lock() {
          local lock_path="$1"
          local attempt
          local owner
          local stale
          ${lib.getExe' coreutils "mkdir"} -p -m 0700 -- \
            "$(${lib.getExe' coreutils "dirname"} "$lock_path")"
          for ((attempt = 0; attempt < 300; attempt++)); do
            if ${lib.getExe' coreutils "mkdir"} -m 0700 -- "$lock_path" 2>/dev/null; then
              printf '%s\n' "$$" > "$lock_path/pid"
              held_locks+=("$lock_path")
              return 0
            fi
            owner=
            if [[ -f "$lock_path/pid" && ! -L "$lock_path/pid" ]]; then
              IFS= read -r owner < "$lock_path/pid" || owner=
            fi
            if [[ "$owner" =~ ^[0-9]+$ ]] && ! kill -0 "$owner" 2>/dev/null; then
              stale="$lock_path.stale.$$"
              if ${lib.getExe' coreutils "mv"} -- "$lock_path" "$stale" 2>/dev/null; then
                ${lib.getExe' coreutils "rm"} -rf -- "$stale"
                continue
              fi
            fi
            ${lib.getExe' coreutils "sleep"} 0.1
          done
          echo "error: timed out waiting for lock: $lock_path" >&2
          return 1
        }

        release_lock() {
          local lock_path="$1"
          local held_lock
          local owner=
          local -a remaining_locks=()
          if [[ -f "$lock_path/pid" && ! -L "$lock_path/pid" ]]; then
            IFS= read -r owner < "$lock_path/pid" || owner=
          fi
          if [[ "$owner" == "$$" ]]; then
            ${lib.getExe' coreutils "rm"} -f -- "$lock_path/pid"
            ${lib.getExe' coreutils "rmdir"} -- "$lock_path" 2>/dev/null || true
          fi
          for held_lock in "''${held_locks[@]}"; do
            if [[ "$held_lock" != "$lock_path" ]]; then
              remaining_locks+=("$held_lock")
            fi
          done
          held_locks=()
          if [[ "''${#remaining_locks[@]}" -gt 0 ]]; then
            held_locks=("''${remaining_locks[@]}")
          fi
        }

        release_all_locks() {
          local lock_path
          while [[ "''${#held_locks[@]}" -gt 0 ]]; do
            lock_path="''${held_locks[$((''${#held_locks[@]} - 1))]}"
            release_lock "$lock_path"
          done
        }

        fingerprint() {
          local target="$1"
          local digest
          if [[ ! -e "$target" && ! -L "$target" ]]; then
            printf '%s\n' absent
          elif [[ -f "$target" && ! -L "$target" ]]; then
            digest="$(${lib.getExe' coreutils "sha256sum"} -- "$target")"
            printf 'sha256:%s\n' "''${digest%% *}"
          else
            printf '%s\n' invalid
          fi
        }

        restore_dotgit() {
          if [[ -z "$dotgit_kind" || "$dotgit_restored" -eq 1 ]]; then
            return 0
          fi
          if [[ "$(cd "$worktree_root" && pwd -P)" != "$worktree_root" ]]; then
            return 1
          fi
          ${lib.getExe' coreutils "rm"} -rf -- "$worktree_root/.git" || return 1
          if [[ "$dotgit_kind" == directory ]]; then
            ${lib.getExe' coreutils "mv"} -- \
              "$metadata_root/original-git" "$worktree_root/.git" || return 1
          else
            ${lib.getExe' coreutils "mv"} -- \
              "$metadata_root/original-dotgit" "$worktree_root/.git" || return 1
          fi
          dotgit_restored=1
        }

        safe_real_git() {
          GIT_CONFIG_GLOBAL=/dev/null \
            GIT_CONFIG_NOSYSTEM=1 \
            ${lib.getExe git} \
            -c core.hooksPath=/dev/null \
            -c core.fsmonitor=false \
            --git-dir="$real_git_directory" \
            --work-tree="$worktree_root" \
            "$@"
        }

        lookup_ref() {
          local refs_file="$1"
          local requested_ref="$2"
          local candidate_ref
          local candidate_oid
          while read -r candidate_ref candidate_oid; do
            if [[ "$candidate_ref" == "$requested_ref" ]]; then
              printf '%s\n' "$candidate_oid"
              return 0
            fi
          done < "$refs_file"
          return 1
        }

        sync_git() {
          local current_head_mode
          local current_head_oid
          local current_head_ref
          local current_index_fingerprint
          local export_head_mode
          local export_head_oid
          local export_head_ref
          local export_index_state
          local exported_ref
          local exported_ref_oid
          local extra_field
          local index_temporary="$real_index.tmp.$$"
          local required_export
          local refs_changed=0
          local refs_transaction="$session_root/refs-transaction"
          local start_ref
          local start_ref_oid

          for required_export in \
            "$git_export/status" \
            "$git_export/head-mode" \
            "$git_export/head-ref" \
            "$git_export/head-oid" \
            "$git_export/index-state" \
            "$git_export/refs" \
            "$git_export/objects.pack"; do
            [[ -f "$required_export" && ! -L "$required_export" ]] || return 1
          done
          [[ "$(<"$git_export/status")" == ok ]] || return 1
          IFS= read -r export_head_mode < "$git_export/head-mode"
          IFS= read -r export_head_ref < "$git_export/head-ref"
          IFS= read -r export_head_oid < "$git_export/head-oid"
          IFS= read -r export_index_state < "$git_export/index-state"

          [[ "$export_head_mode" == "$start_head_mode" ]] || return 1
          [[ "$export_head_ref" == "$start_head_ref" ]] || return 1
          [[ "$export_index_state" == present || "$export_index_state" == absent ]] || return 1
          if [[ -n "$export_head_oid" && ! "$export_head_oid" =~ ^[0-9a-fA-F]{40,64}$ ]]; then
            return 1
          fi
          while read -r exported_ref exported_ref_oid extra_field; do
            [[ -n "$exported_ref" && -n "$exported_ref_oid" && -z "$extra_field" ]] \
              || return 1
            safe_real_git check-ref-format "$exported_ref" || return 1
            [[ "$exported_ref_oid" =~ ^[0-9a-fA-F]{40,64}$ ]] || return 1
          done < "$git_export/refs"

          if current_head_ref="$(safe_real_git symbolic-ref -q HEAD 2>/dev/null)"; then
            current_head_mode=symbolic
          else
            current_head_mode=detached
            current_head_ref=
          fi
          current_head_oid="$(safe_real_git rev-parse --verify HEAD 2>/dev/null || true)"
          current_index_fingerprint="$(fingerprint "$real_index")"
          [[ "$current_head_mode" == "$start_head_mode" ]] || return 1
          [[ "$current_head_ref" == "$start_head_ref" ]] || return 1
          [[ "$current_head_oid" == "$start_head_oid" ]] || return 1
          [[ "$current_index_fingerprint" == "$start_index_fingerprint" ]] || return 1

          if [[ -s "$git_export/objects.pack" ]]; then
            safe_real_git index-pack --stdin < "$git_export/objects.pack" >/dev/null || return 1
          fi
          if [[ -n "$export_head_oid" ]]; then
            safe_real_git cat-file -e "$export_head_oid^{commit}" || return 1
          fi
          if [[ "$export_index_state" == present ]]; then
            [[ -f "$git_export/index" && ! -L "$git_export/index" ]] || return 1
            GIT_INDEX_FILE="$git_export/index" safe_real_git ls-files --stage >/dev/null || return 1
          fi

          : > "$refs_transaction" || return 1
          while read -r start_ref start_ref_oid; do
            if exported_ref_oid="$(lookup_ref "$git_export/refs" "$start_ref")"; then
              safe_real_git cat-file -e "$exported_ref_oid^{object}" || return 1
              if [[ "$exported_ref_oid" != "$start_ref_oid" ]]; then
                printf 'update %s %s %s\n' \
                  "$start_ref" "$exported_ref_oid" "$start_ref_oid" \
                  >> "$refs_transaction" || return 1
                refs_changed=1
              fi
            else
              printf 'delete %s %s\n' \
                "$start_ref" "$start_ref_oid" >> "$refs_transaction" || return 1
              refs_changed=1
            fi
          done < "$start_refs"
          while read -r exported_ref exported_ref_oid; do
            if ! lookup_ref "$start_refs" "$exported_ref" >/dev/null; then
              safe_real_git cat-file -e "$exported_ref_oid^{object}" || return 1
              printf 'create %s %s\n' \
                "$exported_ref" "$exported_ref_oid" >> "$refs_transaction" || return 1
              refs_changed=1
            fi
          done < "$git_export/refs"
          if [[ "$refs_changed" -eq 1 ]]; then
            safe_real_git update-ref --stdin < "$refs_transaction" || return 1
          fi
          if [[ "$start_head_mode" == detached && "$export_head_oid" != "$start_head_oid" ]]; then
            safe_real_git update-ref --no-deref HEAD "$export_head_oid" "$start_head_oid" \
              || return 1
          fi

          if [[ "$export_index_state" == present ]]; then
            ${lib.getExe' coreutils "cp"} -- "$git_export/index" "$index_temporary" || return 1
            ${lib.getExe' coreutils "chmod"} 0600 -- "$index_temporary" || return 1
            ${lib.getExe' coreutils "mv"} -f -- "$index_temporary" "$real_index" || return 1
          else
            ${lib.getExe' coreutils "rm"} -f -- "$real_index" || return 1
          fi
        }

        persist_auth() {
          local auth_state
          local current_fingerprint
          local current_legacy_fingerprint
          local export_fingerprint
          local legacy_temporary="$legacy_source.tmp.$$"
          local persistent_temporary="$persistent_target.tmp.$$"

          [[ -f "$auth_status" && ! -L "$auth_status" ]] || return 1
          IFS= read -r auth_state < "$auth_status"
          [[ "$auth_state" == present || "$auth_state" == absent ]] || return 1

          if ! acquire_lock "$auth_lock"; then
            return 1
          fi
          current_fingerprint="$(fingerprint "$persistent_target")"
          if [[ "$legacy_available" -eq 1 ]]; then
            current_legacy_fingerprint="$(fingerprint "$legacy_source")"
          else
            current_legacy_fingerprint=unavailable
          fi
          if [[ "$auth_state" == present ]]; then
            if [[ ! -f "$auth_export" || -L "$auth_export" ]]; then
              release_lock "$auth_lock"
              return 1
            fi
            export_fingerprint="$(fingerprint "$auth_export")"
          else
            export_fingerprint=absent
          fi

          if [[ "$export_fingerprint" == "$auth_baseline_fingerprint" ]]; then
            release_lock "$auth_lock"
            return 0
          fi
          if [[ "$current_fingerprint" != "$auth_baseline_fingerprint" \
            && "$current_fingerprint" != "$export_fingerprint" ]] \
            || [[ "$legacy_available" -eq 1 \
              && "$current_legacy_fingerprint" != "$legacy_baseline_fingerprint" \
              && "$current_legacy_fingerprint" != "$export_fingerprint" ]]; then
            if [[ "$auth_state" == present ]]; then
              ${lib.getExe' coreutils "cp"} -- "$auth_export" "$session_root/auth-conflict"
            fi
            recovery_required=1
            echo "error: ${name} authentication changed in concurrent sessions; preserving recovery state" >&2
            release_lock "$auth_lock"
            return 1
          fi

          if [[ "$auth_state" == present ]]; then
            if ! ${lib.getExe' coreutils "cp"} -- "$auth_export" "$persistent_temporary" \
              || ! ${lib.getExe' coreutils "chmod"} 0600 -- "$persistent_temporary"; then
              release_lock "$auth_lock"
              return 1
            fi
            if [[ "$legacy_available" -eq 1 ]]; then
              if ! ${lib.getExe' coreutils "cp"} -- "$auth_export" "$legacy_temporary" \
                || ! ${lib.getExe' coreutils "chmod"} 0600 -- "$legacy_temporary" \
                || ! ${lib.getExe' coreutils "mv"} -f -- "$legacy_temporary" "$legacy_source"; then
                release_lock "$auth_lock"
                return 1
              fi
            fi
            if ! ${lib.getExe' coreutils "mv"} -f -- "$persistent_temporary" "$persistent_target"; then
              release_lock "$auth_lock"
              return 1
            fi
          else
            if [[ "$legacy_available" -eq 1 ]] \
              && ! ${lib.getExe' coreutils "rm"} -f -- "$legacy_source"; then
              release_lock "$auth_lock"
              return 1
            fi
            if ! ${lib.getExe' coreutils "rm"} -f -- "$persistent_target"; then
              release_lock "$auth_lock"
              return 1
            fi
          fi
          release_lock "$auth_lock"
        }

        cleanup() {
          local original_status=$?
          trap - EXIT HUP INT TERM
          set +e

          if [[ "$nono_invoked" -eq 1 ]]; then
            if ! sync_git; then
              cleanup_failed=1
              recovery_required=1
              echo "error: unable to reconcile isolated Git state" >&2
            fi
            if ! persist_auth; then
              cleanup_failed=1
              recovery_required=1
              echo "error: unable to persist ${name} authentication safely" >&2
            fi
          fi
          if ! restore_dotgit; then
            cleanup_failed=1
            recovery_required=1
            echo "error: unable to restore Git metadata for $worktree_root" >&2
          fi
          if [[ -n "$metadata_root" && -d "$metadata_root" \
            && (-z "$dotgit_kind" || "$dotgit_restored" -eq 1) ]]; then
            if ! ${lib.getExe' coreutils "rm"} -rf -- "$metadata_root"; then
              cleanup_failed=1
              recovery_required=1
              echo "error: unable to remove Git metadata staging at $metadata_root" >&2
            fi
          fi
          release_all_locks

          if [[ -n "$session_root" ]]; then
            if [[ "$recovery_required" -eq 1 ]]; then
              echo "error: recovery state preserved at $session_root" >&2
            else
              if ! ${lib.getExe' coreutils "rm"} -rf -- "$session_root"; then
                cleanup_failed=1
                recovery_required=1
                echo "error: unable to remove session state at $session_root" >&2
              fi
            fi
          fi
          if [[ -n "$metadata_root" && -d "$metadata_root" ]]; then
            echo "error: Git recovery state preserved at $metadata_root" >&2
          fi
          if [[ "$original_status" -eq 0 && "$cleanup_failed" -ne 0 ]]; then
            exit 74
          fi
          exit "$original_status"
        }
        trap cleanup EXIT HUP INT TERM

        readonly session_temp_root="$configured_home/.cache/nono"
        readonly locks_root="$session_temp_root/locks"
        ${lib.getExe' coreutils "mkdir"} -p -m 0700 -- "$session_temp_root" "$locks_root"
        session_temp_root_canonical="$(${lib.getExe' coreutils "realpath"} -e -- "$session_temp_root")"
        if [[ "$session_temp_root_canonical" != "$configured_home_canonical/"* \
          || -L "$session_temp_root" \
          || -L "$locks_root" ]]; then
          echo "error: refusing unsafe Nono state root: $session_temp_root" >&2
          exit 78
        fi

        worktree_digest="$(
          printf '%s' "$worktree_root" | ${lib.getExe' coreutils "sha256sum"}
        )"
        readonly git_lock="$locks_root/git-''${worktree_digest%% *}"
        readonly auth_lock="$locks_root/auth-${name}"
        acquire_lock "$git_lock"

        if ! git_directory="$(${lib.getExe git} -C "$current_directory" \
          rev-parse --path-format=absolute --git-dir 2>/dev/null)" \
          || ! common_directory="$(${lib.getExe git} -C "$current_directory" \
            rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
          echo "error: unable to resolve Git metadata for $worktree_root" >&2
          exit 78
        fi
        git_directory="$(cd "$git_directory" && pwd -P)"
        common_directory="$(cd "$common_directory" && pwd -P)"

        if start_head_ref="$(${lib.getExe git} -C "$current_directory" symbolic-ref -q HEAD 2>/dev/null)"; then
          start_head_mode=symbolic
        else
          start_head_mode=detached
          start_head_ref=
        fi
        start_head_oid="$(${lib.getExe git} -C "$current_directory" rev-parse --verify HEAD 2>/dev/null || true)"
        object_format="$(${lib.getExe git} -C "$current_directory" rev-parse --show-object-format)"
        real_index="$(${lib.getExe git} -C "$current_directory" rev-parse --path-format=absolute --git-path index)"

        session_root="$(${lib.getExe' coreutils "mktemp"} \
          -d "$session_temp_root/session.XXXXXXXXXX")"
        readonly session_home="$session_root/home"
        readonly session_temp="$session_root/tmp"
        readonly session_git="$session_root/git"
        readonly export_root="$session_root/export"
        readonly git_export="$export_root/git"
        readonly auth_export="$export_root/auth"
        readonly auth_status="$export_root/auth-status"
        readonly start_refs="$session_root/start-refs"
        readonly persistent_state_root="$configured_home/.local/state/nono-agent-auth/${name}"
        readonly persistent_target="$persistent_state_root/$persistent_file"
        ${lib.getExe' coreutils "mkdir"} -m 0700 -- \
          "$session_home" \
          "$session_temp" \
          "$session_home/.run" \
          "$export_root" \
          "$git_export"
        ${lib.getExe' coreutils "touch"} -- "$auth_export" "$auth_status"
        ${lib.getExe' coreutils "chmod"} 0600 -- "$auth_export" "$auth_status"

        worktree_parent="$(${lib.getExe' coreutils "dirname"} "$worktree_root")"
        metadata_parent="$worktree_parent"
        while enclosing_worktree="$(${lib.getExe git} -C "$metadata_parent" \
          rev-parse --show-toplevel 2>/dev/null)"; do
          enclosing_worktree="$(cd "$enclosing_worktree" && pwd -P)"
          next_metadata_parent="$(${lib.getExe' coreutils "dirname"} "$enclosing_worktree")"
          if [[ "$next_metadata_parent" == "$metadata_parent" ]]; then
            break
          fi
          metadata_parent="$next_metadata_parent"
        done
        readonly worktree_parent
        readonly metadata_parent
        metadata_root="$(${lib.getExe' coreutils "mktemp"} \
          -d "$metadata_parent/.nono-git-metadata.XXXXXXXXXX")"
        git_device="$(${lib.getExe' coreutils "stat"} -c %d -- "$worktree_root/.git")"
        metadata_device="$(${lib.getExe' coreutils "stat"} -c %d -- "$metadata_root")"
        if [[ "$git_device" != "$metadata_device" ]]; then
          echo "error: Git metadata isolation requires a writable directory on the worktree filesystem" >&2
          exit 78
        fi
        if [[ -d "$worktree_root/.git" && ! -L "$worktree_root/.git" ]]; then
          if [[ "$git_directory" != "$common_directory" \
            || "$git_directory" != "$worktree_root/.git" ]]; then
            echo "error: unsupported in-tree Git metadata layout" >&2
            exit 78
          fi
          ${lib.getExe' coreutils "mv"} -- "$worktree_root/.git" "$metadata_root/original-git"
          dotgit_kind=directory
          real_git_directory="$metadata_root/original-git"
          real_common_directory="$metadata_root/original-git"
          real_index="$metadata_root/original-git/index"
        elif [[ -f "$worktree_root/.git" && ! -L "$worktree_root/.git" ]]; then
          ${lib.getExe' coreutils "mv"} -- \
            "$worktree_root/.git" "$metadata_root/original-dotgit"
          dotgit_kind=file
          real_git_directory="$git_directory"
          real_common_directory="$common_directory"
        else
          echo "error: refusing unsupported .git entry: $worktree_root/.git" >&2
          exit 78
        fi
        readonly real_git_directory
        readonly real_common_directory
        readonly real_index
        readonly real_objects_directory="$real_common_directory/objects"
        readonly start_index_fingerprint="$(fingerprint "$real_index")"
        ${lib.getExe git} --git-dir="$real_git_directory" for-each-ref \
          --format='%(refname) %(objectname)' > "$start_refs"

        ${lib.getExe git} init -q --bare --object-format="$object_format" "$session_git"
        if [[ -f "$real_common_directory/config" && ! -L "$real_common_directory/config" ]]; then
          ${lib.getExe' coreutils "cp"} -- "$real_common_directory/config" "$session_git/config"
        fi
        ${lib.getExe git} config --file "$session_git/config" core.bare false
        ${lib.getExe git} config --file "$session_git/config" core.worktree "$worktree_root"
        ${lib.getExe git} config --file "$session_git/config" core.hooksPath "$session_git/hooks"
        ${lib.getExe git} config --file "$session_git/config" core.fsmonitor false
        if [[ -f "$real_git_directory/config.worktree" \
          && ! -L "$real_git_directory/config.worktree" ]]; then
          ${lib.getExe' coreutils "cp"} -- \
            "$real_git_directory/config.worktree" "$session_git/config.worktree"
        fi
        ${lib.getExe' coreutils "mkdir"} -p -- "$session_git/objects/info"
        printf '%s\n' "$real_objects_directory" > "$session_git/objects/info/alternates"
        while read -r reference object; do
          [[ -n "$object" && -n "$reference" ]] \
            && ${lib.getExe git} --git-dir="$session_git" update-ref "$reference" "$object"
        done < "$start_refs"
        if [[ "$start_head_mode" == symbolic ]]; then
          ${lib.getExe git} --git-dir="$session_git" symbolic-ref HEAD "$start_head_ref"
        elif [[ -n "$start_head_oid" ]]; then
          ${lib.getExe git} --git-dir="$session_git" update-ref --no-deref HEAD "$start_head_oid"
        fi
        if [[ -f "$real_index" && ! -L "$real_index" ]]; then
          ${lib.getExe' coreutils "cp"} -- "$real_index" "$session_git/index"
        fi
        for relative_info_file in exclude attributes; do
          real_info_file="$real_common_directory/info/$relative_info_file"
          if [[ -f "$real_info_file" && ! -L "$real_info_file" ]]; then
            ${lib.getExe' coreutils "cp"} -- \
              "$real_info_file" "$session_git/info/$relative_info_file"
          fi
        done
        printf 'gitdir: %s\n' "$session_git" > "$session_root/dotgit-pointer"
        ${lib.getExe' coreutils "mv"} -- "$session_root/dotgit-pointer" "$worktree_root/.git"

        ${createWritableDirectories}
        ${createWritableFiles}
        ${stagePaths}
        ${stageFilteredJsonPaths}

        if [[ -L "$persistent_state_root" ]]; then
          echo "error: refusing symlinked persistent state root: $persistent_state_root" >&2
          exit 78
        fi
        ${lib.getExe' coreutils "mkdir"} -p -m 0700 -- \
          "$persistent_state_root" \
          "$(${lib.getExe' coreutils "dirname"} "$persistent_target")"
        readonly legacy_source="$configured_home/$persistent_file"
        legacy_available=0
        legacy_parent="$(${lib.getExe' coreutils "dirname"} "$legacy_source")"
        if [[ -d "$legacy_parent" && ! -L "$legacy_parent" ]]; then
          legacy_parent_canonical="$(${lib.getExe' coreutils "realpath"} -e -- "$legacy_parent")"
          if [[ "$legacy_parent_canonical" == "$configured_home_canonical/"* ]]; then
            legacy_available=1
          fi
        fi

        acquire_lock "$auth_lock"
        persistent_fingerprint="$(fingerprint "$persistent_target")"
        if [[ "$persistent_fingerprint" == invalid ]]; then
          echo "error: refusing unsafe persistent authentication file: $persistent_target" >&2
          exit 78
        fi
        if [[ "$legacy_available" -eq 1 ]]; then
          legacy_fingerprint="$(fingerprint "$legacy_source")"
          if [[ "$legacy_fingerprint" == invalid ]]; then
            echo "error: refusing unsafe legacy authentication file: $legacy_source" >&2
            exit 78
          fi
          if [[ "$legacy_fingerprint" != absent \
            && ("$persistent_fingerprint" == absent \
              || "$legacy_source" -nt "$persistent_target") ]]; then
            legacy_temporary="$persistent_target.migrate.$$"
            ${lib.getExe' coreutils "cp"} -- "$legacy_source" "$legacy_temporary"
            ${lib.getExe' coreutils "chmod"} 0600 -- "$legacy_temporary"
            ${lib.getExe' coreutils "mv"} -f -- "$legacy_temporary" "$persistent_target"
          fi
        fi
        release_lock "$auth_lock"

        auth_baseline_fingerprint="$(fingerprint "$persistent_target")"
        if [[ "$auth_baseline_fingerprint" == invalid ]]; then
          echo "error: refusing unsafe persistent authentication file: $persistent_target" >&2
          exit 78
        fi
        if [[ "$legacy_available" -eq 1 ]]; then
          legacy_baseline_fingerprint="$(fingerprint "$legacy_source")"
        else
          legacy_baseline_fingerprint=unavailable
        fi
        if [[ "$auth_baseline_fingerprint" != absent ]]; then
          session_auth="$session_home/$persistent_file"
          ${lib.getExe' coreutils "mkdir"} -p -m 0700 -- \
            "$(${lib.getExe' coreutils "dirname"} "$session_auth")"
          ${lib.getExe' coreutils "cp"} -- "$persistent_target" "$session_auth"
          ${lib.getExe' coreutils "chmod"} 0600 -- "$session_auth"
        fi

        export DOTFILES_AGENT_HOME="$session_home"
        export DOTFILES_HOST_HOME="$configured_home"
        export TMPDIR="$session_temp"
        export NONO_NO_PACK_UPDATE_HINTS=1
        export NONO_NO_UPDATE_CHECK=1
        export XDG_CONFIG_HOME="$session_home/.config"
        export HOME="$session_home"

        nono_arguments=(
          run
          --profile "$profile_path"
          --allow "$worktree_root"
          --allow "$session_git"
          --read "$real_objects_directory"
          --allow "$export_root"
          --workdir "$current_directory"
          --
          ${lib.escapeShellArg (lib.getExe sandboxSupervisor)}
          "$session_git"
          "$worktree_root"
          "$git_export"
          "$session_home"
          "$persistent_file"
          "$auth_export"
          "$auth_status"
          "$real_executable"
          ${lib.escapeShellArgs definition.clientArguments}
          "$@"
        )

        nono_invoked=1
        set +e
        ${lib.escapeShellArg (lib.getExe nonoPackage)} "''${nono_arguments[@]}"
        command_status=$?
        set -e
        exit "$command_status"
      '';
    };

  mkUnsafeWrapper =
    name:
    let
      realExecutable = agentExecutables.${name};
    in
    writeShellApplication {
      name = "${name}-unsafe";
      text = ''
        real_executable=${lib.escapeShellArg realExecutable}

        if [[ ! -x "$real_executable" ]]; then
          echo "error: real ${name} executable is unavailable: $real_executable" >&2
          exit 127
        fi

        echo "warning: launching ${name} UNSANDBOXED" >&2
        exec "$real_executable" "$@"
      '';
    };
in
assert lib.assertMsg (
  missingAgents == [ ]
) "agentExecutables is missing: ${lib.concatStringsSep ", " missingAgents}";
assert lib.assertMsg (
  unexpectedAgents == [ ]
) "agentExecutables has unexpected entries: ${lib.concatStringsSep ", " unexpectedAgents}";
assert lib.assertMsg (
  relativeExecutables == [ ]
) "agent executable paths must be absolute: ${lib.concatStringsSep ", " relativeExecutables}";
assert lib.assertMsg (invalidPersistentAgents == [ ])
  "agents must declare exactly one persistent authentication file: ${lib.concatStringsSep ", " invalidPersistentAgents}";
assert lib.assertMsg (invalidPersistentPaths == [ ])
  "agents must declare safe relative authentication paths: ${lib.concatStringsSep ", " invalidPersistentPaths}";
symlinkJoin {
  name = "nono-agent-wrappers";
  paths = builtins.concatMap (name: [
    (mkNormalWrapper name)
    (mkUnsafeWrapper name)
  ]) agentNames;
}
