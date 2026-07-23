# Opt-in Nono Agent Wrappers

## Goal

Make each coding agent's ordinary command launch the unmodified, unsandboxed
agent. Provide Nono sandboxing only through an explicit command whose name ends
in `-nono`.

## Command interface

The installed commands will be:

| Agent | Ordinary command | Nono command |
| --- | --- | --- |
| Claude Code | `claude` | `claude-nono` |
| Codex | `codex` | `codex-nono` |
| OpenCode | `opencode` | `opencode-nono` |
| Pi | `pi` | `pi-nono` |

The ordinary commands will be the upstream executables without wrapper-added
arguments, environment changes, authentication synchronization, or warnings.
The `claude-unsafe`, `codex-unsafe`, `opencode-unsafe`, and `pi-unsafe`
commands will be removed.

## Architecture

`packages/nono-agent-wrappers.nix` will continue to build the existing Nono
launcher for every entry in `packages/nono-agents.nix`, but each generated
launcher will be installed as `<agent>-nono`. The Nono profiles, sandbox
permissions, session-local home, Git metadata isolation, recovery handling,
credential synchronization, and agent-specific arguments will remain
unchanged.

The wrapper package will contain only the `*-nono` commands. It will not
provide the ordinary agent names or compatibility aliases for the removed
`*-unsafe` commands.

On macOS, the ordinary executables will continue to come from the existing
Homebrew declarations in `configuration.nix`. On Linux, the existing Nix agent
packages will be added directly to `home.packages` so their ordinary command
names are available independently of the wrapper package.

## Runtime behavior

Invoking an ordinary command executes the upstream agent directly. Invoking a
`*-nono` command enters the same fail-closed sandbox flow used by the current
ordinary wrapper, including validation of the working tree, isolated Git
metadata, staged agent configuration, persistent authentication import and
export, and cleanup or recovery after the session.

Missing profiles, missing upstream executables, unsafe home paths, unsupported
Git states, and sandbox failures retain their current errors and exit codes.

## Documentation

README guidance will describe Nono as opt-in, list all four `*-nono` commands,
and remove instructions for the old `*-unsafe` commands. Existing profile and
package update instructions will remain applicable.

## Testing

Tests will first be changed to express the new command interface and observed
failing before production code changes. Wrapper tests will then verify:

- every registered agent has a working `<agent>-nono` command;
- arguments, standard input, environment filtering, isolation, authentication,
  cleanup, and recovery continue to behave as before;
- the wrapper package does not expose ordinary agent names;
- the wrapper package does not expose `*-unsafe` names; and
- missing-profile and missing-executable failures use the renamed commands.

The runtime driver will invoke `codex-nono`, `pi-nono`, and the other renamed
wrappers wherever it currently invokes sandboxed ordinary commands. Its unsafe
logout scenario will be replaced with a host-side authentication change
followed by a sandboxed launch, preserving coverage of authentication
synchronization without an unsafe wrapper.

Repository formatting, evaluation, wrapper checks, profile checks, package
checks, and the native runtime test will be run before completion.

## Scope

This change does not alter agent versions, agent configuration, Nono profiles,
sandbox permissions, or the deliberate Homebrew cleanup policy. It does not
add compatibility aliases for old wrapper command names.
