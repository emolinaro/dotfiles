{ buildNpmPackage
, coreutils
, fetchurl
, lib
, symlinkJoin
, writeShellScriptBin
,
}:

let
  version = "0.1.41";
  npmPackage = fetchurl {
    url = "https://registry.npmjs.org/gnhf/-/gnhf-0.1.41.tgz";
    hash = "sha256-LrohL6wV3TboFHzmyt4xnW0y8IE+dvGqdFx35AcuAm8=";
  };
  npmLock = fetchurl {
    url = "https://raw.githubusercontent.com/kunchenguid/gnhf/gnhf-v0.1.41/package-lock.json";
    hash = "sha256-k1K0nYREhTyxmPoTWHmMjuMYq+gl1FEH3/U//iYJsGk=";
  };
  gnhfBinary = buildNpmPackage {
    pname = "gnhf";
    inherit version;
    src = npmPackage;
    sourceRoot = "package";
    dontNpmBuild = true;
    npmDepsHash = "sha256-QvU0AbTEbdylqUcrPEdQrO2DbF99qncsMBH3qdXCuSc=";
    postPatch = ''
      cp ${npmLock} package-lock.json
    '';
  };

  gnhfWrapper = writeShellScriptBin "gnhf" ''
    exec ${gnhfBinary}/bin/gnhf "$@"
  '';
  gnhfCodexWrapper = writeShellScriptBin "gnhf-codex" ''
    exec ${gnhfBinary}/bin/gnhf --agent codex "$@"
  '';
  gnhfOpencodeWrapper = writeShellScriptBin "gnhf-opencode" ''
    exec ${gnhfBinary}/bin/gnhf --agent opencode "$@"
  '';
  gnhfCodexNonoWrapper = writeShellScriptBin "gnhf-codex-nono" ''
    set -euo pipefail

    sandbox_bin="$(command -v codex-nono || true)"
    if [ -z "$sandbox_bin" ]; then
      echo "error: codex-nono wrapper is not installed" >&2
      exit 1
    fi

    wrapper_dir=$(${coreutils}/bin/mktemp -d)
    cleanup() {
      ${coreutils}/bin/rm -rf "$wrapper_dir"
    }
    trap cleanup EXIT

    ${coreutils}/bin/ln -s "$sandbox_bin" "$wrapper_dir/codex"
    PATH="$wrapper_dir:$PATH" exec ${gnhfBinary}/bin/gnhf --agent codex "$@"
  '';
  gnhfOpencodeNonoWrapper = writeShellScriptBin "gnhf-opencode-nono" ''
    set -euo pipefail

    sandbox_bin="$(command -v opencode-nono || true)"
    if [ -z "$sandbox_bin" ]; then
      echo "error: opencode-nono wrapper is not installed" >&2
      exit 1
    fi

    wrapper_dir=$(${coreutils}/bin/mktemp -d)
    cleanup() {
      ${coreutils}/bin/rm -rf "$wrapper_dir"
    }
    trap cleanup EXIT

    ${coreutils}/bin/ln -s "$sandbox_bin" "$wrapper_dir/opencode"
    PATH="$wrapper_dir:$PATH" exec ${gnhfBinary}/bin/gnhf --agent opencode "$@"
  '';
in
symlinkJoin {
  name = "gnhf";
  inherit version;
  paths = [
    gnhfWrapper
    gnhfCodexWrapper
    gnhfOpencodeWrapper
    gnhfCodexNonoWrapper
    gnhfOpencodeNonoWrapper
  ];
  meta = {
    description = "gnhf orchestrator CLI with quick agent wrappers";
    homepage = "https://github.com/kunchenguid/gnhf";
    license = lib.licenses.mit;
  };
}
