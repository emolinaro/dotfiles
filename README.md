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
- Headless Ubuntu 24.04 or 26.04 or Arch Linux (including Arch Linux ARM and Omarchy)
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

The Linux setup runs headless or on a desktop. The distro package manager
installs only system-level prerequisites; Home Manager installs the shared
user environment, including WezTerm with the same configuration macOS uses.
Platform-specific package sources are selected declaratively, and
checksum-pinned binary packages choose the correct archive for each supported
architecture. Update checks remain under Nix control.

The bootstrap supports Ubuntu and Arch Linux (including Omarchy) on x86_64 and ARM64, uses the
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

## Upgrading Nix itself

Nix is installed by the Determinate installer and is deliberately outside this
flake (`configuration.nix` sets `nix.enable = false`), so `./rebuild.sh` never
touches the daemon or `/etc/nix/nix.conf`. Rebuilds pin your packages; they do
not move the daemon.

```sh
./nix-upgrade.sh --check   # running and latest versions
./nix-upgrade.sh           # upgrade to the latest stable, smoke test it
./rebuild.sh
```

`nix-upgrade.sh` only reports success after its smoke test passes: the daemon
answers, store writes work, and the config still evaluates and schedules
substitutes. It refuses to upgrade while a rebuild is running unless you pass
`--force`, because upgrading restarts the daemon. Run it when `--check` reports
a newer release, or when a rebuild misbehaves. Pass an explicit version to pin
the daemon instead of following stable: `./nix-upgrade.sh 3.24.1`.

### Diagnose the daemon

Check the daemon first when a rebuild hangs: a wedged daemon looks exactly like
a slow download, and a bounded smoke test turns an hour of waiting into an
immediate error.

`./doctor.sh` reports the daemon version against the pin and the latest release,
FlakeHub auth state (logged-out is expected here, since only private flakes need
it), substituter latency, `/nix` free space, and whether a build is in flight.
It then runs the same bounded smoke test. `./doctor.sh --quick` skips it.

### Priming the store

Root keeps its own eval and fetcher caches, so a `sudo` build imports the flake
input source trees itself. Where file creation is expensive (an endpoint
security filter, a network volume, a machine reindexing after an OS update) that
import dominates the rebuild, and an interrupted one leaves a lock that stalls
every later build. `./rebuild.sh` therefore primes as the invoking user first,
and the same step is available on its own:

```sh
./nix-prime.sh
```

It runs two steps in order: `nix flake archive` to fetch every input source tree
into the store, then `nix build` for every output. Both run as you, never as
`root`, and each reports how long it took:

```
==> Priming flake inputs
    'flake inputs' done in 47m12s
==> Priming build outputs
    'build outputs' done in 3m4s
```

A `waiting for lock` silence counts as a deadlock only when nothing is being
built: the stalled client is killed, the Nix daemon restarted, and the step
retried once. A lock held by a concurrent build is left alone.

Run it after a flake update, when new input revisions need new source trees, or
before a rebuild when you want the slow part visible. It is never required,
because `./rebuild.sh` primes automatically, and it is a no-op once everything
is present, so repeat runs cost seconds.

```sh
./nix-prime.sh --help
./nix-prime.sh /path/to/other/flake
NIX_LOCK_GRACE_SECONDS=300 ./nix-prime.sh   # accept longer silent lock waits
```

Skip priming inside a rebuild with `DOTFILES_SKIP_PRIME=1 ./rebuild.sh`.

## Check and reclaim disk space

Run the managed disk-usage report from the dotfiles checkout:

```sh
cd ~/.dotfiles
./disk-usage.sh
```

It reports the space used by Nix, Homebrew, gstack, and related caches. When the
Nix store is using too much space, reclaim it from the dotfiles checkout:

```sh
./disk-clean.sh            # reclaim
./disk-clean.sh --dry-run  # show what would be removed
```

It collects old generations of your profiles and of root's profile, collects
dead store paths, hard-links duplicate files in the store, and caps the systemd
journal at 300 MiB. This permanently removes old generations, so you can no
longer roll back to them; the generation that is currently active is never
touched. Run it after switching, or when a rebuild warns that free space is
low.

The order matters and the script handles it: generations go first so their
closures become unreachable, then the store is collected, then the surviving
files are hard-linked together. `nix-collect-garbage -d` on its own is not
enough: it only reaches profiles you own, so root's generations stay in
`/nix/var/nix/profiles/per-user/root/profile` and keep their closure alive.

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

Linux agent CLIs use a separately pinned unstable package collection. Update
Claude, Codex, OpenCode, and Pi without changing the main Linux package set:

```sh
nix flake update nixpkgs-agents
./rebuild.sh
```

New input revisions mean new source trees. `./rebuild.sh` primes those as your
user before the privileged switch, so a cold import never lands inside `sudo`.
If you want to get that work out of the way first, run `./nix-prime.sh`.

Every input updates independently:

| Input | Contents |
| --- | --- |
| `nixpkgs` | Package collection for macOS |
| `nixpkgs-linux` | Package collection for both Linux targets |
| `nixpkgs-agents` | Unstable package collection for Linux agent CLIs |
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
packages (`no-mistakes`, `treehouse`, `nono`) pin their version and per-platform
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
updates those through the declared Homebrew activation settings. The Nix
daemon is not recorded there either; see [Upgrading Nix itself](#upgrading-nix-itself).

## Make it yours

This repo is mine.
If you clone it, change these before you run `bootstrap.sh`:

- **macOS user** is detected automatically from the account running the setup. When the scripts invoke `sudo`, the flake uses `SUDO_USER`; otherwise it uses `USER`. Evaluation is intentionally impure so any sudo-capable account can apply the configuration without code changes.
- **Git identity**, in `programs.git.settings.user` in `home.nix`
  (`emolinaro` / `40191802+emolinaro@users.noreply.github.com`).
- **Host label** `"mac"`, in three places: `flake.nix` (the `darwinConfigurations."mac"` name), `scripts/macos/rebuild.sh` (the `#mac` at the end of the flake reference), and `scripts/macos/bootstrap.sh`'s first-switch command (also `#mac`).
  All three have to match. `scripts/lib-nix.sh` reuses the same label for the smoke test in `./doctor.sh` and `./nix-upgrade.sh`; change it there too, or override it with `DOTFILES_HOST`.

**Homebrew cleanup warning:** `configuration.nix` sets `homebrew.onActivation.cleanup = "zap"`.
That means every time you switch, Homebrew removes any package or cask on your machine that isn't listed in the `brews` and `casks` arrays in `configuration.nix`.
If you already have Homebrew stuff installed that isn't in that list, the first switch will uninstall it.
Read through `brews` and `casks` before you run `bootstrap.sh` or `rebuild.sh` for the first time, and add anything you want to keep.

## License

This repo is licensed under MIT No Attribution.
It is based on [Kun Chen's dotfiles](https://github.com/kunchenguid/dotfiles),
with additional development and platform support by Emiliano Molinaro.
See `LICENSE`.
