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

## Agent sandbox

Use direct clients normally; use `*-nono` for isolated runs and `gnhf*` for agent wrappers.

```sh
claude-nono
codex-nono
opencode-nono
pi-nono
gnhf
gnhf-codex
gnhf-codex-nono
gnhf-opencode
gnhf-opencode-nono
```

`gnhf` defaults to `codex`; add suffixes for a specific tool.

`*-nono` runs in an isolated worktree+HOME, syncs only `auth.json`, blocks
history-rewriting Git operations, and adds env/network hardening.

```sh
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

`bootstrap.sh` installs Nix if missing, links `~/.dotfiles`, then runs the first `darwin-rebuild switch` with nix-darwin 26.05.

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

Ubuntu is headless: Apt provides OS prerequisites, Home Manager owns shared user
environment configuration, and package inputs are pinned per architecture in
Nix. The bootstrap supports x86_64 and ARM64, sets `/usr/bin/zsh` as your
login shell, enables Docker, adds you to `docker`, then asks you to reopen
your shell and run:

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

Nix stores package and agent source pins in `flake.lock`.

```sh
# Update all inputs
nix flake update

# Update one or a few inputs only
nix flake update nixpkgs nixpkgs-linux
nix flake update gstack
```

`nixpkgs` and `nixpkgs-linux` are shared package inputs; everything else (for
example `lavish`, `chromeDevtoolsAxi`, `ghAxi`, `superpowers`, `herdr`) is
updated independently. External tool bundles like Treehouse and No Mistakes are
pinned in `packages/treehouse.nix` and `packages/no-mistakes.nix`.

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

- **macOS user** is detected automatically (`SUDO_USER` when using `sudo`, otherwise `USER`) so any sudo-capable account can apply configuration.
- **Git identity**, in `programs.git.settings.user` in `home.nix`
  (`emolinaro` / `emil.molinaro@gmail.com`).
- **Host label** `"mac"` in `flake.nix`, `scripts/macos/rebuild.sh`, and `scripts/macos/bootstrap.sh`; all three must match.

**Homebrew cleanup warning:** `configuration.nix` sets `homebrew.onActivation.cleanup = "zap"`.
That means each switch removes Homebrew items not listed in the `brews` and `casks` arrays, so review those lists before first `bootstrap.sh`/`rebuild.sh` and add anything you want to keep.

## License

This repo is licensed under MIT No Attribution.
It is based on [Kun Chen's dotfiles](https://github.com/kunchenguid/dotfiles),
with additional development and platform support by Emiliano Molinaro.
See `LICENSE`.
