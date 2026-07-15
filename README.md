# dotfiles

My personal macOS and Ubuntu setup, managed with Nix and Home Manager.
One repo, one command, and a fresh machine ends up configured the same way every time.

## What you get

Both platforms get the shared shell, editor, CLI, and agent configuration. macOS
also gets the desktop and system settings managed by nix-darwin and Homebrew.

Running the platform-specific switch builds:

- System settings (dark mode, key repeat, dock, Finder, trackpad)
- Homebrew apps (casks and CLI tools)
- Nix user packages for shell, Git, Kubernetes, containers, service debugging,
  Neovim, and the Hack Nerd Font
- Shell (zsh, aliases, starship prompt)
- Editor (Neovim config)
- Terminal (WezTerm config)
- Agent configs (Claude, Codex, opencode all share one AGENTS.md)
- Codex extensions (gstack and Superpowers)
- Herdr workspace manager and shared configuration

The developer toolchain includes Python with uv, Ruff, and basedpyright; Go
with gopls, golangci-lint, Delve, and goimports; and shell tooling with
ShellCheck, shfmt, and bash-language-server. Neovim provides completion, LSP
navigation and actions, diagnostics, and format-on-save for these languages.

## Supported systems

- macOS on Apple Silicon, by default.
- Intel Mac: change one line.
  In `configuration.nix`, set `nixpkgs.hostPlatform = "x86_64-darwin";` (the comment right there tells you the same thing).
- Headless Ubuntu 24.04 on x86_64 or ARM64. The Ubuntu bootstrap requires a
  non-root user with sudo access and selects the correct architecture automatically.

## Fresh macOS setup

On a brand new Mac, from a bare clone of this repo:

```sh
git clone https://github.com/emolinaro/dotfiles.git
cd dotfiles
```

Before you run it: open the config files and change the values listed in "Make it yours" below (git identity, host label, and Intel vs Apple Silicon), and read the Homebrew cleanup warning.
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

The Ubuntu setup is headless. It uses apt only for Zsh, Docker Engine, Nix
installer prerequisites, and the system libraries required by gstack's
Chromium browser. Home Manager installs the Nix-managed Docker client and
Compose tooling alongside Codex, Herdr, and the shared dotfiles. Herdr comes
from its pinned upstream Nix flake on Ubuntu; macOS continues to install Herdr
through its declared Homebrew cask. The shared cloud toolkit includes Helm,
k9s, kubectx/kubens, Stern, Dive, yq, grpcurl, HTTPie, Just, and Watchexec.
Headless Ubuntu also gets Lazydocker; macOS uses OrbStack instead.

The bootstrap supports x86_64 and ARM64, uses the current username and home
directory, changes the login shell to `/usr/bin/zsh`, enables Docker through
systemd, and adds the current user to the `docker` group. Start a new login
session after it completes so the shell and Docker group changes take effect,
then authenticate Codex manually. Restart Codex after a rebuild so it discovers
newly installed Superpowers skills:

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

## Make it yours

This repo is mine.
If you clone it, change these before you run `bootstrap.sh`:

- **macOS user** is detected automatically from the account running the setup. When the scripts invoke `sudo`, the flake uses `SUDO_USER`; otherwise it uses `USER`. Evaluation is intentionally impure so any sudo-capable account can apply the configuration without code changes.
- **Git identity**, in `home.nix:43-46` (`emolinaro` / `40191802+emolinaro@users.noreply.github.com`).
- **Host label** `"mac"`, in three places: `flake.nix` (the `darwinConfigurations."mac"` name), `scripts/macos/rebuild.sh` (the `#mac` at the end of the flake reference), and `scripts/macos/bootstrap.sh`'s first-switch command (also `#mac`).
  All three have to match.
- **CPU architecture**, `hostPlatform` in `configuration.nix` (see Prerequisites above).

**Homebrew cleanup warning:** `configuration.nix` sets `homebrew.onActivation.cleanup = "zap"`.
That means every time you switch, Homebrew removes any package or cask on your machine that isn't listed in the `brews` and `casks` arrays in `configuration.nix`.
If you already have Homebrew stuff installed that isn't in that list, the first switch will uninstall it.
Read through `brews` and `casks` before you run `bootstrap.sh` or `rebuild.sh` for the first time, and add anything you want to keep.

## License

This repo is licensed under MIT No Attribution.
It is based on [Kun Chen's dotfiles](https://github.com/kunchenguid/dotfiles),
with additional development and platform support by Emiliano Molinaro.
See `LICENSE`.
