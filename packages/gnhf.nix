{ lib, nodejs, stdenvNoCC }:

let
  gnhfVersion = "0.1.41";
  codexScript = lib.concatStringsSep "\n" [
    "#!/usr/bin/env bash"
    "set -euo pipefail"
    "if [ \"$#\" -eq 0 ]; then"
    "  echo \"gnhf: expected a single prompt argument\" >&2"
    "  exit 2"
    "fi"
    "exec ${nodejs}/bin/npx -y gnhf@${gnhfVersion} --agent codex \"$*\""
  ];
  opencodeScript = lib.concatStringsSep "\n" [
    "#!/usr/bin/env bash"
    "set -euo pipefail"
    "if [ \"$#\" -eq 0 ]; then"
    "  echo \"gnhf-opencode: expected a single prompt argument\" >&2"
    "  exit 2"
    "fi"
    "exec ${nodejs}/bin/npx -y gnhf@${gnhfVersion} --agent opencode \"$*\""
  ];
  codexNonoWrapperScript = lib.concatStringsSep "\n" [
    "#!/usr/bin/env bash"
    "set -euo pipefail"
    ""
    "wrapper_dir=\"$(mktemp -d)\""
    "trap 'rm -rf -- \"$wrapper_dir\"' EXIT"
    ""
    "cat > \"$wrapper_dir/codex\" <<'SH'"
    "#!/usr/bin/env bash"
    "exec codex-nono \"$@\""
    "SH"
    "chmod +x \"$wrapper_dir/codex\""
    ""
    "PATH=\"$wrapper_dir:$PATH\""
    "${nodejs}/bin/npx -y gnhf@${gnhfVersion} --agent codex \"$*\""
  ];
  opencodeNonoWrapperScript = lib.concatStringsSep "\n" [
    "#!/usr/bin/env bash"
    "set -euo pipefail"
    ""
    "wrapper_dir=\"$(mktemp -d)\""
    "trap 'rm -rf -- \"$wrapper_dir\"' EXIT"
    ""
    "cat > \"$wrapper_dir/opencode\" <<'SH'"
    "#!/usr/bin/env bash"
    "exec opencode-nono \"$@\""
    "SH"
    "chmod +x \"$wrapper_dir/opencode\""
    ""
    "PATH=\"$wrapper_dir:$PATH\""
    "${nodejs}/bin/npx -y gnhf@${gnhfVersion} --agent opencode \"$*\""
  ];
  gnhfDefaultScript = lib.concatStringsSep "\n" [
    "#!/usr/bin/env bash"
    "set -euo pipefail"
    "if [ \"$#\" -eq 0 ]; then"
    "  echo \"gnhf: expected a single prompt argument\" >&2"
    "  exit 2"
    "fi"
    "exec \"${nodejs}/bin/npx\" -y gnhf@${gnhfVersion} --agent codex \"$*\""
  ];
in
stdenvNoCC.mkDerivation {
  pname = "gnhf-wrapper";
  version = "0.1.0";

  dontBuild = true;
  dontUnpack = true;

  installPhase = lib.concatStringsSep "\n" [
    "runHook preInstall"
    ""
    "mkdir -p \"$out/bin\""
    ""
    "cat > \"$out/bin/gnhf-codex\" <<'EOF'"
    codexScript
    "EOF"
    "cat > \"$out/bin/gnhf-codex-nono\" <<'EOF'"
    codexNonoWrapperScript
    "EOF"
    "cat > \"$out/bin/gnhf-opencode\" <<'EOF'"
    opencodeScript
    "EOF"
    "cat > \"$out/bin/gnhf-opencode-nono\" <<'EOF'"
    opencodeNonoWrapperScript
    "EOF"
    "cat > \"$out/bin/gnhf\" <<'EOF'"
    gnhfDefaultScript
    "EOF"
    ""
    "chmod +x \\"
    "  \"$out/bin/gnhf\" \\"
    "  \"$out/bin/gnhf-codex\" \\"
    "  \"$out/bin/gnhf-codex-nono\" \\"
    "  \"$out/bin/gnhf-opencode\" \\"
    "  \"$out/bin/gnhf-opencode-nono\""
    ""
    "runHook postInstall"
  ];

  meta = {
    description = "Agent helper scripts for running gnhf with codex/opencode and sandbox variants";
    homepage = "https://github.com/kunchenguid/gnhf";
    license = lib.licenses.mit;
    mainProgram = "gnhf";
    platforms = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
  };
}
