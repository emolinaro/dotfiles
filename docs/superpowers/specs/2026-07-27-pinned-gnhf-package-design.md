# Pinned GNHF Package Design

## Goal

Replace the runtime `npx -y gnhf` download with a standalone, reproducible
Nix package for GNHF 0.1.42 while preserving every existing `gnhf*` command.

## Current State

`packages/gnhf.nix` produces shell wrappers only. Each wrapper invokes
`npx -y gnhf`, so the resolved GNHF version and its dependencies can change at
every launch and require registry access.

## Approved Design

`packages/gnhf.nix` will become a first-class package module. It will fetch the
`gnhf-v0.1.42` source tag directly from `kunchenguid/gnhf`, use pnpm 11 and
`fetchPnpmDeps` to build the committed lockfile, and install the compiled
`dist/cli.mjs` behind a `gnhf` executable. The source hash and pnpm dependency
hash are fixed Nix inputs, so evaluation and builds do not resolve npm packages
at runtime.

The module will also produce the existing command surface:

- `gnhf` and `gnhf-codex` select the Codex agent.
- `gnhf-opencode` selects the OpenCode agent.
- `gnhf-codex-nono` and `gnhf-opencode-nono` preserve their temporary command
  shims and route the selected client through its Nono wrapper.

Each wrapper invokes the package's store path directly. It does not call `npx`,
use a global npm cache, or download code after installation.

## Constraints

- Pin GNHF to version `0.1.42` and tag `gnhf-v0.1.42`.
- Build from upstream source with its committed `pnpm-lock.yaml` and pnpm 11.
- Preserve the five public commands and their arguments.
- Support `aarch64-darwin`, `x86_64-darwin`, `aarch64-linux`, and
  `x86_64-linux`.
- Keep GNHF independent from Axi Tools. It must not share a package identity,
  source input, or wrapper implementation with Axi Tools.
- Add tests that prove the public wrappers invoke the pinned package and do not
  invoke `npx`.

## Failure Handling

A changed upstream source tree or lockfile must invalidate the corresponding
Nix hash and fail the build. A missing compiled CLI must fail packaging. A
missing Nono client wrapper continues to fail through the selected wrapper as it
does today.

## Verification

The GNHF wrapper check will exercise all five command variants using a fake
pinned GNHF executable and assert their exact agent arguments. The real package
will be built for the current system, and flake evaluation will cover all
declared platforms.
