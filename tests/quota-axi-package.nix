{
  pkgs,
  quotaAxiPackage,
}:

pkgs.runCommand "quota-axi-package-test"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      quotaAxiPackage
    ];
  }
  ''
    set -euo pipefail

    test "$(quota-axi --version)" = "${quotaAxiPackage.version}"
    quota-axi --help | grep -F 'usage: quota-axi [auth] [flags]'

    skill="${quotaAxiPackage}/share/agent-skills/quota-axi/SKILL.md"
    grep -F 'Invoke the declaratively packaged CLI with `quota-axi`.' "$skill"
    if grep -F 'npx -y quota-axi' "$skill"; then
      exit 1
    fi

    touch "$out"
  ''
