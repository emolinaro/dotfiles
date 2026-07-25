{ fetchFromGitHub
, fetchPnpmDeps
, git
, lib
, makeWrapper
, nodejs
, pnpm_11
, pnpmConfigHook
, stdenv
,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "gnhf";
  version = "0.1.42";

  src = fetchFromGitHub {
    owner = "kunchenguid";
    repo = "gnhf";
    rev = "bcafaa3e3c23ad2f6d934dca43cc805f502b777d";
    hash = "sha256-8dTfXCULAoXMJwb38bEMCazT7jzT130rzpLivVkx3Wc=";
  };

  patches = [ ../patches/gnhf-agent-path.patch ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_11;
    fetcherVersion = 4;
    hash = "sha256-kQHYvZ8LNHGw1pPuTnOTUn26yUY8TmgA0+BO2+cSvLY=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs
    pnpm_11
    pnpmConfigHook
  ];

  buildPhase = ''
    runHook preBuild
    pnpm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    pnpm prune --prod --ignore-scripts
    rm -r node_modules/.bin
    rm node_modules/.modules.yaml node_modules/.pnpm-workspace-state-v1.json

    mkdir -p "$out/bin" "$out/lib/gnhf" "$out/share/gnhf/skills"
    cp -R dist node_modules package.json "$out/lib/gnhf/"
    cp -R skills/gnhf "$out/share/gnhf/skills/gnhf"

    makeWrapper ${lib.getExe nodejs} "$out/bin/gnhf" \
      --add-flags "$out/lib/gnhf/dist/cli.mjs" \
      --prefix PATH : ${lib.makeBinPath [ git ]}

    runHook postInstall
  '';

  passthru.skillPath = "${finalAttrs.finalPackage}/share/gnhf/skills/gnhf";

  meta = {
    description = "Long-running orchestrator for iterative coding agents";
    homepage = "https://github.com/kunchenguid/gnhf";
    license = lib.licenses.mit;
    mainProgram = "gnhf";
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
})
