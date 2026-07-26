# dotfiles

My personal macOS and Ubuntu setup, managed with Nix and Home Manager.
One repo, one command, and a fresh machine ends up configured the same way every time.

## What you get

Both platforms use Home Manager for a shared reproducible shell, editor,
developer tooling, and agent workflow; macOS also gets nix-darwin/Homebrew-
managed desktop apps and system settings.

The setup includes Zsh and language-aware Neovim, cloud/container tooling,
managed agent extensions, isolated worktrees, and local validation with explicit
approval for push, pull-request, merge, and deploy actions.

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

Ubuntu is headless: Apt handles OS packages, Home Manager owns user config, and
Nix pins inputs per architecture (`x86_64`/`ARM64`). It then sets `/usr/bin/zsh`
as login shell, enables Docker, adds you to `docker`, and prompts you to reopen
your shell and run:

```sh
codex login
```

### Rebuild Ubuntu

Apply later changes with:

```sh
./rebuild.sh
```

The root scripts choose the right platform rebuild automatically; run platform
scripts directly only when needed:

```sh
./scripts/macos/rebuild.sh
./scripts/ubuntu/rebuild.sh
```

Ubuntu entry points check that `/usr/bin/zsh` is the login shell and restore it
with `sudo` if needed.

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
Each switch removes unlisted Homebrew items, so review `brews` and `casks` before your first bootstrap/rebuild and keep anything needed.

## License

This repo is licensed under MIT No Attribution.
It is based on [Kun Chen's dotfiles](https://github.com/kunchenguid/dotfiles),
with additional development and platform support by Emiliano Molinaro.
See `LICENSE`.
