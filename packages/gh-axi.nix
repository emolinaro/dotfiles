# Pinned npm artifact; refresh with scripts/update-npm-tool.sh gh-axi
{ callPackage, lib }:
callPackage ./npm-tool.nix {
  pname = "gh-axi";
  version = "0.1.45";
  entryPoint = "dist/bin/gh-axi.js";
  hash = "sha256-orhnUfPzQD5E2QuvAT7cFgLagqJn6RcoI8AyJfCkV2g=";
  depsHash = "sha256-CUHI22cSaS9kHen+BetJ20XkYasWDgb37fZFX7qqoTw=";
  description = "GitHub operations across issues, pull requests, workflows and releases";
  homepage = "https://github.com/kunchenguid/gh-axi";
}
