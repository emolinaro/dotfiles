{
  lib,
  nodejs,
  stdenvNoCC,
}:

let
  gnhfVersion = "0.1.42";
in
stdenvNoCC.mkDerivation {
  inherit gnhfVersion;
  pname = "gnhf-wrapper";
  version = gnhfVersion;

  dontBuild = true;
  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"

    cat > "$out/bin/gnhf-codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec ${nodejs}/bin/npx -y gnhf@${toString gnhfVersion} --agent codex "$@"
EOF

    cat > "$out/bin/gnhf-codex-nono" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

wrapper_dir="$(mktemp -d)"
trap 'rm -rf -- "$wrapper_dir"' EXIT

cat > "$wrapper_dir/codex" <<'SH'
#!/usr/bin/env bash
exec codex-nono "$@"
SH
chmod +x "$wrapper_dir/codex"

PATH="$wrapper_dir:$PATH" exec ${nodejs}/bin/npx -y gnhf@${toString gnhfVersion} --agent codex "$@"
EOF

    cat > "$out/bin/gnhf-opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec ${nodejs}/bin/npx -y gnhf@${toString gnhfVersion} --agent opencode "$@"
EOF

    cat > "$out/bin/gnhf-opencode-nono" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

wrapper_dir="$(mktemp -d)"
trap 'rm -rf -- "$wrapper_dir"' EXIT

cat > "$wrapper_dir/opencode" <<'SH'
#!/usr/bin/env bash
exec opencode-nono "$@"
SH
chmod +x "$wrapper_dir/opencode"

PATH="$wrapper_dir:$PATH" exec ${nodejs}/bin/npx -y gnhf@${toString gnhfVersion} --agent opencode "$@"
EOF

    cat > "$out/bin/gnhf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec "${nodejs}/bin/npx" -y gnhf@${toString gnhfVersion} --agent codex "$@"
EOF

    chmod +x \
      "$out/bin/gnhf" \
      "$out/bin/gnhf-codex" \
      "$out/bin/gnhf-codex-nono" \
      "$out/bin/gnhf-opencode" \
      "$out/bin/gnhf-opencode-nono"

    runHook postInstall
  '';

  meta = {
    description = "Agent helper scripts for running gnhf with codex/opencode and sandbox variants";
    homepage = "https://github.com/kunchenguid/gnhf";
    license = lib.licenses.mit;
    mainProgram = "gnhf";
    platforms = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
  };
}
