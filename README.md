# dotfiles

Nix and Home Manager set up macOS and Ubuntu from one repo with one command.

## What you get

Shared Home Manager base; macOS adds nix-darwin/Homebrew, tooling, managed agents, isolated worktrees, and approval checks.

## Agent sandbox

Use direct clients by default; `*-nono` wrappers (`gnhf*`, `gnhf`→`codex`) run in isolated worktree+HOME with `auth.json`-only sync, history protection, and hardened env/network.

```sh
nix run ".#nono-runtime-test"
```

## Supported systems

Supported: Apple Silicon macOS (Intel via `nixpkgs.hostPlatform = "x86_64-darwin"`), plus headless Ubuntu 24.04 on x86_64/ARM64 with non-root sudo and arch auto-detection.

## Fresh macOS setup

On a brand new Mac, from a bare clone of this repo:

```sh
git clone https://github.com/emolinaro/dotfiles.git
cd dotfiles
```

Before bootstrap, update Make it yours, review Homebrew cleanup, then run `./bootstrap.sh`.

```sh
./bootstrap.sh
```

`./bootstrap.sh` installs Nix, links `~/.dotfiles`, runs the first `darwin-rebuild switch` with nix-darwin 26.05, and keeps `darwin-rebuild` for regular use.

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

No separate build-and-copy step.

## Fresh Ubuntu 24.04 setup

Clone the repo as the user who will own the configuration, then run:

```sh
git clone https://github.com/emolinaro/dotfiles.git
cd dotfiles
./bootstrap.sh
```

`./bootstrap.sh` uses Apt for system and Home Manager for user, auto-detects architecture, enables Docker and `/usr/bin/zsh`, and prompts for `codex login` after restart.

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

Ubuntu scripts enforce `/usr/bin/zsh` as the login shell and restore it with
`sudo` if required.

## Update packages and agent workflows

Nix stores package and agent source pins in `flake.lock`.

```sh
# Update all inputs
nix flake update

# Update one or a few inputs only
nix flake update nixpkgs nixpkgs-linux
nix flake update gstack
```

Only `nixpkgs` and `nixpkgs-linux` are shared; pin other inputs in `packages/treehouse.nix` or `packages/no-mistakes.nix`.

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
- **Host label** `"mac"` in `flake.nix`, `scripts/macos/rebuild.sh`, and `scripts/macos/bootstrap.sh`; all three must match.

**Homebrew cleanup warning:** `homebrew.onActivation.cleanup = "zap"` removes unlisted Homebrew items on each switch, so review `brews`/`casks` before first bootstrap/rebuild.

## License

Licensed under MIT No Attribution, based on [Kun Chen's dotfiles](https://github.com/kunchenguid/dotfiles), with additional development and platform support by Emiliano Molinaro.
See `LICENSE`.
