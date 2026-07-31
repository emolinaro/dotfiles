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
