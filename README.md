# dotfiles

Nix and Home Manager set up macOS and Ubuntu from one repo with one command.

## What you get

Shared Home Manager base; macOS adds nix-darwin/Homebrew, tooling, managed agents, isolation, and approvals.

## Agent sandbox

Normal clients run directly; `*-nono` wrappers (`gnhf*`, `gnhf`→`codex`) use isolated worktree+HOME, `auth.json`-only sync, and hardened history, env, and network.

```sh
nix run ".#nono-runtime-test"
```

## Supported systems

Supported: Apple Silicon macOS (Intel via `nixpkgs.hostPlatform = "x86_64-darwin"`), plus Ubuntu 24.04 (x86_64/ARM64) with non-root sudo and auto-arch detection.

## Fresh macOS setup

On a fresh Mac, clone this repo:

```sh
git clone https://github.com/emolinaro/dotfiles.git
cd dotfiles
```

Before bootstrap, update Make it yours and review Homebrew cleanup.

```sh
./bootstrap.sh
```

`./bootstrap.sh` installs Nix, links `~/.dotfiles`, and runs `darwin-rebuild switch`.

### Validate without applying

Validate local changes without applying:

```sh
nix flake check --no-build
nix build .#darwinConfigurations.mac.system --dry-run
```

If renamed, replace `mac` with your label in both commands.

### Rebuild macOS

Edit the config files in place and apply:

```sh
./rebuild.sh
```

## Fresh Ubuntu 24.04 setup

Clone as the config owner, then run:

```sh
git clone https://github.com/emolinaro/dotfiles.git
cd dotfiles
./bootstrap.sh
```

`./bootstrap.sh` uses Apt for system and Home Manager for user, auto-detects arch, enables Docker and `/usr/bin/zsh`, then prompts for `codex login` after restart.

```sh
codex login
```

### Rebuild Ubuntu

Apply later changes with:

```sh
./rebuild.sh
```

`./rebuild.sh` auto-detects the platform; use direct scripts only when needed:

```sh
./scripts/macos/rebuild.sh
./scripts/ubuntu/rebuild.sh
```

Ubuntu rebuild scripts enforce `/usr/bin/zsh` login and restore via `sudo` when needed.

## Update packages and agent workflows

Package and agent pins live in `flake.lock`.

```sh
# Update all inputs
nix flake update

# Update one or a few inputs only
nix flake update nixpkgs nixpkgs-linux
nix flake update gstack
```

Only `nixpkgs` and `nixpkgs-linux` are shared; pin others in `packages/treehouse.nix` or `packages/no-mistakes.nix`.

Review lock changes before rebuilding:

```sh
git diff -- flake.lock
nix flake check --all-systems --impure --no-build
./rebuild.sh
```

Homebrew on macOS is managed by nix-darwin activation, not `flake.lock`.

## Make it yours

Before first `bootstrap.sh`, update this repo for your environment:

- **macOS user** resolves to `SUDO_USER` with `USER` as fallback.
- **Git identity**: `programs.git.settings.user` in `home.nix` (`emolinaro` / `emil.molinaro@gmail.com`).
- **Host label** set `"mac"` consistently in `flake.nix`, `scripts/macos/rebuild.sh`, and `scripts/macos/bootstrap.sh`.

**Homebrew cleanup warning:** `homebrew.onActivation.cleanup = "zap"` removes unlisted Homebrew items on each switch, so review `brews`/`casks` before first bootstrap/rebuild.

## License

Licensed under MIT No Attribution, based on [Kun Chen's dotfiles](https://github.com/kunchenguid/dotfiles), with additional development and platform support by Emiliano Molinaro.
See `LICENSE`.
