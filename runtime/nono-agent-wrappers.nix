{
  agentExecutables,
  agentRegistry,
  bash,
  coreutils,
  findutils,
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
          "${homeDirectory}/.cache/axi-tools/bin"
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
  processSupervisorSource = builtins.toFile "nono-process-supervisor.c" ''
    #define _POSIX_C_SOURCE 200809L

    #include <errno.h>
    #include <fcntl.h>
    #include <signal.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <sys/socket.h>
    #include <sys/stat.h>
    #include <sys/types.h>
    #include <sys/un.h>
    #include <sys/wait.h>
    #include <time.h>
    #include <unistd.h>

    #ifdef __linux__
    #include <sys/prctl.h>
    #endif

    static volatile sig_atomic_t received_signal = 0;

    static void receive_signal(int signal_number) {
      received_signal = signal_number;
    }

    static void pause_briefly(void) {
      struct timespec delay = { .tv_sec = 0, .tv_nsec = 20000000 };
      while (nanosleep(&delay, &delay) < 0 && errno == EINTR) {
      }
    }

    static int signal_adopted_children(int signal_number) {
      #ifdef __linux__
      char path[128];
      FILE *children;
      long child;
      int found = 0;

      snprintf(path, sizeof(path), "/proc/self/task/%ld/children", (long)getpid());
      children = fopen(path, "r");
      if (children == NULL) {
        return 0;
      }
      while (fscanf(children, "%ld", &child) == 1) {
        found = 1;
        kill((pid_t)child, signal_number);
      }
      fclose(children);
      return found;
      #else
      (void)signal_number;
      return 0;
      #endif
    }

    static void reap_adopted_children(void) {
      while (waitpid(-1, NULL, WNOHANG) > 0) {
      }
    }

    static void terminate_group(pid_t group) {
      int attempt;
      kill(-group, SIGCONT);
      kill(-group, SIGTERM);
      for (attempt = 0; attempt < 25; attempt++) {
        int adopted = signal_adopted_children(SIGTERM);
        reap_adopted_children();
        if (kill(-group, 0) < 0 && errno == ESRCH && !adopted) {
          return;
        }
        pause_briefly();
      }
      kill(-group, SIGKILL);
      for (attempt = 0; attempt < 25; attempt++) {
        int adopted = signal_adopted_children(SIGKILL);
        reap_adopted_children();
        if (kill(-group, 0) < 0 && errno == ESRCH && !adopted) {
          return;
        }
        pause_briefly();
      }
    }

    static int transfer_all(
      int descriptor,
      void *buffer,
      size_t length,
      int writing
    ) {
      char *position = buffer;
      size_t remaining = length;

      while (remaining > 0) {
        ssize_t result = writing
          ? write(descriptor, position, remaining)
          : read(descriptor, position, remaining);
        if (result > 0) {
          position += result;
          remaining -= (size_t)result;
          continue;
        }
        if (result < 0 && errno == EINTR) {
          continue;
        }
        if (
          result < 0
          && (errno == EAGAIN || errno == EWOULDBLOCK)
        ) {
          pause_briefly();
          continue;
        }
        return -1;
      }
      return 0;
    }

    static int generate_token(char token[33]) {
      unsigned char random_bytes[16];
      int random_descriptor;
      size_t index;

      random_descriptor = open("/dev/urandom", O_RDONLY);
      if (random_descriptor < 0
          || transfer_all(
            random_descriptor,
            random_bytes,
            sizeof(random_bytes),
            0
          ) < 0
          || close(random_descriptor) < 0) {
        return -1;
      }
      for (index = 0; index < sizeof(random_bytes); index++) {
        if (snprintf(
              token + (index * 2),
              3,
              "%02x",
              random_bytes[index]
            ) != 2) {
          return -1;
        }
      }
      token[32] = '\0';
      return 0;
    }

    static int create_listener(const char *path) {
      struct sockaddr_un address = { 0 };
      struct stat existing;
      int descriptor;
      int flags;
      size_t length = strlen(path);

      if (path[0] != '/' || length >= sizeof(address.sun_path)) {
        return -1;
      }
      if (lstat(path, &existing) == 0 || errno != ENOENT) {
        return -1;
      }
      descriptor = socket(AF_UNIX, SOCK_STREAM, 0);
      if (descriptor < 0) {
        return -1;
      }
      address.sun_family = AF_UNIX;
      memcpy(address.sun_path, path, length + 1);
      if (bind(
            descriptor,
            (struct sockaddr *)&address,
            sizeof(address)
          ) < 0
          || chmod(path, 0600) < 0
          || listen(descriptor, 4) < 0) {
        close(descriptor);
        unlink(path);
        return -1;
      }
      flags = fcntl(descriptor, F_GETFL);
      if (flags < 0
          || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) < 0) {
        close(descriptor);
        unlink(path);
        return -1;
      }
      return descriptor;
    }

    static int connect_control(const char *path, const char *token) {
      struct sockaddr_un address = { 0 };
      int descriptor;
      size_t length = strlen(path);

      if (path[0] != '/'
          || length >= sizeof(address.sun_path)
          || strlen(token) != 32) {
        return -1;
      }
      descriptor = socket(AF_UNIX, SOCK_STREAM, 0);
      if (descriptor < 0) {
        return -1;
      }
      address.sun_family = AF_UNIX;
      memcpy(address.sun_path, path, length + 1);
      while (connect(
          descriptor,
          (struct sockaddr *)&address,
          sizeof(address)
        ) < 0) {
        if (errno != EINTR) {
          close(descriptor);
          return -1;
        }
      }
      if (transfer_all(descriptor, (void *)token, 32, 1) < 0) {
        close(descriptor);
        return -1;
      }
      return descriptor;
    }

    int main(int argc, char **argv) {
      pid_t child;
      pid_t original_parent;
      pid_t original_foreground_group = -1;
      pid_t waited;
      char ready_byte = 1;
      int ready_pipe[2];
      int status = 0;
      int child_exited = 0;
      int parent_disappeared = 0;
      int terminal_input = 0;
      int command_index = 1;
      int pid_descriptor;
      int outer_supervisor = 0;
      int listener_descriptor = -1;
      int control_descriptor = -1;
      int control_flags;
      int control_authenticated = 0;
      int accepted_descriptor;
      const char *control_path = NULL;
      const char *control_token_value;
      char control_token[33] = { 0 };
      char authentication[32] = { 0 };
      char control_byte;
      size_t authentication_received = 0;
      ssize_t control_result;
      struct sigaction action = { 0 };

      if (argc < 2) {
        return 64;
      }
      if (argc >= 6
          && strcmp(argv[1], "--pid-file") == 0
          && strcmp(argv[3], "--job-socket") == 0) {
        pid_descriptor = open(
          argv[2],
          O_WRONLY | O_CREAT | O_EXCL,
          0600
        );
        if (pid_descriptor < 0) {
          return 73;
        }
        if (dprintf(pid_descriptor, "%ld\n", (long)getpid()) < 0
            || fsync(pid_descriptor) < 0
            || close(pid_descriptor) < 0) {
          return 73;
        }
        control_path = argv[4];
        if (generate_token(control_token) < 0) {
          return 71;
        }
        listener_descriptor = create_listener(control_path);
        if (listener_descriptor < 0) {
          return 71;
        }
        outer_supervisor = 1;
        command_index = 5;
      }
      if (!outer_supervisor) {
        control_path = getenv("DOTFILES_JOB_CONTROL_SOCKET");
        control_token_value = getenv("DOTFILES_JOB_CONTROL_TOKEN");
        if ((control_path == NULL) != (control_token_value == NULL)) {
          return 64;
        }
        if (control_path != NULL) {
          control_descriptor = connect_control(
            control_path,
            control_token_value
          );
          if (control_descriptor < 0) {
            return 71;
          }
          control_authenticated = 1;
        }
      }
      if (command_index >= argc) {
        return 64;
      }

      original_parent = getppid();
      #ifdef __linux__
      if (prctl(PR_SET_CHILD_SUBREAPER, 1) < 0) {
        return 71;
      }
      #endif
      action.sa_handler = receive_signal;
      sigemptyset(&action.sa_mask);
      sigaction(SIGINT, &action, NULL);
      sigaction(SIGHUP, &action, NULL);
      sigaction(SIGTERM, &action, NULL);
      signal(SIGPIPE, SIG_IGN);
      signal(SIGTTOU, SIG_IGN);

      if (isatty(STDIN_FILENO)) {
        original_foreground_group = tcgetpgrp(STDIN_FILENO);
        terminal_input = original_foreground_group >= 0;
      }
      if (pipe(ready_pipe) < 0) {
        return 71;
      }

      child = fork();
      if (child < 0) {
        close(ready_pipe[0]);
        close(ready_pipe[1]);
        return 71;
      }
      if (child == 0) {
        ssize_t ready_result;
        close(ready_pipe[1]);
        if (outer_supervisor) {
          close(listener_descriptor);
          if (setenv(
                "DOTFILES_JOB_CONTROL_SOCKET",
                control_path,
                1
              ) < 0
              || setenv(
                "DOTFILES_JOB_CONTROL_TOKEN",
                control_token,
                1
              ) < 0) {
            _exit(71);
          }
        } else if (control_descriptor >= 0) {
          close(control_descriptor);
          unsetenv("DOTFILES_JOB_CONTROL_SOCKET");
          unsetenv("DOTFILES_JOB_CONTROL_TOKEN");
        }
        signal(SIGINT, SIG_DFL);
        signal(SIGHUP, SIG_DFL);
        signal(SIGPIPE, SIG_DFL);
        signal(SIGTERM, SIG_DFL);
        signal(SIGTTOU, SIG_DFL);
        if (setpgid(0, 0) < 0) {
          _exit(71);
        }
        do {
          ready_result = read(ready_pipe[0], &ready_byte, 1);
        } while (ready_result < 0 && errno == EINTR);
        close(ready_pipe[0]);
        if (ready_result != 1) {
          _exit(71);
        }
        execvp(argv[command_index], &argv[command_index]);
        _exit(errno == ENOENT ? 127 : 126);
      }

      close(ready_pipe[0]);
      if (setpgid(child, child) < 0 && errno != EACCES && errno != ESRCH) {
        close(ready_pipe[1]);
        kill(child, SIGKILL);
        waitpid(child, NULL, 0);
        return 71;
      }
      if (terminal_input && tcsetpgrp(STDIN_FILENO, child) < 0) {
        close(ready_pipe[1]);
        kill(child, SIGKILL);
        waitpid(child, NULL, 0);
        return 71;
      }
      while (write(ready_pipe[1], &ready_byte, 1) < 0) {
        if (errno != EINTR) {
          close(ready_pipe[1]);
          kill(child, SIGKILL);
          waitpid(child, NULL, 0);
          if (terminal_input) {
            tcsetpgrp(STDIN_FILENO, original_foreground_group);
          }
          return 71;
        }
      }
      close(ready_pipe[1]);

      for (;;) {
        if (outer_supervisor
            && control_descriptor < 0
            && listener_descriptor >= 0) {
          accepted_descriptor = accept(listener_descriptor, NULL, NULL);
          if (accepted_descriptor >= 0) {
            control_flags = fcntl(accepted_descriptor, F_GETFL);
            if (control_flags < 0
                || fcntl(
                  accepted_descriptor,
                  F_SETFL,
                  control_flags | O_NONBLOCK
                ) < 0) {
              close(accepted_descriptor);
            } else {
              control_descriptor = accepted_descriptor;
              authentication_received = 0;
            }
          } else if (errno != EAGAIN
              && errno != EWOULDBLOCK
              && errno != EINTR) {
            received_signal = SIGTERM;
            break;
          }
        }
        if (outer_supervisor
            && control_descriptor >= 0
            && !control_authenticated) {
          control_result = read(
            control_descriptor,
            authentication + authentication_received,
            sizeof(authentication) - authentication_received
          );
          if (control_result > 0) {
            authentication_received += (size_t)control_result;
            if (authentication_received == sizeof(authentication)) {
              if (memcmp(
                    authentication,
                    control_token,
                    sizeof(authentication)
                  ) != 0) {
                close(control_descriptor);
                control_descriptor = -1;
                authentication_received = 0;
              } else {
                control_authenticated = 1;
                close(listener_descriptor);
                listener_descriptor = -1;
                unlink(control_path);
              }
            }
          } else if (control_result == 0) {
            close(control_descriptor);
            control_descriptor = -1;
            authentication_received = 0;
          } else if (errno != EAGAIN
              && errno != EWOULDBLOCK
              && errno != EINTR) {
            close(control_descriptor);
            control_descriptor = -1;
            authentication_received = 0;
          }
        }
        if (outer_supervisor && control_authenticated) {
          control_result = read(
            control_descriptor,
            &control_byte,
            sizeof(control_byte)
          );
          if (control_result == 1) {
            if (control_byte != 'S') {
              received_signal = SIGTERM;
              break;
            }
            if (terminal_input) {
              tcsetpgrp(STDIN_FILENO, original_foreground_group);
            }
            kill(-child, SIGSTOP);
            kill(0, SIGSTOP);
            if (terminal_input) {
              tcsetpgrp(STDIN_FILENO, child);
            }
            kill(-child, SIGCONT);
            control_byte = 'C';
            if (transfer_all(
                  control_descriptor,
                  &control_byte,
                  sizeof(control_byte),
                  1
                ) < 0) {
              received_signal = SIGTERM;
              break;
            }
            continue;
          }
          if (control_result == 0) {
            close(control_descriptor);
            control_descriptor = -1;
            control_authenticated = 0;
          } else if (control_result < 0
              && errno != EAGAIN
              && errno != EWOULDBLOCK
              && errno != EINTR) {
            received_signal = SIGTERM;
            break;
          }
        }
        waited = waitpid(child, &status, WNOHANG | WUNTRACED | WCONTINUED);
        if (waited == child) {
          if (WIFSTOPPED(status)) {
            if (terminal_input) {
              tcsetpgrp(STDIN_FILENO, original_foreground_group);
            }
            if (control_descriptor >= 0 && !outer_supervisor) {
              control_byte = 'S';
              if (transfer_all(
                    control_descriptor,
                    &control_byte,
                    sizeof(control_byte),
                    1
                  ) < 0
                  || transfer_all(
                    control_descriptor,
                    &control_byte,
                    sizeof(control_byte),
                    0
                  ) < 0
                  || control_byte != 'C') {
                received_signal = SIGTERM;
                break;
              }
            } else {
              kill(0, SIGSTOP);
            }
            if (terminal_input) {
              tcsetpgrp(STDIN_FILENO, child);
            }
            kill(-child, SIGCONT);
            continue;
          }
          if (WIFCONTINUED(status)) {
            continue;
          }
          child_exited = 1;
          break;
        }
        if (waited < 0 && errno != EINTR) {
          break;
        }
        if (received_signal != 0) {
          break;
        }
        if (getppid() != original_parent || kill(original_parent, 0) < 0) {
          parent_disappeared = 1;
          break;
        }
        pause_briefly();
      }

      terminate_group(child);
      if (!child_exited) {
        while (waitpid(child, &status, 0) < 0 && errno == EINTR) {
        }
      }
      if (terminal_input) {
        tcsetpgrp(STDIN_FILENO, original_foreground_group);
      }
      if (control_descriptor >= 0) {
        close(control_descriptor);
      }
      if (listener_descriptor >= 0) {
        close(listener_descriptor);
      }
      if (outer_supervisor && control_path != NULL) {
        unlink(control_path);
      }

      if (parent_disappeared) {
        return 143;
      }
      if (received_signal != 0) {
        return 128 + received_signal;
      }
      if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
      }
      if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
      }
      return 70;
    }
  '';
  processSupervisor = stdenv.mkDerivation {
    pname = "nono-process-supervisor";
    version = "1";
    dontUnpack = true;
    buildPhase = ''
      $CC -std=c11 -Wall -Wextra -Werror \
        ${processSupervisorSource} -o nono-process-supervisor
    '';
    installPhase = ''
      mkdir -p "$out/bin"
      cp nono-process-supervisor "$out/bin/"
    '';
  };
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
        local reflogs_temporary="$git_export/reflog-oids.tmp"
        local index_temporary="$git_export/index.tmp"
        local refs_temporary="$git_export/refs.tmp"
        local git_command=(
          ${lib.getExe git}
          -c core.hooksPath=/dev/null
          -c core.fsmonitor=false
          --git-dir="$session_git"
          --work-tree="$worktree"
        )
        local marker
        local marker_path

        if [[ "$("''${git_command[@]}" rev-parse --is-shallow-repository)" == true ]] \
          || [[ "$("''${git_command[@]}" config --bool core.sparseCheckout || true)" == true ]] \
          || [[ "$("''${git_command[@]}" config --bool index.sparse || true)" == true ]] \
          || [[ "$("''${git_command[@]}" config --bool core.splitIndex || true)" == true ]] \
          || [[ -n "$("''${git_command[@]}" rev-parse --shared-index-path 2>/dev/null || true)" ]]; then
          return 1
        fi
        for marker in \
          MERGE_HEAD \
          CHERRY_PICK_HEAD \
          REVERT_HEAD \
          BISECT_LOG \
          rebase-apply \
          rebase-merge \
          sequencer; do
          marker_path="$("''${git_command[@]}" rev-parse --git-path "$marker")"
          if [[ -e "$marker_path" || -L "$marker_path" ]]; then
            return 1
          fi
        done
        while read -r mode _; do
          if [[ "$mode" == 160000 ]]; then
            return 1
          fi
        done < <("''${git_command[@]}" ls-files --stage)

        ${lib.getExe' coreutils "rm"} -f -- \
          "$git_export/status" \
          "$git_export/head-mode" \
          "$git_export/head-ref" \
          "$git_export/head-oid" \
          "$git_export/index-state" \
          "$git_export/index" \
          "$git_export/refs" \
          "$git_export/reflog-oids" \
          "$git_export/objects.pack" \
          "$revisions" \
          "$pack_temporary" \
          "$reflogs_temporary" \
          "$index_temporary" \
          "$refs_temporary"

        if head_ref="$("''${git_command[@]}" symbolic-ref -q HEAD)"; then
          head_mode=symbolic
        else
          head_mode=detached
          head_ref=
        fi
        head_oid="$("''${git_command[@]}" rev-parse --verify HEAD 2>/dev/null || true)"

        "''${git_command[@]}" rev-list --reflog --all > "$revisions"
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
        "''${git_command[@]}" reflog --all --format=%H \
          | ${lib.getExe' coreutils "sort"} -u > "$reflogs_temporary"
        ${lib.getExe' coreutils "cat"} -- "$reflogs_temporary" >> "$revisions"

        if [[ -s "$revisions" ]]; then
          "''${git_command[@]}" pack-objects --local --stdout --revs \
            < "$revisions" > "$pack_temporary"
        else
          : > "$pack_temporary"
        fi
        "''${git_command[@]}" for-each-ref \
          --format='%(refname)%09%(objectname)%09%(symref)' > "$refs_temporary"
        ${lib.getExe' coreutils "mv"} -f -- "$pack_temporary" "$git_export/objects.pack"
        ${lib.getExe' coreutils "mv"} -f -- "$refs_temporary" "$git_export/refs"
        ${lib.getExe' coreutils "mv"} -f -- "$reflogs_temporary" "$git_export/reflog-oids"
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
      ${lib.getExe' processSupervisor "nono-process-supervisor"} \
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

  mkNonoWrapper =
    name:
    let
      definition = agentRegistry.${name};
      profile = definition.profile;
      realExecutable = agentExecutables.${name};
      persistentFile = builtins.head definition.persistentFiles;
      createWritableDirectories = lib.concatMapStrings (relativePath: ''
        ${lib.getExe' coreutils "mkdir"} -p -- \
          "$session_home"/${lib.escapeShellArg relativePath}
        ${lib.getExe' coreutils "chmod"} 0700 -- \
          "$session_home"/${lib.escapeShellArg relativePath}
      '') definition.writableDirectories;
      createWritableFiles = lib.concatMapStrings (relativePath: ''
        writable_file="$session_home"/${lib.escapeShellArg relativePath}
        ${lib.getExe' coreutils "mkdir"} -p -- \
          "$(${lib.getExe' coreutils "dirname"} "$writable_file")"
        ${lib.getExe' coreutils "chmod"} 0700 -- \
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
                if [[ -f "$staged_target" || -L "$staged_target" ]]; then
                  ${lib.getExe' coreutils "rm"} -f -- "$staged_target"
                fi
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
      name = "${name}-nono";
      destination = "/bin/${name}-nono";
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
              XDG_DATA_HOME | XDG_RUNTIME_DIR | XDG_STATE_HOME | DOTFILES_JOB_CONTROL_SOCKET | \
              DOTFILES_JOB_CONTROL_TOKEN | DOTFILES_WORKTREE_ROOT)
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
        readonly session_temp_root="$configured_home_canonical/.cache/nono"
        readonly locks_root="$session_temp_root/locks"
        readonly recovery_root="$session_temp_root/recovery"
        ${lib.getExe' coreutils "mkdir"} -p -- \
          "$session_temp_root" \
          "$locks_root" \
          "$recovery_root"
        ${lib.getExe' coreutils "chmod"} 0700 -- \
          "$session_temp_root" \
          "$locks_root" \
          "$recovery_root"
        session_temp_root_canonical="$(${lib.getExe' coreutils "realpath"} -e -- "$session_temp_root")"
        if [[ "$session_temp_root_canonical" != "$session_temp_root" \
          || -L "$session_temp_root" \
          || -L "$locks_root" \
          || -L "$recovery_root" ]]; then
          echo "error: refusing unsafe Nono state root: $session_temp_root" >&2
          exit 78
        fi

        held_locks=()
        session_root=
        metadata_root=
        nono_state_root=
        recovery_record=
        recovery_temporary=
        completed_recovery_record=
        dotgit_kind=
        dotgit_restored=0
        nono_invoked=0
        cleanup_failed=0
        recovery_required=0
        command_status=0

        acquire_lock() {
          local lock_path="$1"
          local attempt
          local lock_parent
          local owner
          local stale
          lock_parent="$(${lib.getExe' coreutils "dirname"} "$lock_path")"
          ${lib.getExe' coreutils "mkdir"} -p -- "$lock_parent"
          ${lib.getExe' coreutils "chmod"} 0700 -- "$lock_parent"
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

        recover_pending_git() {
          local actual_pointer
          local completed
          local expected_digest
          local expected_pointer
          local kind
          local metadata_parent
          local metadata
          local original
          local owner
          local pid_file
          local quarantine
          local record
          local record_kind
          local recovery_lock
          local recovery_status
          local recorded_worktree
          local required_record
          local session

          recover_record_locked() {
            for pid_file in owner runtime; do
              owner=
              if [[ -f "$record/$pid_file" && ! -L "$record/$pid_file" ]]; then
                IFS= read -r owner < "$record/$pid_file" || owner=
              fi
              if [[ "$owner" =~ ^[0-9]+$ ]] && kill -0 "$owner" 2>/dev/null; then
                if [[ "$record_kind" == completed ]]; then
                  return 2
                fi
                echo "error: Git isolation session is still active for $recorded_worktree" >&2
                return 1
              fi
            done
            IFS= read -r metadata < "$record/metadata" || return 1
            IFS= read -r metadata_parent < "$record/metadata-parent" || return 1
            IFS= read -r kind < "$record/kind" || return 1
            IFS= read -r session < "$record/session" || return 1
            if [[ "$metadata_parent" == / \
              || "$metadata_parent" != /* \
              || -L "$metadata_parent" \
              || "$(${lib.getExe' coreutils "realpath"} -m -- "$metadata_parent")" \
                != "$metadata_parent" \
              || "$metadata" != "$metadata_parent"/.nono-git-metadata.* \
              || -L "$metadata" \
              || ( -e "$metadata" && ! -d "$metadata" ) ]]; then
              echo "error: invalid Git recovery staging path: $metadata" >&2
              return 1
            fi
            if [[ "$record_kind" == pending || -e "$metadata" ]]; then
              if [[ ! -d "$metadata_parent" \
                || "$(${lib.getExe' coreutils "realpath"} -e -- "$metadata_parent")" \
                  != "$metadata_parent" ]]; then
                echo "error: unavailable Git recovery staging parent: $metadata_parent" >&2
                return 1
              fi
            fi
            case "$metadata" in
              "$recorded_worktree" | "$recorded_worktree"/*)
                echo "error: unsafe Git recovery staging path: $metadata" >&2
                return 1
                ;;
            esac
            if [[ "$session" != "$session_temp_root"/session.* \
              || -L "$session" \
              || ( -e "$session" && ! -d "$session" ) ]]; then
              echo "error: invalid Git recovery session path: $session" >&2
              return 1
            fi

            if [[ "$record_kind" == completed ]]; then
              if [[ -e "$metadata" || -L "$metadata" ]]; then
                [[ -d "$metadata" && ! -L "$metadata" ]] || return 1
                ${lib.getExe' coreutils "rm"} -rf -- "$metadata" || return 1
              fi
              if [[ -e "$session" || -L "$session" ]]; then
                [[ -d "$session" && ! -L "$session" ]] || return 1
                ${lib.getExe' coreutils "rm"} -rf -- "$session" || return 1
              fi
              ${lib.getExe' coreutils "rm"} -rf -- "$record" || return 1
              ${lib.getExe' coreutils "sync"} -f "$recovery_root" || return 1
              return 0
            fi

            if [[ "$kind" == directory ]]; then
              original="$metadata/original-git"
              if [[ -e "$original" || -L "$original" ]]; then
                [[ -d "$original" && ! -L "$original" ]] || return 1
              elif [[ ! -d "$recorded_worktree/.git" \
                || -L "$recorded_worktree/.git" ]]; then
                return 1
              fi
            elif [[ "$kind" == file ]]; then
              original="$metadata/original-dotgit"
              if [[ -e "$original" || -L "$original" ]]; then
                [[ -f "$original" && ! -L "$original" ]] || return 1
              elif [[ ! -f "$recorded_worktree/.git" || -L "$recorded_worktree/.git" ]]; then
                return 1
              fi
            else
              return 1
            fi
            if [[ -e "$original" || -L "$original" ]]; then
              if [[ "$kind" == directory ]]; then
                if [[ ! -e "$recorded_worktree/.git" \
                  && ! -L "$recorded_worktree/.git" ]]; then
                  ${lib.getExe' coreutils "mkdir"} -m 0700 -- \
                    "$recorded_worktree/.git" || return 1
                fi
                [[ -d "$recorded_worktree/.git" \
                  && ! -L "$recorded_worktree/.git" ]] || return 1
                if [[ ! -f "$record/restoring" \
                  && -n "$(${lib.getExe' findutils "find"} -P \
                    "$recorded_worktree/.git" -mindepth 1 -print -quit)" ]]; then
                  echo "error: refusing to replace repaired Git metadata" >&2
                  return 1
                fi
                printf '%s\n' restoring > "$record/restoring" || return 1
                ${lib.getExe' coreutils "sync"} -f "$record/restoring" || return 1
                ${lib.getExe' findutils "find"} -P "$recorded_worktree/.git" \
                  -mindepth 1 -delete || return 1
                ${lib.getExe' coreutils "cp"} -a -l -- \
                  "$original/." "$recorded_worktree/.git/" || return 1
                ${lib.getExe' coreutils "chmod"} --reference="$original" \
                  "$recorded_worktree/.git" || return 1
                ${lib.getExe' coreutils "sync"} -f \
                  "$recorded_worktree/.git" || return 1
                ${lib.getExe' coreutils "rm"} -rf -- "$original" || return 1
              else
                expected_pointer="gitdir: $session/home/.run/git"
                if [[ ! -e "$recorded_worktree/.git" \
                  && ! -L "$recorded_worktree/.git" ]]; then
                  printf '%s\n' "$expected_pointer" > "$recorded_worktree/.git" \
                    || return 1
                  ${lib.getExe' coreutils "chmod"} --reference="$original" \
                    "$recorded_worktree/.git" || return 1
                elif [[ ! -f "$recorded_worktree/.git" \
                  || -L "$recorded_worktree/.git" ]]; then
                  echo "error: refusing to replace repaired Git metadata" >&2
                  return 1
                fi
                if [[ ! -f "$record/restoring" ]]; then
                  IFS= read -r actual_pointer < "$recorded_worktree/.git" \
                    || actual_pointer=
                  if [[ "$actual_pointer" != "$expected_pointer" \
                    || "$(${lib.getExe' coreutils "wc"} -l \
                      < "$recorded_worktree/.git" | ${lib.getExe' coreutils "tr"} -d ' ')" \
                      != 1 ]]; then
                    echo "error: refusing to replace repaired Git metadata" >&2
                    return 1
                  fi
                fi
                printf '%s\n' restoring > "$record/restoring" || return 1
                ${lib.getExe' coreutils "sync"} -f "$record/restoring" || return 1
                ${lib.getExe' coreutils "cat"} -- "$original" \
                  > "$recorded_worktree/.git" || return 1
                ${lib.getExe' coreutils "chmod"} --reference="$original" \
                  "$recorded_worktree/.git" || return 1
                ${lib.getExe' coreutils "sync"} -f \
                  "$recorded_worktree/.git" || return 1
                ${lib.getExe' coreutils "rm"} -f -- "$original" || return 1
              fi
              ${lib.getExe' coreutils "sync"} -f \
                "$(${lib.getExe' coreutils "dirname"} "$recorded_worktree")" || return 1
            fi
            quarantine="$recovery_root/quarantined-git-''${expected_digest%% *}.$(
              ${lib.getExe' coreutils "date"} +%s
            ).$$"
            if [[ -e "$session" || -L "$session" ]]; then
              [[ -d "$session" && ! -L "$session" \
                && ! -e "$quarantine" && ! -L "$quarantine" ]] || return 1
              ${lib.getExe' coreutils "mv"} -- "$session" "$quarantine" || return 1
              ${lib.getExe' coreutils "sync"} -f "$recovery_root" || return 1
              echo "warning: interrupted Git session quarantined at $quarantine" >&2
            fi
            completed="$recovery_root/completed-$(
              ${lib.getExe' coreutils "basename"} "$record"
            ).$$"
            ${lib.getExe' coreutils "mv"} -- "$record" "$completed" || return 1
            ${lib.getExe' coreutils "sync"} -f "$recovery_root" || return 1
            if [[ -e "$metadata" || -L "$metadata" ]]; then
              ${lib.getExe' coreutils "rm"} -rf -- "$metadata" || return 1
            fi
            ${lib.getExe' coreutils "rm"} -rf -- "$completed" || return 1
            ${lib.getExe' coreutils "sync"} -f "$recovery_root" || return 1
          }

          for record in "$recovery_root"/completed-* "$recovery_root"/git-*; do
            [[ -e "$record" || -L "$record" ]] || continue
            [[ -d "$record" && ! -L "$record" ]] || continue
            if [[ "$record" == *.tmp.* ]]; then
              owner=
              if [[ -f "$record/owner" && ! -L "$record/owner" ]]; then
                IFS= read -r owner < "$record/owner" || owner=
              fi
              if [[ "$owner" =~ ^[0-9]+$ ]] && kill -0 "$owner" 2>/dev/null; then
                recorded_worktree=
                if [[ -f "$record/worktree" && ! -L "$record/worktree" ]]; then
                  IFS= read -r recorded_worktree < "$record/worktree" \
                    || recorded_worktree=
                fi
                if [[ -n "$recorded_worktree" ]]; then
                  case "$current_directory" in
                    "$recorded_worktree" | "$recorded_worktree"/*)
                      echo "error: Git recovery transaction is still active: $record" >&2
                      return 1
                      ;;
                  esac
                fi
                continue
              fi
              ${lib.getExe' coreutils "rm"} -rf -- "$record" || return 1
              continue
            fi
            case "$record" in
              "$recovery_root"/completed-*)
                record_kind=completed
                ;;
              "$recovery_root"/git-*)
                record_kind=pending
                ;;
              *)
                return 1
                ;;
            esac
            for required_record in worktree metadata metadata-parent kind owner session; do
              if [[ ! -f "$record/$required_record" || -L "$record/$required_record" ]]; then
                echo "error: invalid Git recovery record: $record" >&2
                return 1
              fi
            done
            IFS= read -r recorded_worktree < "$record/worktree" || return 1
            if [[ "$record_kind" == pending ]]; then
              case "$current_directory" in
                "$recorded_worktree" | "$recorded_worktree"/*)
                  ;;
                *)
                  continue
                  ;;
              esac
            fi
            expected_digest="$(
              printf '%s' "$recorded_worktree" | ${lib.getExe' coreutils "sha256sum"}
            )"
            if [[ "$recorded_worktree" != /* \
              || "$recorded_worktree" == / \
              || "$(${lib.getExe' coreutils "realpath"} -m -- "$recorded_worktree")" \
                != "$recorded_worktree" \
              || ( "$record_kind" == pending \
                && ( ! -d "$recorded_worktree" || -L "$recorded_worktree" ) ) ]]; then
              echo "error: invalid Git recovery target: $record" >&2
              return 1
            fi
            if [[ "$record_kind" == pending ]]; then
              [[ "$record" == "$recovery_root/git-''${expected_digest%% *}" ]] \
                || return 1
            else
              [[ "$record" == "$recovery_root/completed-git-''${expected_digest%% *}".* ]] \
                || return 1
            fi
            recovery_lock="$locks_root/git-worktree-''${expected_digest%% *}"
            acquire_lock "$recovery_lock" || return 1
            if [[ ! -e "$record" && ! -L "$record" ]]; then
              release_lock "$recovery_lock"
              continue
            fi
            recovery_status=0
            recover_record_locked || recovery_status=$?
            release_lock "$recovery_lock"
            if [[ "$record_kind" == completed && "$recovery_status" -eq 2 ]]; then
              continue
            fi
            [[ "$recovery_status" -eq 0 ]] || return "$recovery_status"
          done
        }

        recovery_status=0
        set +e
        (
          set -e
          recover_pending_git
        )
        recovery_status=$?
        set -e
        if [[ "$recovery_status" -ne 0 ]]; then
          echo "error: unable to recover interrupted Git isolation" >&2
          exit 78
        fi
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

        read_auth_generation() {
          local generation
          local extra
          if [[ ! -e "$auth_generation" && ! -L "$auth_generation" ]]; then
            printf '%s\n' uninitialized
            return 0
          fi
          if [[ ! -f "$auth_generation" || -L "$auth_generation" ]]; then
            printf '%s\n' invalid
            return 0
          fi
          IFS= read -r generation < "$auth_generation" || generation=
          IFS= read -r extra < <(${lib.getExe' coreutils "tail"} -n +2 -- "$auth_generation") \
            || extra=
          if [[ -n "$extra" ]] \
            || [[ "$generation" != absent \
              && ! "$generation" =~ ^sha256:[0-9a-f]{64}$ ]]; then
            printf '%s\n' invalid
          else
            printf '%s\n' "$generation"
          fi
        }

        select_host_auth() {
          local legacy_fingerprint
          local persistent_fingerprint
          local recorded_fingerprint

          recorded_fingerprint="$(read_auth_generation)"
          persistent_fingerprint="$(fingerprint "$persistent_target")"
          legacy_fingerprint="$(fingerprint "$legacy_source")"
          if [[ "$recorded_fingerprint" == invalid \
            || "$persistent_fingerprint" == invalid \
            || "$legacy_fingerprint" == invalid ]]; then
            return 1
          fi

          if [[ "$recorded_fingerprint" == uninitialized ]]; then
            if [[ "$persistent_fingerprint" == absent ]]; then
              selected_auth_fingerprint="$legacy_fingerprint"
              selected_auth_source="$legacy_source"
            elif [[ "$legacy_fingerprint" == absent \
              || "$persistent_fingerprint" == "$legacy_fingerprint" ]]; then
              selected_auth_fingerprint="$persistent_fingerprint"
              selected_auth_source="$persistent_target"
            elif [[ "$legacy_source" -nt "$persistent_target" ]]; then
              selected_auth_fingerprint="$legacy_fingerprint"
              selected_auth_source="$legacy_source"
            else
              selected_auth_fingerprint="$persistent_fingerprint"
              selected_auth_source="$persistent_target"
            fi
          elif [[ "$persistent_fingerprint" != "$recorded_fingerprint" \
            && "$legacy_fingerprint" != "$recorded_fingerprint" \
            && "$persistent_fingerprint" != "$legacy_fingerprint" ]]; then
            return 1
          elif [[ "$persistent_fingerprint" == "$recorded_fingerprint" \
            && "$legacy_fingerprint" == absent \
            && "$recorded_fingerprint" != absent ]]; then
            selected_auth_fingerprint="$persistent_fingerprint"
            selected_auth_source="$persistent_target"
          elif [[ "$legacy_fingerprint" == "$recorded_fingerprint" \
            && "$persistent_fingerprint" == absent \
            && "$recorded_fingerprint" != absent ]]; then
            selected_auth_fingerprint="$legacy_fingerprint"
            selected_auth_source="$legacy_source"
          elif [[ "$persistent_fingerprint" != "$recorded_fingerprint" ]]; then
            selected_auth_fingerprint="$persistent_fingerprint"
            selected_auth_source="$persistent_target"
          elif [[ "$legacy_fingerprint" != "$recorded_fingerprint" ]]; then
            selected_auth_fingerprint="$legacy_fingerprint"
            selected_auth_source="$legacy_source"
          else
            selected_auth_fingerprint="$recorded_fingerprint"
            selected_auth_source="$persistent_target"
          fi
          if [[ "$selected_auth_fingerprint" == absent ]]; then
            selected_auth_source=
          fi
        }

        sync_auth_locations() {
          local desired_fingerprint="$1"
          local desired_source="$2"
          local generation_temporary="$auth_generation.tmp.$$"
          local legacy_temporary="$legacy_source.tmp.$$"
          local persistent_temporary="$persistent_target.tmp.$$"

          ${lib.getExe' coreutils "rm"} -f -- \
            "$generation_temporary" \
            "$legacy_temporary" \
            "$persistent_temporary"
          if [[ "$desired_fingerprint" == absent ]]; then
            ${lib.getExe' coreutils "rm"} -f -- "$legacy_source" "$persistent_target" \
              || return 1
          else
            [[ "$(fingerprint "$desired_source")" == "$desired_fingerprint" ]] || return 1
            ${lib.getExe' coreutils "cp"} -- "$desired_source" "$legacy_temporary" \
              || return 1
            ${lib.getExe' coreutils "cp"} -- "$desired_source" "$persistent_temporary" \
              || return 1
            ${lib.getExe' coreutils "chmod"} 0600 -- \
              "$legacy_temporary" "$persistent_temporary" || return 1
            ${lib.getExe' coreutils "mv"} -f -- "$legacy_temporary" "$legacy_source" \
              || return 1
            ${lib.getExe' coreutils "mv"} -f -- "$persistent_temporary" "$persistent_target" \
              || return 1
          fi
          printf '%s\n' "$desired_fingerprint" > "$generation_temporary" || return 1
          ${lib.getExe' coreutils "chmod"} 0600 -- "$generation_temporary" || return 1
          ${lib.getExe' coreutils "mv"} -f -- "$generation_temporary" "$auth_generation" \
            || return 1
        }

        ensure_safe_file_parent() {
          local root="$1"
          local relative_file="$2"
          local component
          local current="$root"
          local expected
          local relative_parent
          local -a components

          relative_parent="$(${lib.getExe' coreutils "dirname"} "$relative_file")"
          if [[ "$relative_parent" == . ]]; then
            return 0
          fi
          IFS=/ read -r -a components <<< "$relative_parent"
          for component in "''${components[@]}"; do
            if [[ -z "$component" || "$component" == . || "$component" == .. ]]; then
              return 1
            fi
            current="$current/$component"
            if [[ -L "$current" ]]; then
              return 1
            fi
            if [[ ! -e "$current" ]]; then
              ${lib.getExe' coreutils "mkdir"} -m 0700 -- "$current" || return 1
            fi
            [[ -d "$current" && ! -L "$current" ]] || return 1
          done
          expected="$configured_home_canonical/$relative_parent"
          [[ "$(${lib.getExe' coreutils "realpath"} -e -- "$current")" == "$expected" ]]
        }

        copy_safe_tree() {
          local source="$1"
          local target="$2"
          local unsafe_entry

          [[ -d "$source" && ! -L "$source" ]] || return 1
          unsafe_entry="$(${lib.getExe' findutils "find"} -P "$source" -mindepth 1 \
            ! -type d ! -type f -print -quit)"
          [[ -z "$unsafe_entry" ]] || return 1
          ${lib.getExe' coreutils "mkdir"} -p -- "$target" || return 1
          ${lib.getExe' coreutils "cp"} -R -- "$source/." "$target/"
        }

        restore_dotgit() {
          local actual_pointer
          local expected_pointer
          local original
          if [[ -z "$dotgit_kind" || "$dotgit_restored" -eq 1 ]]; then
            return 0
          fi
          if [[ "$(cd "$worktree_root" && pwd -P)" != "$worktree_root" ]]; then
            return 1
          fi
          if [[ "$dotgit_kind" == directory ]]; then
            original="$metadata_root/original-git"
            if [[ ! -e "$original" && ! -L "$original" ]]; then
              [[ -d "$worktree_root/.git" && ! -L "$worktree_root/.git" ]] || return 1
            else
              [[ -d "$original" && ! -L "$original" ]] || return 1
            fi
          else
            original="$metadata_root/original-dotgit"
            if [[ ! -e "$original" && ! -L "$original" ]]; then
              [[ -f "$worktree_root/.git" && ! -L "$worktree_root/.git" ]] || return 1
            else
              [[ -f "$original" && ! -L "$original" ]] || return 1
            fi
          fi
          if [[ -e "$original" || -L "$original" ]]; then
            if [[ "$dotgit_kind" == directory ]]; then
              [[ -d "$worktree_root/.git" && ! -L "$worktree_root/.git" ]] \
                || return 1
              if [[ -n "$(${lib.getExe' findutils "find"} -P \
                "$worktree_root/.git" -mindepth 1 -print -quit)" ]]; then
                return 1
              fi
              printf '%s\n' restoring > "$recovery_record/restoring" || return 1
              ${lib.getExe' coreutils "sync"} -f "$recovery_record/restoring" \
                || return 1
              ${lib.getExe' findutils "find"} -P "$worktree_root/.git" \
                -mindepth 1 -delete || return 1
              ${lib.getExe' coreutils "cp"} -a -l -- \
                "$original/." "$worktree_root/.git/" || return 1
              ${lib.getExe' coreutils "chmod"} --reference="$original" \
                "$worktree_root/.git" || return 1
              ${lib.getExe' coreutils "sync"} -f "$worktree_root/.git" || return 1
              ${lib.getExe' coreutils "rm"} -rf -- "$original" || return 1
            else
              expected_pointer="gitdir: $session_git"
              [[ -f "$worktree_root/.git" && ! -L "$worktree_root/.git" ]] \
                || return 1
              IFS= read -r actual_pointer < "$worktree_root/.git" \
                || actual_pointer=
              if [[ "$actual_pointer" != "$expected_pointer" \
                || "$(${lib.getExe' coreutils "wc"} -l \
                  < "$worktree_root/.git" | ${lib.getExe' coreutils "tr"} -d ' ')" \
                  != 1 ]]; then
                return 1
              fi
              printf '%s\n' restoring > "$recovery_record/restoring" || return 1
              ${lib.getExe' coreutils "sync"} -f "$recovery_record/restoring" \
                || return 1
              ${lib.getExe' coreutils "cat"} -- "$original" > "$worktree_root/.git" \
                || return 1
              ${lib.getExe' coreutils "chmod"} --reference="$original" \
                "$worktree_root/.git" || return 1
              ${lib.getExe' coreutils "sync"} -f "$worktree_root/.git" || return 1
              ${lib.getExe' coreutils "rm"} -f -- "$original" || return 1
            fi
            ${lib.getExe' coreutils "sync"} -f "$worktree_parent" || return 1
          fi
          dotgit_restored=1
          if [[ -n "$recovery_record" && -d "$recovery_record" ]]; then
            completed_recovery_record="$recovery_root/completed-$(
              ${lib.getExe' coreutils "basename"} "$recovery_record"
            ).$$"
            ${lib.getExe' coreutils "mv"} -- \
              "$recovery_record" "$completed_recovery_record" || return 1
            ${lib.getExe' coreutils "sync"} -f "$recovery_root" || return 1
          fi
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
          local candidate_symbolic_target
          while IFS=$'\t' read -r candidate_ref candidate_oid candidate_symbolic_target; do
            if [[ "$candidate_ref" == "$requested_ref" ]]; then
              printf '%s\t%s\n' "$candidate_oid" "$candidate_symbolic_target"
              return 0
            fi
          done < "$refs_file"
          return 1
        }

        contains_exact_line() {
          local expected="$1"
          local source_file="$2"
          local candidate
          while IFS= read -r candidate; do
            [[ "$candidate" == "$expected" ]] && return 0
          done < "$source_file"
          return 1
        }

        sync_git_locked() {
          local current_time
          local current_head_mode
          local current_head_oid
          local current_head_ref
          local current_index_fingerprint
          local export_head_mode
          local export_head_oid
          local export_head_ref
          local export_index_state
          local exported_lookup
          local exported_ref
          local exported_ref_oid
          local exported_symbolic_target
          local extra_field
          local index_temporary="$real_index.tmp.$$"
          local required_export
          local refs_changed=0
          local refs_transaction="$session_root/refs-transaction"
          local reflog_oid
          local reflog_type
          local recovery_ref
          local recovery_ref_oid
          local recovery_ref_suffix
          local recovery_ref_timestamp
          local recovery_cutoff
          local migrated_recovery_ref
          local candidate_recovery_ref
          local candidate_recovery_suffix
          local candidate_recovery_timestamp
          local session_ref
          local session_reachable
          local start_ref
          local start_lookup
          local start_ref_oid
          local start_symbolic_target

          for required_export in \
            "$git_export/status" \
            "$git_export/head-mode" \
            "$git_export/head-ref" \
            "$git_export/head-oid" \
            "$git_export/index-state" \
            "$git_export/refs" \
            "$git_export/reflog-oids" \
            "$git_export/objects.pack"; do
            [[ -f "$required_export" && ! -L "$required_export" ]] || return 1
          done
          [[ "$(<"$git_export/status")" == ok ]] || return 1
          IFS= read -r export_head_mode < "$git_export/head-mode"
          IFS= read -r export_head_ref < "$git_export/head-ref"
          IFS= read -r export_head_oid < "$git_export/head-oid"
          IFS= read -r export_index_state < "$git_export/index-state"

          [[ "$export_head_mode" == symbolic || "$export_head_mode" == detached ]] || return 1
          [[ "$export_index_state" == present || "$export_index_state" == absent ]] || return 1
          if [[ "$export_head_mode" == symbolic ]]; then
            [[ -n "$export_head_ref" ]] || return 1
            safe_real_git check-ref-format "$export_head_ref" || return 1
          elif [[ -n "$export_head_ref" || -z "$export_head_oid" ]]; then
            return 1
          fi
          if [[ -n "$export_head_oid" && ! "$export_head_oid" =~ ^[0-9a-fA-F]{40,64}$ ]]; then
            return 1
          fi
          while IFS=$'\t' read -r \
            exported_ref exported_ref_oid exported_symbolic_target extra_field; do
            [[ -n "$exported_ref" && -n "$exported_ref_oid" && -z "$extra_field" ]] \
              || return 1
            safe_real_git check-ref-format "$exported_ref" || return 1
            [[ "$exported_ref_oid" =~ ^[0-9a-fA-F]{40,64}$ ]] || return 1
            if [[ -n "$exported_symbolic_target" ]]; then
              safe_real_git check-ref-format "$exported_symbolic_target" || return 1
            fi
          done < "$git_export/refs"
          while read -r reflog_oid extra_field; do
            [[ -n "$reflog_oid" && -z "$extra_field" \
              && "$reflog_oid" =~ ^[0-9a-fA-F]{40,64}$ ]] || return 1
          done < "$git_export/reflog-oids"

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
          while IFS=$'\t' read -r start_ref start_ref_oid start_symbolic_target; do
            if exported_lookup="$(lookup_ref "$git_export/refs" "$start_ref")"; then
              IFS=$'\t' read -r exported_ref_oid exported_symbolic_target \
                <<< "$exported_lookup"
              safe_real_git cat-file -e "$exported_ref_oid^{object}" || return 1
              if [[ -n "$start_symbolic_target" && -n "$exported_symbolic_target" ]]; then
                if [[ "$exported_symbolic_target" != "$start_symbolic_target" ]]; then
                  printf 'option no-deref\n' >> "$refs_transaction" || return 1
                  printf 'symref-update %s %s ref %s\n' \
                    "$start_ref" "$exported_symbolic_target" "$start_symbolic_target" \
                    >> "$refs_transaction" || return 1
                  refs_changed=1
                fi
              elif [[ -z "$start_symbolic_target" && -n "$exported_symbolic_target" ]]; then
                printf 'option no-deref\n' >> "$refs_transaction" || return 1
                printf 'symref-update %s %s oid %s\n' \
                  "$start_ref" "$exported_symbolic_target" "$start_ref_oid" \
                  >> "$refs_transaction" || return 1
                refs_changed=1
              elif [[ -n "$start_symbolic_target" ]]; then
                return 1
              elif [[ "$exported_ref_oid" != "$start_ref_oid" ]]; then
                printf 'update %s %s %s\n' \
                  "$start_ref" "$exported_ref_oid" "$start_ref_oid" \
                  >> "$refs_transaction" || return 1
                refs_changed=1
              fi
            else
              if [[ -n "$start_symbolic_target" ]]; then
                printf 'option no-deref\n' >> "$refs_transaction" || return 1
                printf 'symref-delete %s %s\n' \
                  "$start_ref" "$start_symbolic_target" >> "$refs_transaction" || return 1
              else
                printf 'delete %s %s\n' \
                  "$start_ref" "$start_ref_oid" >> "$refs_transaction" || return 1
              fi
              refs_changed=1
            fi
          done < "$start_refs"
          while IFS=$'\t' read -r \
            exported_ref exported_ref_oid exported_symbolic_target; do
            if ! lookup_ref "$start_refs" "$exported_ref" >/dev/null; then
              safe_real_git cat-file -e "$exported_ref_oid^{object}" || return 1
              if [[ -n "$exported_symbolic_target" ]]; then
                printf 'option no-deref\n' >> "$refs_transaction" || return 1
                printf 'symref-create %s %s\n' \
                  "$exported_ref" "$exported_symbolic_target" \
                  >> "$refs_transaction" || return 1
              else
                printf 'create %s %s\n' \
                  "$exported_ref" "$exported_ref_oid" \
                  >> "$refs_transaction" || return 1
              fi
              refs_changed=1
            fi
          done < "$git_export/refs"
          current_time="$(${lib.getExe' coreutils "date"} +%s)" || return 1
          recovery_cutoff=$((current_time - 2592000))
          while IFS=$'\t' read -r recovery_ref recovery_ref_oid; do
            recovery_ref_suffix="''${recovery_ref##*/}"
            recovery_ref_timestamp="''${recovery_ref_suffix%%-*}"
            if [[ "$recovery_ref_timestamp" =~ ^[0-9]+$ \
              && "$recovery_ref_timestamp" -lt "$recovery_cutoff" ]]; then
              printf 'delete %s %s\n' "$recovery_ref" "$recovery_ref_oid" \
                >> "$refs_transaction" || return 1
              refs_changed=1
            elif [[ "$recovery_ref_suffix" =~ ^[0-9a-fA-F]{40,64}$ ]]; then
              migrated_recovery_ref=
              while IFS= read -r candidate_recovery_ref; do
                candidate_recovery_suffix="''${candidate_recovery_ref##*/}"
                candidate_recovery_timestamp="''${candidate_recovery_suffix%%-*}"
                if [[ "$candidate_recovery_ref" != "$recovery_ref" \
                  && "$candidate_recovery_timestamp" =~ ^[0-9]+$ \
                  && "$candidate_recovery_timestamp" -ge "$recovery_cutoff" ]]; then
                  migrated_recovery_ref="$candidate_recovery_ref"
                  break
                fi
              done < <(
                safe_real_git for-each-ref \
                  --points-at="$recovery_ref_oid" \
                  --format='%(refname)' \
                  "refs/nono/recovery/''${worktree_digest%% *}/"
              )
              if [[ -z "$migrated_recovery_ref" ]]; then
                migrated_recovery_ref="refs/nono/recovery/''${worktree_digest%% *}/$current_time-$recovery_ref_suffix"
                printf 'create %s %s\n' "$migrated_recovery_ref" "$recovery_ref_oid" \
                  >> "$refs_transaction" || return 1
              fi
              printf 'delete %s %s\n' "$recovery_ref" "$recovery_ref_oid" \
                >> "$refs_transaction" || return 1
              refs_changed=1
            fi
          done < <(
            safe_real_git for-each-ref \
              --format='%(refname)%09%(objectname)' \
              "refs/nono/recovery/''${worktree_digest%% *}/"
          )
          while IFS= read -r reflog_oid; do
            contains_exact_line "$reflog_oid" "$start_reflog_oids" && continue
            reflog_type="$(safe_real_git cat-file -t "$reflog_oid")" || return 1
            session_reachable=0
            if [[ "$reflog_type" == commit ]]; then
              while IFS= read -r session_ref; do
                if [[ -n "$session_ref" ]]; then
                  session_reachable=1
                  break
                fi
              done < <(
                ${lib.getExe git} \
                  --git-dir="$session_git" \
                  --work-tree="$worktree_root" \
                  for-each-ref --contains="$reflog_oid" --format='%(refname)'
              )
              if [[ "$session_reachable" -eq 0 && -n "$export_head_oid" ]] \
                && ${lib.getExe git} \
                  --git-dir="$session_git" \
                  --work-tree="$worktree_root" \
                  merge-base --is-ancestor "$reflog_oid" "$export_head_oid"; then
                session_reachable=1
              fi
            fi
            if [[ "$session_reachable" -eq 0 ]]; then
              recovery_ref="$(
                safe_real_git for-each-ref \
                  --points-at="$reflog_oid" \
                  --format='%(refname)' \
                  "refs/nono/recovery/''${worktree_digest%% *}/" \
                  | ${lib.getExe' coreutils "head"} -n 1
              )"
              if [[ -z "$recovery_ref" ]]; then
                recovery_ref="refs/nono/recovery/''${worktree_digest%% *}/$current_time-$reflog_oid"
                printf 'create %s %s\n' "$recovery_ref" "$reflog_oid" \
                  >> "$refs_transaction" || return 1
                refs_changed=1
              fi
            fi
          done < "$git_export/reflog-oids"
          if [[ "$refs_changed" -eq 1 ]]; then
            safe_real_git update-ref --stdin < "$refs_transaction" || return 1
          fi
          if [[ "$start_head_mode" == symbolic && "$export_head_mode" == symbolic ]]; then
            if [[ "$export_head_ref" != "$start_head_ref" ]]; then
              safe_real_git symbolic-ref HEAD "$export_head_ref" || return 1
            fi
          elif [[ "$start_head_mode" == detached && "$export_head_mode" == detached ]]; then
            if [[ "$export_head_oid" != "$start_head_oid" ]]; then
              safe_real_git update-ref --no-deref HEAD "$export_head_oid" "$start_head_oid" \
                || return 1
            fi
          elif [[ "$export_head_mode" == symbolic ]]; then
            safe_real_git symbolic-ref HEAD "$export_head_ref" || return 1
          else
            safe_real_git update-ref --no-deref HEAD "$export_head_oid" || return 1
          fi

          if [[ "$export_index_state" == present ]]; then
            ${lib.getExe' coreutils "cp"} -- "$git_export/index" "$index_temporary" || return 1
            ${lib.getExe' coreutils "chmod"} 0600 -- "$index_temporary" || return 1
            ${lib.getExe' coreutils "mv"} -f -- "$index_temporary" "$real_index" || return 1
          else
            ${lib.getExe' coreutils "rm"} -f -- "$real_index" || return 1
          fi
        }

        sync_git() {
          local sync_status=0
          acquire_lock "$common_lock" || return 1
          sync_git_locked || sync_status=$?
          release_lock "$common_lock"
          return "$sync_status"
        }

        persist_auth() {
          local auth_state
          local export_fingerprint

          [[ -f "$auth_status" && ! -L "$auth_status" ]] || return 1
          IFS= read -r auth_state < "$auth_status"
          [[ "$auth_state" == present || "$auth_state" == absent ]] || return 1
          if [[ "$auth_state" == present ]]; then
            [[ -f "$auth_export" && ! -L "$auth_export" ]] || return 1
            export_fingerprint="$(fingerprint "$auth_export")"
          else
            export_fingerprint=absent
          fi

          if ! acquire_lock "$auth_lock"; then
            return 1
          fi
          if ! select_host_auth; then
            recovery_required=1
            echo "error: ${name} authentication locations diverged; preserving recovery state" >&2
            release_lock "$auth_lock"
            return 1
          fi
          if [[ "$export_fingerprint" != "$auth_baseline_fingerprint" \
            && "$selected_auth_fingerprint" != "$auth_baseline_fingerprint" \
            && "$selected_auth_fingerprint" != "$export_fingerprint" ]]; then
            if [[ "$auth_state" == present ]]; then
              ${lib.getExe' coreutils "cp"} -- "$auth_export" "$session_root/auth-conflict"
            fi
            recovery_required=1
            echo "error: ${name} authentication changed in concurrent sessions; preserving recovery state" >&2
            release_lock "$auth_lock"
            return 1
          fi
          if [[ "$export_fingerprint" == "$auth_baseline_fingerprint" ]]; then
            if ! sync_auth_locations "$selected_auth_fingerprint" "$selected_auth_source"; then
              release_lock "$auth_lock"
              return 1
            fi
          elif ! sync_auth_locations "$export_fingerprint" "$auth_export"; then
            release_lock "$auth_lock"
            return 1
          fi
          release_lock "$auth_lock"
        }

        cleanup() {
          local original_status=$?
          local state_parent
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
          if [[ -n "$recovery_temporary" && -d "$recovery_temporary" ]]; then
            ${lib.getExe' coreutils "rm"} -rf -- "$recovery_temporary" || cleanup_failed=1
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
          if [[ -n "$nono_state_root" ]]; then
            state_parent="$configured_home_canonical/.nono-s"
            if [[ "$nono_state_root" != "$state_parent"/* \
              || ! -d "$nono_state_root" \
              || -L "$nono_state_root" \
              || ! -f "$nono_state_root/worktree" \
              || -L "$nono_state_root/worktree" \
              || "$(<"$nono_state_root/worktree")" != "$worktree_root" ]]; then
              cleanup_failed=1
              recovery_required=1
              echo "error: refusing unsafe Nono runtime state cleanup" >&2
            elif ! ${lib.getExe' coreutils "rm"} -rf -- "$nono_state_root"; then
              cleanup_failed=1
              recovery_required=1
              echo "error: unable to remove Nono runtime state at $nono_state_root" >&2
            else
              ${lib.getExe' coreutils "rmdir"} -- "$state_parent" 2>/dev/null || true
            fi
          fi
          if [[ -n "$completed_recovery_record" \
            && -d "$completed_recovery_record" ]]; then
            ${lib.getExe' coreutils "rm"} -rf -- "$completed_recovery_record" \
              || cleanup_failed=1
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

        worktree_digest="$(
          printf '%s' "$worktree_root" | ${lib.getExe' coreutils "sha256sum"}
        )"
        readonly git_lock="$locks_root/git-worktree-''${worktree_digest%% *}"
        readonly auth_lock="$locks_root/auth-${name}"
        acquire_lock "$git_lock"

        readonly nono_state_parent="$configured_home_canonical/.nono-s"
        if [[ ! -e "$nono_state_parent" && ! -L "$nono_state_parent" ]]; then
          ${lib.getExe' coreutils "mkdir"} -m 0700 -- "$nono_state_parent"
        fi
        if [[ ! -d "$nono_state_parent" \
          || -L "$nono_state_parent" \
          || "$(${lib.getExe' coreutils "realpath"} -e -- "$nono_state_parent")" \
            != "$nono_state_parent" ]]; then
          echo "error: refusing unsafe Nono runtime state root: $nono_state_parent" >&2
          exit 78
        fi
        ${lib.getExe' coreutils "chmod"} 0700 -- "$nono_state_parent"
        nono_state_root="$nono_state_parent/''${worktree_digest:0:12}"
        if [[ -e "$nono_state_root" || -L "$nono_state_root" ]]; then
          if [[ ! -d "$nono_state_root" \
            || -L "$nono_state_root" \
            || ! -f "$nono_state_root/worktree" \
            || -L "$nono_state_root/worktree" \
            || "$(<"$nono_state_root/worktree")" != "$worktree_root" ]]; then
            echo "error: refusing conflicting Nono runtime state: $nono_state_root" >&2
            exit 78
          fi
          ${lib.getExe' coreutils "rm"} -rf -- "$nono_state_root"
        fi
        ${lib.getExe' coreutils "mkdir"} -m 0700 -- "$nono_state_root"
        printf '%s\n' "$worktree_root" > "$nono_state_root/worktree"
        ${lib.getExe' coreutils "chmod"} 0600 -- "$nono_state_root/worktree"
        readonly nono_state_root

        if ! git_directory="$(${lib.getExe git} -C "$current_directory" \
          rev-parse --path-format=absolute --git-dir 2>/dev/null)" \
          || ! common_directory="$(${lib.getExe git} -C "$current_directory" \
            rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
          echo "error: unable to resolve Git metadata for $worktree_root" >&2
          exit 78
        fi
        git_directory="$(cd "$git_directory" && pwd -P)"
        common_directory="$(cd "$common_directory" && pwd -P)"
        common_digest="$(
          printf '%s' "$common_directory" | ${lib.getExe' coreutils "sha256sum"}
        )"
        readonly common_lock="$locks_root/git-common-''${common_digest%% *}"

        if [[ -d "$worktree_root/.git" \
          && ! -L "$worktree_root/.git" \
          && "$git_directory" == "$common_directory" \
          && -d "$common_directory/worktrees" ]]; then
          for linked_worktree_entry in "$common_directory"/worktrees/*; do
            [[ -e "$linked_worktree_entry" || -L "$linked_worktree_entry" ]] || continue
            echo "error: refusing main worktree with linked worktrees: $worktree_root" >&2
            exit 78
          done
        fi

        unsupported_state=
        if [[ "$(${lib.getExe git} -C "$current_directory" rev-parse --is-shallow-repository)" == true ]]; then
          unsupported_state=shallow
        elif [[ "$(${lib.getExe git} -C "$current_directory" config --bool core.sparseCheckout || true)" == true ]]; then
          unsupported_state=sparse-checkout
        elif [[ "$(${lib.getExe git} -C "$current_directory" config --bool index.sparse || true)" == true ]]; then
          unsupported_state=sparse-index
        elif [[ "$(${lib.getExe git} -C "$current_directory" config --bool core.splitIndex || true)" == true ]]; then
          unsupported_state=split-index
        elif [[ -n "$(${lib.getExe git} -C "$current_directory" \
          rev-parse --shared-index-path 2>/dev/null || true)" ]]; then
          unsupported_state=split-index
        fi
        if [[ -z "$unsupported_state" ]]; then
          alternates_path="$(${lib.getExe git} -C "$current_directory" \
            rev-parse --path-format=absolute --git-path objects/info/alternates)"
          if [[ -e "$alternates_path" || -L "$alternates_path" ]]; then
            if [[ ! -f "$alternates_path" || -L "$alternates_path" \
              || -s "$alternates_path" ]]; then
              unsupported_state=object-alternates
            fi
          fi
        fi
        if [[ -z "$unsupported_state" ]]; then
          for state_marker in \
            MERGE_HEAD \
            CHERRY_PICK_HEAD \
            REVERT_HEAD \
            BISECT_LOG \
            rebase-apply \
            rebase-merge \
            sequencer; do
            state_path="$(${lib.getExe git} -C "$current_directory" rev-parse --git-path "$state_marker")"
            if [[ -e "$state_path" || -L "$state_path" ]]; then
              unsupported_state="$state_marker"
              break
            fi
          done
        fi
        if [[ -z "$unsupported_state" ]]; then
          while read -r state_mode _; do
            if [[ "$state_mode" == 160000 ]]; then
              unsupported_state=submodule
              break
            fi
          done < <(${lib.getExe git} -C "$current_directory" ls-files --stage)
        fi
        if [[ -n "$unsupported_state" ]]; then
          echo "error: unsupported Git state for isolated session: $unsupported_state" >&2
          exit 78
        fi

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
        readonly session_git="$session_home/.run/git"
        readonly export_root="$session_root/export"
        readonly git_export="$export_root/git"
        readonly auth_export="$export_root/auth"
        readonly auth_status="$export_root/auth-status"
        readonly start_refs="$session_root/start-refs"
        readonly start_reflog_oids="$session_root/start-reflog-oids"
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
        metadata_store_root="$session_temp_root/git-metadata"
        ${lib.getExe' coreutils "mkdir"} -p -- "$metadata_store_root"
        ${lib.getExe' coreutils "chmod"} 0700 -- "$metadata_store_root"
        if [[ -L "$metadata_store_root" \
          || "$(${lib.getExe' coreutils "realpath"} -e -- "$metadata_store_root")" \
            != "$metadata_store_root" ]]; then
          echo "error: refusing unsafe Git metadata store: $metadata_store_root" >&2
          exit 78
        fi
        metadata_parent="$metadata_store_root"
        readonly worktree_parent
        metadata_root="$(${lib.getExe' coreutils "mktemp"} \
          -d "$metadata_parent/.nono-git-metadata.XXXXXXXXXX")"
        git_device="$(${lib.getExe' coreutils "stat"} -c %d -- "$worktree_root/.git")"
        metadata_device="$(${lib.getExe' coreutils "stat"} -c %d -- "$metadata_root")"
        if [[ "$git_device" != "$metadata_device" ]]; then
          ${lib.getExe' coreutils "rmdir"} -- "$metadata_root"
          metadata_anchor="$worktree_root"
          ancestor="$worktree_parent"
          while [[ "$ancestor" != / ]]; do
            enclosing_worktree="$(
              ${lib.getExe git} -C "$ancestor" rev-parse --show-toplevel 2>/dev/null || true
            )"
            if [[ -n "$enclosing_worktree" ]]; then
              enclosing_worktree="$(cd "$enclosing_worktree" && pwd -P)"
              if [[ "$enclosing_worktree" != "$worktree_root" \
                && "$worktree_root" == "$enclosing_worktree/"* ]]; then
                metadata_anchor="$enclosing_worktree"
                ancestor="$(${lib.getExe' coreutils "dirname"} "$enclosing_worktree")"
                continue
              fi
            fi
            ancestor="$(${lib.getExe' coreutils "dirname"} "$ancestor")"
          done
          metadata_parent="$(${lib.getExe' coreutils "dirname"} "$metadata_anchor")"
          metadata_root="$(${lib.getExe' coreutils "mktemp"} \
            -d "$metadata_parent/.nono-git-metadata.XXXXXXXXXX")"
          metadata_device="$(${lib.getExe' coreutils "stat"} -c %d -- "$metadata_root")"
          if [[ "$git_device" != "$metadata_device" ]]; then
            echo "error: Git metadata isolation requires safe staging on the worktree filesystem" >&2
            exit 78
          fi
        fi
        readonly metadata_parent
        if [[ -d "$worktree_root/.git" && ! -L "$worktree_root/.git" ]]; then
          if [[ "$git_directory" != "$common_directory" \
            || "$git_directory" != "$worktree_root/.git" ]]; then
            echo "error: unsupported in-tree Git metadata layout" >&2
            exit 78
          fi
          dotgit_kind=directory
          real_git_directory="$metadata_root/original-git"
          real_common_directory="$metadata_root/original-git"
          real_index="$metadata_root/original-git/index"
        elif [[ -f "$worktree_root/.git" && ! -L "$worktree_root/.git" ]]; then
          dotgit_kind=file
          real_git_directory="$git_directory"
          real_common_directory="$common_directory"
        else
          echo "error: refusing unsupported .git entry: $worktree_root/.git" >&2
          exit 78
        fi
        candidate_recovery_record="$recovery_root/git-''${worktree_digest%% *}"
        recovery_temporary="$candidate_recovery_record.tmp.$$"
        if [[ -e "$candidate_recovery_record" || -L "$candidate_recovery_record" \
          || -e "$recovery_temporary" || -L "$recovery_temporary" ]]; then
          echo "error: refusing conflicting Git recovery record: $candidate_recovery_record" >&2
          exit 78
        fi
        recovery_record="$candidate_recovery_record"
        ${lib.getExe' coreutils "mkdir"} -m 0700 -- "$recovery_temporary"
        printf '%s\n' "$worktree_root" > "$recovery_temporary/worktree"
        printf '%s\n' "$metadata_root" > "$recovery_temporary/metadata"
        printf '%s\n' "$metadata_parent" > "$recovery_temporary/metadata-parent"
        printf '%s\n' "$dotgit_kind" > "$recovery_temporary/kind"
        printf '%s\n' "$$" > "$recovery_temporary/owner"
        printf '%s\n' "$session_root" > "$recovery_temporary/session"
        ${lib.getExe' coreutils "chmod"} 0600 -- "$recovery_temporary"/*
        ${lib.getExe' coreutils "sync"} -f "$recovery_temporary"/*
        ${lib.getExe' coreutils "mv"} -- "$recovery_temporary" "$recovery_record"
        ${lib.getExe' coreutils "sync"} -f "$recovery_root"
        if [[ "$dotgit_kind" == directory ]]; then
          ${lib.getExe' coreutils "mv"} -- "$worktree_root/.git" "$metadata_root/original-git"
          ${lib.getExe' coreutils "mkdir"} -m 0700 -- "$worktree_root/.git"
        else
          ${lib.getExe' coreutils "mv"} -- \
            "$worktree_root/.git" "$metadata_root/original-dotgit"
          printf 'gitdir: %s\n' "$session_git" > "$worktree_root/.git"
          ${lib.getExe' coreutils "chmod"} --reference="$metadata_root/original-dotgit" \
            "$worktree_root/.git"
        fi
        ${lib.getExe' coreutils "sync"} -f \
          "$metadata_root" "$worktree_root/.git" "$worktree_parent"
        readonly real_git_directory
        readonly real_common_directory
        readonly real_index
        readonly real_objects_directory="$real_common_directory/objects"
        readonly start_index_fingerprint="$(fingerprint "$real_index")"
        acquire_lock "$common_lock"
        ${lib.getExe git} --git-dir="$real_git_directory" for-each-ref \
          --format='%(refname)%09%(objectname)%09%(symref)' > "$start_refs"
        safe_real_git reflog --all --format=%H \
          | ${lib.getExe' coreutils "sort"} -u > "$start_reflog_oids"
        release_lock "$common_lock"

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
        while IFS=$'\t' read -r reference object symbolic_target; do
          if [[ -n "$symbolic_target" ]]; then
            ${lib.getExe git} --git-dir="$session_git" \
              symbolic-ref "$reference" "$symbolic_target"
          elif [[ -n "$object" && -n "$reference" ]]; then
            ${lib.getExe git} --git-dir="$session_git" \
              update-ref --no-deref "$reference" "$object"
          fi
        done < "$start_refs"
        if [[ "$start_head_mode" == symbolic ]]; then
          ${lib.getExe git} --git-dir="$session_git" symbolic-ref HEAD "$start_head_ref"
        elif [[ -n "$start_head_oid" ]]; then
          ${lib.getExe git} --git-dir="$session_git" update-ref --no-deref HEAD "$start_head_oid"
        fi
        if [[ -f "$real_index" && ! -L "$real_index" ]]; then
          ${lib.getExe' coreutils "cp"} -- "$real_index" "$session_git/index"
        fi
        if [[ -d "$real_common_directory/logs" \
          && ! -L "$real_common_directory/logs" ]]; then
          copy_safe_tree "$real_common_directory/logs" "$session_git/logs"
        fi
        if [[ "$real_git_directory" != "$real_common_directory" \
          && -f "$real_git_directory/logs/HEAD" \
          && ! -L "$real_git_directory/logs/HEAD" ]]; then
          ${lib.getExe' coreutils "mkdir"} -p -- "$session_git/logs"
          ${lib.getExe' coreutils "cp"} -- \
            "$real_git_directory/logs/HEAD" "$session_git/logs/HEAD"
        fi
        for relative_info_file in exclude attributes; do
          real_info_file="$real_common_directory/info/$relative_info_file"
          if [[ -f "$real_info_file" && ! -L "$real_info_file" ]]; then
            ${lib.getExe' coreutils "cp"} -- \
              "$real_info_file" "$session_git/info/$relative_info_file"
          fi
        done
        ${createWritableDirectories}
        ${createWritableFiles}
        ${stagePaths}
        ${stageFilteredJsonPaths}

        readonly legacy_source="$configured_home/$persistent_file"
        readonly auth_generation="$persistent_state_root/.synchronized-fingerprint"
        if ! ensure_safe_file_parent "$configured_home" \
          ".local/state/nono-agent-auth/${name}/$persistent_file" \
          || ! ensure_safe_file_parent "$configured_home" "$persistent_file"; then
          echo "error: refusing unsafe authentication state path for ${name}" >&2
          exit 78
        fi

        acquire_lock "$auth_lock"
        if ! select_host_auth \
          || ! sync_auth_locations "$selected_auth_fingerprint" "$selected_auth_source"; then
          echo "error: unable to reconcile ${name} authentication state" >&2
          exit 78
        fi
        auth_baseline_fingerprint="$selected_auth_fingerprint"
        release_lock "$auth_lock"

        if [[ "$auth_baseline_fingerprint" != absent ]]; then
          session_auth="$session_home/$persistent_file"
          ${lib.getExe' coreutils "mkdir"} -p -- \
            "$(${lib.getExe' coreutils "dirname"} "$session_auth")"
          ${lib.getExe' coreutils "chmod"} 0700 -- \
            "$(${lib.getExe' coreutils "dirname"} "$session_auth")"
          ${lib.getExe' coreutils "cp"} -- "$persistent_target" "$session_auth"
          ${lib.getExe' coreutils "chmod"} 0600 -- "$session_auth"
        fi

        export DOTFILES_AGENT_HOME="$session_home"
        export DOTFILES_HOST_HOME="$configured_home"
        export DOTFILES_WORKTREE_ROOT="$worktree_root"
        export GIT_DIR="$session_git"
        export GIT_WORK_TREE="$worktree_root"
        export TMPDIR="$session_temp"
        export NONO_NO_PACK_UPDATE_HINTS=1
        export NONO_NO_UPDATE_CHECK=1
        export XDG_CONFIG_HOME="$session_home/.config"
        export XDG_STATE_HOME="$nono_state_root"
        export HOME="$session_home"

        allow_domain_values="''${DOTFILES_NONO_ALLOW_DOMAINS:-chatgpt.com}"
        allow_domain_values="''${allow_domain_values//,/ }"
        nono_arguments=(
          run
          --profile "$profile_path"
          --allow "$worktree_root"
          --allow "$session_git"
          --read "$real_objects_directory"
          --allow "$export_root"
        )
        allow_domain_added=0
        for allow_domain_value in $allow_domain_values; do
          if [[ -n "$allow_domain_value" ]]; then
            nono_arguments+=(--allow-domain "$allow_domain_value")
            allow_domain_added=1
          fi
        done
        if [[ "$allow_domain_added" -eq 0 ]]; then
          nono_arguments+=(--allow-domain chatgpt.com)
        fi

        open_port_values="''${DOTFILES_NONO_OPEN_PORTS:-}"
        open_port_values="''${open_port_values//,/ }"
        for open_port_value in $open_port_values; do
          if [[ "$open_port_value" =~ ^[0-9]+$ ]]; then
            nono_arguments+=(--open-port "$open_port_value")
          else
            echo "error: invalid DOTFILES_NONO_OPEN_PORTS entry: $open_port_value" >&2
            exit 78
          fi
        done

        nono_arguments+=(
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
        ${lib.getExe' processSupervisor "nono-process-supervisor"} \
          --pid-file "$recovery_record/runtime" \
          --job-socket "$nono_state_root/control" \
          ${lib.escapeShellArg (lib.getExe nonoPackage)} \
          "''${nono_arguments[@]}"
        command_status=$?
        set -e
        exit "$command_status"
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
  paths = map mkNonoWrapper agentNames;
}
