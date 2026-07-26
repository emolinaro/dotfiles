{ lib, nodejs, stdenvNoCC }:

let
  version = "0.1.41";
  packageSpecifier = "gnhf@${version}";
in
stdenvNoCC.mkDerivation {
  pname = "gnhf";
  inherit version;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    cat > "$out/bin/gnhf" <<'EOF'
#!/usr/bin/env sh
set -eu
has_agent=0
for arg in "$@"; do
  case "$arg" in
    --agent|--agent=*) has_agent=1 ;;
  esac
done

if [ "$has_agent" -eq 0 ]; then
  set -- --agent codex "$@"
fi

exec ${nodejs}/bin/npx --yes "${packageSpecifier}" "$@"
EOF
    chmod +x "$out/bin/gnhf"
    runHook postInstall
  '';

  meta = {
    description = "Multi-agent CLI gateway for Codex/OpenCode frontends";
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
}
