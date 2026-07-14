# dotfiles

My personal macOS and Ubuntu setup, managed with Nix and Home Manager.
One repo, one command, and a fresh machine ends up configured the same way every time.

## What you get

Both platforms get the shared shell, editor, CLI, and agent configuration. macOS
also gets the desktop and system settings managed by nix-darwin and Homebrew.

Running the platform-specific switch builds:

- System settings (dark mode, key repeat, dock, Finder, trackpad)
- Homebrew apps (casks and CLI tools)
- Nix user packages (ripgrep, fd, fzf, jq, lazygit, Neovim, Hack Nerd Font)
- Shell (zsh, aliases, starship prompt)
- Editor (Neovim config)
- Terminal (WezTerm config)
- Agent configs (Claude, Codex, opencode all share one AGENTS.md)
- Codex extensions (gstack and Superpowers)

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

Before you run it: open the config files and change the values listed in "Make it yours" below (username, home path, git identity, host label, and Intel vs Apple Silicon), and read the Homebrew cleanup warning.
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
./bootstrap-ubuntu.sh
```

The Ubuntu setup is headless. It uses apt only for Zsh, Docker Engine, Nix
installer prerequisites, and the system libraries required by gstack's
Chromium browser. Home Manager installs the Nix-managed Docker client and
Compose tooling alongside Codex and the shared dotfiles.

The bootstrap supports x86_64 and ARM64, uses the current username and home
directory, changes the login shell to `/usr/bin/zsh`, enables Docker through
systemd, and adds the current user to the `docker` group. Start a new login
session after it completes so the shell and Docker group changes take effect,
then authenticate Codex manually:

```sh
codex login
```

### Rebuild Ubuntu

Apply later changes with:

```sh
./rebuild-ubuntu.sh
```

The macOS and Ubuntu entry points are intentionally separate. Choose the script
matching the machine instead of running both.

## Make it yours

This repo is mine.
If you clone it, change these before you run `bootstrap.sh`:

- **Username and home path** `molinaro` / `/Users/molinaro`, in four places: `flake.nix:26`, `configuration.nix:10-12`, `configuration.nix:30` (the `nix-homebrew.user` setting), and `home.nix:8-9`.
- **Git identity**, in `home.nix:43-46` (`emolinaro` / `40191802+emolinaro@users.noreply.github.com`).
- **Host label** `"mac"`, in three places: `flake.nix:18` (the `darwinConfigurations."mac"` name), `rebuild.sh:5` (the `#mac` at the end of the flake reference), and `bootstrap.sh`'s first-switch command (also `#mac`).
  All three have to match.
- **CPU architecture**, `hostPlatform` in `configuration.nix` (see Prerequisites above).

**Homebrew cleanup warning:** `configuration.nix` sets `homebrew.onActivation.cleanup = "zap"`.
That means every time you switch, Homebrew removes any package or cask on your machine that isn't listed in the `brews` and `casks` arrays in `configuration.nix`.
If you already have Homebrew stuff installed that isn't in that list, the first switch will uninstall it.
Read through `brews` and `casks` before you run `bootstrap.sh` or `rebuild.sh` for the first time, and add anything you want to keep.

## License

This repo is licensed under MIT No Attribution.
See `LICENSE`.
