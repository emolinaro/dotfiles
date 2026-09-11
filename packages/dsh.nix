{
  buildNpmPackage,
  fetchurl,
  jq,
  lib,
  makeWrapper,
  nodejs,
}:

let
  # node-pty and koffi load platform prebuilds directly at runtime; the
  # install scripts that would fetch or compile them are skipped by the
  # npm hooks.
  version = "0.1.5-rc.1";
in
buildNpmPackage {
  pname = "dsh";
  inherit version;

  src = fetchurl {
    url = "https://registry.npmjs.org/@deepseek-ai/dsh/-/dsh-${version}.tgz";
    hash = "sha256-Gnlxnxx2ORisMOgZTfeDqTMMaxLV8EyVBzGj+KHD2dA=";
  };

  # The registry tarball ships only compiled lib/*.js, so there is nothing to
  # build. The runtime-only lockfile is maintained in this repo because the
  # tarball's devDependencies reference packages that are not published on the
  # public registry (@deepseek-ai/dsh-agent-loop-testkit,
  # @deepseek-ai/dsh-experimental-code-runtime-python), which breaks whole-
  # manifest npm resolution. Strip the devDependencies from the manifest so
  # `npm ci` resolves exactly the committed runtime lockfile.
  postPatch = ''
    ${lib.getExe jq} 'del(.devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
    cp ${./dsh-package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-+/9XAzsADxOI4D+w9P6HsoOv4hKLFTeSGYmvWRCnBTg=";

  dontNpmBuild = true;
  dontNpmPrune = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -dm755 "$out/lib/node_modules/@deepseek-ai/dsh"
    cp -r lib package.json node_modules "$out/lib/node_modules/@deepseek-ai/dsh/"
    makeWrapper ${lib.getExe nodejs} "$out/bin/dsh" \
      --add-flags "--expose-internals" \
      --add-flags "$out/lib/node_modules/@deepseek-ai/dsh/lib/bin.js"

    runHook postInstall
  '';

  # --expose-internals: profile boot classifies Node's internal ESM loader
  # through `node-addon-require-builtin`, whose arm64 V8 prologue scanner
  # rejects the Nix-built node binary image (static executable, no LTO).
  # The flag switches cordis-plugin-loader to its supported direct-require
  # path for the same internals, so profile plugin imports resolve from
  # the profile directory instead of the store.

  meta = {
    description = "DeepSeek Harness CLI: profile boot, plugin management, and the browser UI alias";
    homepage = "https://github.com/deepseek-ai/deepseek-harness";
    license = lib.licenses.mit;
    mainProgram = "dsh";
    platforms = lib.platforms.unix;
  };
}
