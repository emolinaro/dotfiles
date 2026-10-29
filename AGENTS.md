# Project notes for agents

Deliberate decisions in this repo - do NOT silently revert them:

- `packages/wezterm.nix` wraps Linux WezTerm with the nixpkgs Mesa stack on purpose. The Nix binary runs against nixpkgs glibc, so it fails to create a window without EGL vendor configuration and crashes if pointed at the distro's OpenGL libraries. macOS is unaffected: WezTerm still comes from the Homebrew cask in `configuration.nix`, and `wezterm.lua` keeps its macOS-only WebGpu front end.
- `homebrew.onActivation.cleanup = "zap"` in `configuration.nix` is intentional. It forces the good habit of declaring every Homebrew package in the Nix config instead of installing things ad-hoc, which keeps the machine reproducible. Do not soften it to `uninstall` or `none`. Users are warned about its effect in README.md; this note is for anyone tempted to change the setting itself.
- Never commit `.no-mistakes/` validation evidence to this public repo. `.no-mistakes/` is gitignored; if a validation pipeline stages evidence into a branch, drop it before merging.
- Nix itself is outside the flake on purpose: `configuration.nix` sets `nix.enable = false` because the Determinate installer owns the daemon, `/etc/nix/nix.conf`, and its upgrade path. Do not "fix" daemon problems by flipping that flag. Daemon upgrades go through `./nix-upgrade.sh`, which verifies the daemon with a smoke test; `./doctor.sh` diagnoses a suspected wedge, and `./nix-prime.sh` warms the store as the invoking user.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.