# Package a Node CLI from its published npm tarball instead of building the
# source tree. The tarball ships dist/, so no TypeScript toolchain and no dev
# dependencies are needed; only the runtime dependencies get installed, by npm,
# inside a fixed-output derivation whose hash pins the result.
#
# Pins are two hashes: `hash` for the tarball, `depsHash` for the installed
# runtime dependency tree. scripts/update-npm-tool.sh refreshes both.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  nodejs,
  cacert,
  pname,
  version,
  hash,
  depsHash,
  entryPoint,
  npmName ? pname,
  runtimeDirs ? [
    "dist"
    "package.json"
    "README.md"
    "skills"
  ],
  description,
  homepage,
  license ? lib.licenses.mit,
}:

let
  src = fetchurl {
    url = "https://registry.npmjs.org/${npmName}/-/${npmName}-${version}.tgz";
    inherit hash;
  };

  runtimeDeps = stdenvNoCC.mkDerivation {
    pname = "${pname}-runtime-deps";
    inherit version src;

    nativeBuildInputs = [
      nodejs
      cacert
    ];

    buildPhase = ''
      runHook preBuild
      export HOME="$TMPDIR"
      # Build sandboxes have no CA bundle, so https fetches from node fail.
      export SSL_CERT_FILE="${cacert}/etc/ssl/certs/ca-bundle.crt"
      export NODE_EXTRA_CA_CERTS="$SSL_CERT_FILE"
      npm install --omit=dev --ignore-scripts --no-audit --no-fund
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -a node_modules "$out/node_modules"
      runHook postInstall
    '';

    dontPatchShebangs = true;
    dontStrip = true;
    dontFixup = true;
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = depsHash;
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    install -dm755 "$out/lib/node_modules/${pname}"
    for entry in ${lib.escapeShellArgs runtimeDirs}; do
      if [ -e "$entry" ]; then
        cp -R "$entry" "$out/lib/node_modules/${pname}/"
      fi
    done
    cp -a ${runtimeDeps}/node_modules "$out/lib/node_modules/${pname}/node_modules"
    makeWrapper ${lib.getExe' nodejs "node"} "$out/bin/${pname}" \
      --add-flags "$out/lib/node_modules/${pname}/${entryPoint}"
    runHook postInstall
  '';

  meta = {
    inherit description homepage license;
    mainProgram = pname;
  };
}
