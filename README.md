# dotfiles

My personal macOS and Ubuntu setup, managed with Nix and Home Manager.
One repo, one command, and a fresh machine ends up configured the same way every time.

## What you get

Shared Home Manager config provides a reproducible shell, editor, dev tooling, and
agent workflow on both platforms; macOS adds nix-darwin/Homebrew system and
desktop settings. Zsh, language-aware Neovim, cloud/container tooling, managed
agents, isolated worktrees, and explicit approval gates for push, PR, merge, and deploy are
also included.

## Agent sandbox

Use direct clients normally; use `*-nono` for isolated runs and `gnhf*` for wrappers (`gnhf` defaults to `codex`).

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

`*-nono` runs in an isolated worktree+HOME, syncs only `auth.json`, blocks
history-rewrite, and applies env/network hardening.

```sh
nix run ".#nono-runtime-test"
```

## Supported systems

Supported systems are default Apple Silicon macOS (Intel via `nixpkgs.hostPlatform = "x86_64-darwin"` in `configuration.nix`) and headless Ubuntu 24.04 on x86_64/ARM64 with a non-root sudo user and automatic architecture detection.

## Fresh macOS setup

On a brand new Mac, from a bare clone of this repo:

```sh
git clone https://github.com/emolinaro/dotfiles.git
cd dotfiles
```

Before running bootstrap, update the values in "Make it yours" (git identity and host label), read the Homebrew cleanup warning, then run `./bootstrap.sh`.

```sh
./bootstrap.sh
```

`./bootstrap.sh` installs Nix if missing, links `~/.dotfiles`, runs the first `darwin-rebuild switch` with nix-darwin 26.05, then leaves `darwin-rebuild` available for the normal workflow.

### Validate without applying

After Nix is installed, validate local changes without applying them:

```sh
nix flake check --no-build
nix build .#darwinConfigurations.mac.system --dry-run
```

If you renamed the host label in "Make it yours", substitute your label for `mac` in these commands.

### Rebuild macOS

Edit the config files in place and apply:

```sh
./rebuild.sh
```

No separate build-and-copy step.

## Fresh Ubuntu 24.04 setup

Clone the repo as the user who will own the configuration, then run:

```sh
git clone https://github.com/emolinaro/dotfiles.git
cd dotfiles
./bootstrap.sh
```

On Ubuntu, Apt handles system packages, Home Manager user config, and `bootstrap.sh` handles arch pinning (`x86_64`/`ARM64`), Docker setup, `/usr/bin/zsh`, and the `codex login` prompt after restart.

```sh
codex login
```

### Rebuild Ubuntu

Apply later changes with:

```sh
./rebuild.sh
```

The root scripts pick the right platform automatically; use direct platform
scripts only when needed:

```sh
./scripts/macos/rebuild.sh
./scripts/ubuntu/rebuild.sh
```

Ubuntu entry points enforce `/usr/bin/zsh` as the login shell and restore it with
`sudo` if needed.

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
example `lavish`, `chromeDevtoolsAxi`, `ghAxi`, `superpowers`, `herdr`) updates
independently. Treehouse and No Mistakes stay pinned in `packages/treehouse.nix`
and `packages/no-mistakes.nix`.

Review lock changes before rebuilding:

```sh
git diff -- flake.lock
nix flake check --all-systems --impure --no-build
./rebuild.sh
```

Homebrew packages on macOS are not recorded in `flake.lock`; nix-darwin
updates those through the declared Homebrew activation settings.

## Make it yours

Before first `bootstrap.sh`, update this repo for your environment:

- **macOS user** is auto-detected (`SUDO_USER` first, otherwise `USER`) so any sudo-capable account can apply configuration.
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
