# Dynamic Darwin User Design

## Goal

Allow any sudo-capable macOS account to apply the dotfiles without changing hardcoded usernames or home paths.

## User resolution

The flake will resolve the account running the setup from the process environment during impure evaluation:

1. Use `SUDO_USER` when it is set and is not `root`.
2. Otherwise use `USER` when it is set and is not `root`.
3. Reject evaluation when neither variable identifies a non-root account.

The Darwin home directory will be derived as `/Users/${darwinUsername}`.

## Configuration flow

`flake.nix` will use the resolved username and home directory for the dynamic Home Manager user attribute and its `extraSpecialArgs`. It will also pass both values to `configuration.nix`, which will use them for `system.primaryUser`, `users.users`, and `nix-homebrew.user`.

Ubuntu keeps its existing `DOTFILES_USERNAME` and `DOTFILES_HOME` resolution behavior.

## Invocation

Darwin evaluation must use `--impure`, because pure flake evaluation cannot read `SUDO_USER` or `USER`. Both direct invocation by a sudo-capable account and invocation through `sudo` are supported.

## Failure behavior

The flake must fail with a clear message rather than configure the root account when the environment contains no non-root invoking user.

## Validation

Evaluate the Darwin configuration with:

- `USER` set to a non-root test account and `SUDO_USER` unset.
- `SUDO_USER` set to a non-root test account while `USER=root`.
- Both variables missing or resolving to `root`, which must fail clearly.

Evaluate both Ubuntu Home Manager outputs to verify that their behavior is unchanged.
