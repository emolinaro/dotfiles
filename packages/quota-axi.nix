{
  fetchPnpmDeps,
  lib,
  makeWrapper,
  nodejs,
  pnpmConfigHook,
  pnpm_11,
  quotaAxiSource,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "quota-axi";
  version = (builtins.fromJSON (builtins.readFile "${quotaAxiSource}/package.json")).version;

  src = quotaAxiSource;

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = "sha256-l3bTF7qXLSfS7JNbJfM8RiaYy7vkzrkJoIDRYdiG9R8=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs
    pnpm_11
    pnpmConfigHook
  ];

  buildPhase = ''
    runHook preBuild
    pnpm build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    pnpm install --offline --prod --frozen-lockfile --ignore-scripts

    mkdir -p "$out/lib/quota-axi"
    cp -R dist node_modules package.json "$out/lib/quota-axi/"

    makeWrapper ${lib.getExe nodejs} "$out/bin/quota-axi" \
      --add-flags "$out/lib/quota-axi/dist/bin/quota-axi.js"

    install -Dm444 skills/quota-axi/SKILL.md \
      "$out/share/agent-skills/quota-axi/SKILL.md"
    substituteInPlace "$out/share/agent-skills/quota-axi/SKILL.md" \
      --replace-fail \
        'You do not need quota-axi installed globally - invoke it with `npx -y quota-axi`.' \
        'Invoke the declaratively packaged CLI with `quota-axi`.' \
      --replace-fail 'npx -y quota-axi' 'quota-axi'

    runHook postInstall
  '';

  strictDeps = true;

  meta = {
    description = "Report local agent-provider quota windows";
    homepage = "https://github.com/kunchenguid/quota-axi";
    license = lib.licenses.mit;
    mainProgram = "quota-axi";
    platforms = lib.platforms.unix;
  };
})
