{ gnhfPackage
, homeConfig
, pkgs
,
}:

let
  gnhfSkill = homeConfig.home.file.".agents/skills/gnhf" or null;
  launcherPackages = builtins.filter
    (
      package: pkgs.lib.getName package == "gnhf-agent-launchers"
    )
    homeConfig.home.packages;
  launchers = if builtins.length launcherPackages == 1 then builtins.head launcherPackages else null;
  packageIsManaged = builtins.elem gnhfPackage homeConfig.home.packages;
  configIsUnmanaged = !(builtins.hasAttr ".gnhf/config.yml" homeConfig.home.file);
  telemetryIsDisabled = homeConfig.home.sessionVariables.GNHF_TELEMETRY or null == "0";
in
assert pkgs.lib.assertMsg packageIsManaged "Home Manager must install the GNHF package";
assert pkgs.lib.assertMsg
  (
    launchers != null
  ) "Home Manager must install exactly one GNHF agent launcher package";
assert pkgs.lib.assertMsg (gnhfSkill != null) "Home Manager must expose the GNHF agent skill";
assert pkgs.lib.assertMsg configIsUnmanaged
  "Home Manager must leave the mutable GNHF agent choice unmanaged";
assert pkgs.lib.assertMsg telemetryIsDisabled "Home Manager must disable GNHF telemetry";
pkgs.runCommand "gnhf-home-test" { } ''
  set -euo pipefail

  test -x "${gnhfPackage}/bin/gnhf"
  test -x "${launchers}/bin/gnhf-codex"
  test -x "${launchers}/bin/gnhf-codex-nono"
  test -x "${launchers}/bin/gnhf-opencode"
  test -x "${launchers}/bin/gnhf-opencode-nono"
  test -s "${gnhfSkill.source}/SKILL.md"
  mkdir "$out"
''
