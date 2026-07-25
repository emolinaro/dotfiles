# dotfiles

My personal macOS and Ubuntu setup, managed with Nix and Home Manager.
One repo, one command, and a fresh machine ends up configured the same way every time.

## What you get

Both platforms get a reproducible shell, editor, developer toolchain, agent
workflow, and shared user configuration through Home Manager. macOS also gets
desktop applications and system settings managed by nix-darwin and Homebrew.

The configuration provides a fast Zsh environment, a language-aware Neovim
setup, cloud and container tooling, managed agent extensions, isolated
worktree workflows, and local validation before changes are completed. Push,
pull request, merge, and deployment actions always require explicit approval.

## Long-running agent orchestration

[GNHF](https://github.com/kunchenguid/gnhf) is installed from a source- and
dependency-hash-pinned Nix package on every supported system. Its bundled
agent skill is exposed at `~/.agents/skills/gnhf`, and anonymous GNHF
telemetry is disabled through `GNHF_TELEMETRY=0`.

GNHF's mutable `~/.gnhf/config.yml` remains user-owned. Four launchers make the
worker and sandbox choice explicit on every run:

- `gnhf-codex` runs Codex directly.
- `gnhf-opencode` runs OpenCode directly.
- `gnhf-codex-nono` runs Codex through its Nono sandbox wrapper.
- `gnhf-opencode-nono` runs OpenCode through its Nono sandbox wrapper.

Each launcher supplies GNHF's native `--agent` and per-invocation
`--agent-path` values, so the selected executable wins without editing the
GNHF config. Launchers reject caller-supplied `--agent` and `--agent-path`
options so the selected direct or Nono worker cannot be changed. Custom
`agentPathOverride` entries in `~/.gnhf/config.yml` remain available to the
plain `gnhf` command.

For example:

```sh
gnhf-codex \
  --worktree \
  --max-iterations 10 \
  --stop-when "the requested behavior works, relevant checks pass, and no unrelated files changed" \
  "implement the requested change"

gnhf-opencode-nono \
  --worktree \
  --max-iterations 10 \
  --stop-when "the requested behavior works, relevant checks pass, and no unrelated files changed" \
  "implement the requested change"
```

Both OpenCode launchers use the provider and model selected in OpenCode itself,
including a configured local model. GNHF does not expose a model flag. The
plain `gnhf` command remains available for other upstream-supported agents.

Prefer `--worktree` for unattended work. GNHF requires a clean repository and
can reset a failed iteration before retrying. Worktree mode keeps that activity
outside the current checkout and preserves successful work for review. Do not
use `--push` unless the remote update has been explicitly approved.

## Agent sandbox

Terminal launches of `claude`, `codex`, `opencode`, and `pi` use the upstream
clients directly. To run an agent inside the version-pinned Nono sandbox, use:

```sh
claude-nono
codex-nono
opencode-nono
pi-nono
```

The Nono wrappers make the current Git worktree and an ephemeral per-session
client home writable. Trusted agent instructions, skills, plugins, and
configuration are staged into that home while their host originals remain
read-only. Of each client's durable state, only its dedicated authentication
JSON file is copied into a separate persistent store and synchronized with its
legacy client path using generation checks. Git metadata is isolated per
session, then refs and the index are reconciled only if the host repository has
not changed concurrently.
Parallel linked-worktree sessions use separate lifecycle locks and serialize
only snapshots and reconciliation against their shared Git directory. On
macOS, the real `.git` path remains denied for the full sandbox lifetime while
Git uses the session-local metadata directory.
Launch from a linked worktree when a repository has registered linked
worktrees. Main-checkout launches fail closed so the shared Git directory never
moves out from under another worktree. Active merge, rebase, cherry-pick,
revert, bisect, shallow, sparse-checkout, split-index, and submodule states are
also rejected before isolation begins, as are repositories that use external
Git object alternates.
Launches outside a Git worktree fail closed. SSH keys, cloud configuration,
browser data, unrelated repositories, the general macOS keychain, and
container sockets are not granted.

The first rollout restricts filesystem access, ambient environment variables,
and Unix sockets. Outbound TCP is mediated by Nono's developer proxy so host
control sockets remain unreachable without limiting normal provider, plugin,
documentation, and package-registry traffic. API-key, cloud, Git-hosting,
Docker, Kubernetes, and SSH-agent variables are stripped from the sandboxed
process. Linux grants only the exact multi-user Nix daemon socket needed for
normal Nix builds.

Each `*-nono` wrapper accepts dynamic network allowlist overrides via
environment variables:

- `DOTFILES_NONO_ALLOW_DOMAINS` (default: `chatgpt.com`) adds one or more
  `--allow-domain` entries. Use a comma or space separated list of hostnames or
  URL globs.
- `DOTFILES_NONO_OPEN_PORTS` adds one or more localhost `--open-port` entries
  (for example `11434` for Ollama).

The `opencode-nono` wrapper also grants the validated ephemeral port from an
`opencode serve --port` invocation, including the port selected by GNHF.

On macOS, the codex profile also pins `SSL_CERT_FILE` and
`CODEX_CA_CERTIFICATE` to `/private/etc/ssl/cert.pem` so Codex can validate TLS
certificates inside the sandbox without requiring keychain access.

On macOS, the pi profile pins `OPENSSL_CONF` to
`/private/etc/ssl/openssl.cnf` so Homebrew Node does not try to read
`/opt/homebrew/etc/openssl@3/openssl.cnf`, which is outside the sandbox policy.

Interrupted Git sessions are restored under a per-worktree lock and their
session state is quarantined under `~/.cache/nono/recovery/` for manual
inspection. Reflog-only recovery refs expire after 30 days.

Sign in with the ordinary client before its first Nono session. The Nono
wrapper imports that client's authentication JSON and synchronizes later
changes. If only the host credential file disappears, the next Nono session
restores it from the persistent store. To clear both copies, perform the
client's logout flow from inside its `*-nono` session.

On macOS, a subscription-authenticated client that stores or refreshes
credentials in the login keychain must use the ordinary direct client for the
complete session. The Nono wrapper intentionally cannot reach the general
keychain. Desktop applications and editor-launched processes do not pass
through the terminal wrappers.

Nono uses the official release tarballs with a separate SHA-256 hash for each
supported target. To update it, change the version and target hashes in
`packages/nono.nix`. First evaluate every target from any supported host:

```sh
nix flake check --all-systems --impure --no-build
```

Then run the following native builds on Apple Silicon macOS, Intel macOS,
x86_64 Ubuntu, and aarch64 Ubuntu so every release archive, executable, and
Linux ELF patch is exercised on its target platform:

```sh
system="$(nix eval --impure --raw --expr builtins.currentSystem)"
nix build \
  ".#checks.$system.nono-package" \
  ".#checks.$system.nono-agent-wrappers" \
  ".#checks.$system.nono-home-command-surface" \
  ".#checks.$system.nono-profiles" \
  ".#checks.$system.nono-runtime-driver"
nix run ".#nono-runtime-test"
```

## Supported systems

- macOS on Apple Silicon, by default.
- Intel Mac: set `nixpkgs.hostPlatform = "x86_64-darwin";` in
  `configuration.nix`.
- Headless Ubuntu 24.04 on x86_64 or ARM64. The Ubuntu bootstrap requires a
  non-root user with sudo access and selects the correct architecture automatically.

## Fresh macOS setup

On a brand new Mac, from a bare clone of this repo:

```sh
git clone https://github.com/emolinaro/dotfiles.git
cd dotfiles
```

Before you run it: open the config files and change the values listed in "Make it yours" below (git identity and host label), and read the Homebrew cleanup warning.
`bootstrap.sh` applies the config to your machine, so do this first.

```sh
./bootstrap.sh
```

`bootstrap.sh` does three things, in order:

1. Installs Determinate Nix, if it isn't already installed.
2. Symlinks this repo to `~/.dotfiles`.
   This has to happen before the first build, because `home.nix` points at config files through `~/.dotfiles`.
3. Runs the first `darwin-rebuild switch`.
   It fetches the `darwin-rebuild` tool from the nix-darwin 26.05 release branch, then applies this repo's locked flake config.

After that, `darwin-rebuild` exists and you're on the normal workflow below.

### Validate without applying

Once Nix is installed (`bootstrap.sh` step 1 handles that), you can check that the config builds without touching your system - handy when you have edited something:

```sh
nix flake check --no-build
nix build .#darwinConfigurations.mac.system --dry-run
```

If you renamed the host label in "Make it yours", substitute your label for `mac` in these commands.

### Rebuild macOS

Edit the config files in place, then apply:

```sh
./rebuild.sh
```

That's it.
No separate build-and-copy step.

## Fresh Ubuntu 24.04 setup

Clone the repo as the user who will own the configuration, then run:

```sh
git clone https://github.com/emolinaro/dotfiles.git
cd dotfiles
./bootstrap.sh
```

The Ubuntu setup is headless. Apt installs only system-level prerequisites;
Home Manager installs the shared user environment. Platform-specific package
sources are selected declaratively, and checksum-pinned binary packages choose
the correct archive for each supported architecture. Update checks remain
under Nix control.

The bootstrap supports x86_64 and ARM64, uses the current username and home
directory, changes the login shell to `/usr/bin/zsh`, enables Docker through
systemd, and adds the current user to the `docker` group. Start a new login
session after it completes so the shell and Docker group changes take effect,
then authenticate Codex manually. Restart Codex after a rebuild so it discovers
newly installed agent skills:

```sh
codex login
```

### Rebuild Ubuntu

Apply later changes with:

```sh
./rebuild.sh
```

The root scripts detect macOS or Ubuntu 24.04 and dispatch to the matching
implementation. Platform scripts can also be run directly when needed:

```sh
./scripts/macos/rebuild.sh
./scripts/ubuntu/rebuild.sh
```

Both Ubuntu entry points verify that `/usr/bin/zsh` is the account's login
shell. The rebuild restores it with sudo if it has been changed.

## Update packages and agent workflows

Nix records the exact revisions of package collections and external agent
workflows in `flake.lock`. Update every input from the repository root with:

```sh
nix flake update
```

Update one or more named inputs without changing the others by listing them:

```sh
nix flake update lavish
nix flake update chromeDevtoolsAxi
nix flake update ghAxi
nix flake update gstack
nix flake update superpowers
nix flake update nixpkgs nixpkgs-linux
```

The first rebuild after this layout change moves only the managed gstack
checkout from `~/.gstack/repos/gstack` to
`~/.local/share/gstack/repos/gstack`. Other repositories under
`~/.gstack/repos` remain in place. Home Manager dry runs print the planned
move, and recovery is a direct move back to the original path before the next
rebuild.

Most Nix packages come from a shared Nixpkgs input, so an individual package
such as `kubectl` cannot be updated independently. Updating `nixpkgs` updates
the macOS package collection, while `nixpkgs-linux` updates both Ubuntu
targets. Inputs such as `chromeDevtoolsAxi`, `ghAxi`, `lavish`, `gstack`,
`superpowers`, `herdr`, `home-manager`, and `nix-darwin` can be updated
independently. GNHF, Treehouse, and No Mistakes are versioned separately in
`packages/gnhf.nix`, `packages/treehouse.nix`, and `packages/no-mistakes.nix`.
Updating GNHF requires changing its version, immutable upstream revision,
source hash, and pnpm dependency hash together.

Review and validate every lock update before applying it:

```sh
git diff -- flake.lock
nix flake check --all-systems --impure --no-build
./rebuild.sh
```

Homebrew packages on macOS are not recorded in `flake.lock`; nix-darwin
updates those through the declared Homebrew activation settings.

## Make it yours

This repo is mine.
If you clone it, change these before you run `bootstrap.sh`:

- **macOS user** is detected automatically from the account running the setup. When the scripts invoke `sudo`, the flake uses `SUDO_USER`; otherwise it uses `USER`. Evaluation is intentionally impure so any sudo-capable account can apply the configuration without code changes.
- **Git identity**, in `programs.git.settings.user` in `home.nix`
  (`emolinaro` / `emil.molinaro@gmail.com`).
- **Host label** `"mac"`, in three places: `flake.nix` (the `darwinConfigurations."mac"` name), `scripts/macos/rebuild.sh` (the `#mac` at the end of the flake reference), and `scripts/macos/bootstrap.sh`'s first-switch command (also `#mac`).
  All three have to match.

**Homebrew cleanup warning:** `configuration.nix` sets `homebrew.onActivation.cleanup = "zap"`.
That means every time you switch, Homebrew removes any package or cask on your machine that isn't listed in the `brews` and `casks` arrays in `configuration.nix`.
If you already have Homebrew stuff installed that isn't in that list, the first switch will uninstall it.
Read through `brews` and `casks` before you run `bootstrap.sh` or `rebuild.sh` for the first time, and add anything you want to keep.

## License

This repo is licensed under MIT No Attribution.
It is based on [Kun Chen's dotfiles](https://github.com/kunchenguid/dotfiles),
with additional development and platform support by Emiliano Molinaro.
See `LICENSE`.
