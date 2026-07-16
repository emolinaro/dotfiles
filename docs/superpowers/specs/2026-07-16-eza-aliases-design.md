# Eza aliases design

## Goal

Install `eza` through Home Manager on every supported platform and use it for the existing `ls`, `ll`, and `la` Zsh aliases.

## Configuration

- Add `eza` to the shared, alphabetized `home.packages` list in `home.nix`.
- Set `ls` to `${pkgs.eza}/bin/eza --icons=always` exactly as requested.
- Set `ll` to `${pkgs.eza}/bin/eza -laF --icons=always` to retain long, all-files, and classification output.
- Set `la` to `${pkgs.eza}/bin/eza -aF --icons=always` to retain all-files and classification output.
- Use the Nix store path in every alias so alias behavior does not depend on `PATH` ordering.

Eza formats file sizes for people by default, so the GNU `ls` `-h` flag is omitted. In eza, `-h` means `--header` instead.

## Scope and safety

No other shell aliases or packages change. Existing uncommitted edits in the working tree must be preserved.

## Verification

Run the repository formatter or a Nix formatting check, then run `nix flake check --no-build`. Inspect the focused diff to confirm only the intended package and alias lines changed during implementation.
