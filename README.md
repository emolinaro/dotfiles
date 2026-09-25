# dotfiles

My personal macOS, Ubuntu, and Arch Linux setup, managed with Nix and Home Manager.
One repo, one command, and a fresh machine ends up configured the same way every time.

## What you get

Both platforms get a reproducible shell, editor, developer toolchain, agent
workflow, and shared user configuration through Home Manager. macOS also gets
desktop applications and system settings managed by nix-darwin and Homebrew.

The configuration provides a fast Zsh environment, a language-aware Neovim
setup, cloud and container tooling, managed agent extensions, isolated
worktree workflows, and local validation before changes are completed. Push,
pull request, merge, and deployment actions always require explicit approval.

## Agent sandbox

Use direct clients normally; use `*-nono` for isolated runs. For unattended
GNHF loops, pass `--agent <name>` to select the backend. The selected backend
becomes GNHF's default; a new GNHF configuration starts with Claude.

```sh
claude-nono
codex-nono
opencode-nono
pi-nono
gnhf --agent codex "your objective"
gnhf --agent opencode "your objective"
```

- `*-nono`: isolated worktree+HOME; only `auth.json` syncs back.
- Git/reconcile: local `reflog`+`index`; remote refs sync only from a clean host.
- Runtime: blocks merge/rebase/cherry-pick/revert/bisect; unusable in sparse/split-index/submodule/alternate-object/unlinked states.
- Hardening: strips sensitive env; proxy-only egress via allowlist (`DOTFILES_NONO_ALLOW_DOMAINS`, `chatgpt.com`) + `DOTFILES_NONO_OPEN_PORTS`; disables keychain/cert/browser/container access.
- TLS/recovery: codex sets `SSL_CERT_FILE`+`CODEX_CA_CERTIFICATE`, pi sets `OPENSSL_CONF`; recovery in `~/.cache/nono/recovery/` (30d), re-auth direct client if keychain creds disappear.
- Validation:

```sh
nix fmt  # Nix (nixfmt, RFC style) plus shell (shfmt -i 2 -ci)

nix flake check --all-systems --impure --no-build

nix build .#ci
nix run ".#nono-runtime-test"
```

`.#ci` builds every check for the current system, including `format`, which
re-runs nixfmt/shfmt in check mode, and `shell-lint`, which runs shellcheck over
every script.

## Supported systems

- macOS on Apple Silicon, by default.
- Intel Mac: set `nixpkgs.hostPlatform = "x86_64-darwin";` in
  `configuration.nix`.
- Headless Ubuntu 24.04 or 26.04 or Arch Linux (including Arch Linux ARM)
  on x86_64 or ARM64. The Linux bootstrap requires a non-root user with sudo
  access and selects the correct architecture automatically.

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
   It fetches the `darwin-rebuild` tool at the exact nix-darwin revision pinned in `flake.lock`, then applies this repo's locked flake config.

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

## Fresh Ubuntu or Arch setup

Clone the repo as the user who will own the configuration, then run:

```sh
git clone https://github.com/emolinaro/dotfiles.git
cd dotfiles
./bootstrap.sh
```

The Linux setup is headless. The distro package manager installs only
system-level prerequisites; Home Manager installs the shared user environment.
Platform-specific package sources are selected declaratively, and
checksum-pinned binary packages choose the correct archive for each supported
architecture. Update checks remain under Nix control.

The bootstrap supports Ubuntu and Arch Linux on x86_64 and ARM64, uses the
current username and home directory, changes the login shell to
`/usr/bin/zsh`, enables Docker through systemd, and adds the current user to
the `docker` group. On Ubuntu it additionally relaxes the default AppArmor
restriction on unprivileged user namespaces (required by Codex's bubblewrap
sandbox); Arch does not restrict them, so the step is skipped. Start a new
login session after it completes so the shell and Docker group changes take
effect, then authenticate Codex manually. Restart Codex after a rebuild so it
discovers newly installed agent skills:

```sh
codex login
```

### Rebuild Linux

Apply later changes with:

```sh
./rebuild.sh
```

The root scripts detect macOS or a [supported Linux distribution](#supported-systems)
and dispatch to the matching implementation. Platform scripts can also be run
directly when needed:

```sh
./scripts/macos/rebuild.sh
./scripts/linux/rebuild.sh
```

## Check and reclaim disk space

Run the managed disk-usage report from the dotfiles checkout:

```sh
cd ~/.dotfiles
./disk-usage.sh
```

It reports the space used by Nix, Homebrew, gstack, and related caches. If the
Nix store is using too much space, delete old Nix generations with:

```sh
nix-collect-garbage -d
```

This permanently removes old generations, so you can no longer roll back to
them.

## Update packages and agent workflows

Nix records the exact revisions of package collections and external agent
workflows in `flake.lock`. Update every input from the repository root with:

```sh
nix flake update
```

Update one or more named inputs without changing the others by listing them
in a single command:

```sh
nix flake update lavish chromeDevtoolsAxi ghAxi quotaAxi tasksAxi gnhf gstack superpowers
```

Linux agent CLIs split by update cadence. Claude, Codex, and OpenCode
release daily and nixpkgs trails upstream by days to weeks, so they are
pinned directly to GitHub release tarballs in `packages/` and updated with
the release script (same flow as no-mistakes and treehouse):

```sh
./update-release.sh claude-code codex opencode
./rebuild.sh
```

Pi is npm-only upstream and moves slowly enough to stay on the separately
pinned unstable nixpkgs input. Update Pi without changing the main Linux
package set:

```sh
nix flake update nixpkgs-agents
./rebuild.sh
```

Every input updates independently:

| Input | Contents |
| --- | --- |
| `nixpkgs` | Package collection for macOS |
| `nixpkgs-linux` | Package collection for both Linux targets |
| `nixpkgs-agents` | Unstable package collection for the Linux Pi agent CLI |
| `lavish`, `chromeDevtoolsAxi`, `ghAxi`, `quotaAxi`, `tasksAxi` | Axi tool sources and skills |
| `gnhf` | GNHF CLI source |
| `gstack`, `superpowers` | Agent workflow skills |
| `herdr`, `home-manager`, `nix-darwin`, `nix-homebrew` | Platform tooling and Nix modules |

The first rebuild after this layout change moves only the managed gstack
checkout from `~/.gstack/repos/gstack` to
`~/.local/share/gstack/repos/gstack`. Other repositories under
`~/.gstack/repos` remain in place. Home Manager dry runs print the planned
move, and recovery is a direct move back to the original path before the next
rebuild.

Most Nix packages come from a shared Nixpkgs input, so an individual package
such as `kubectl` cannot be updated independently. Precompiled release
packages (`no-mistakes`, `treehouse`, `nono`, and the agent CLIs
`claude-code`, `codex`, `opencode`) pin their version and per-platform
tarball hashes in `packages/`. Update one to its latest GitHub release with:

```sh
./update-release.sh no-mistakes
```

Pass an explicit version to pin something other than the latest release:

```sh
./update-release.sh treehouse 2.2.0
```

The script resolves the release, prefetches every platform tarball, and
rewrites the pinned version and hashes in `packages/<tool>.nix`. Source-built
Axi Tools and GNHF also pin `pnpmDepsHash` in `flake.nix`, which may need
refreshing after an input update if dependencies changed.

Home Manager installs `chrome-devtools-axi`, `gh-axi`, `lavish-axi`,
`quota-axi`, and `tasks-axi` on `PATH` after a rebuild.

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
  (`emolinaro` / `40191802+emolinaro@users.noreply.github.com`).
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
