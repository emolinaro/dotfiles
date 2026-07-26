{ pkgs
, quotaAxiPackage
,
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
    quota-axi --help | grep -F 'usage: quota-axi [auth|update] [flags]'
    quota-axi --help | grep -F '(none)=quota, auth, update'

    managed_update='quota-axi is managed by Nix. Run `nix flake update quotaAxi` from the dotfiles checkout, refresh the pinned dependency hash, and rebuild.'
    test "$(quota-axi update)" = "$managed_update"
    test "$(quota-axi update --check)" = "$managed_update"

    runtime_node_modules="${quotaAxiPackage}/lib/quota-axi/node_modules"
    for metadata in .modules.yaml .package-map.json .pnpm-workspace-state-v1.json; do
      test ! -e "$runtime_node_modules/$metadata"
    done
    test ! -e "$runtime_node_modules/.pnpm/lock.yaml"

    package_size_kib="$(du -sk "${quotaAxiPackage}/lib/quota-axi" | cut -f1)"
    test "$package_size_kib" -lt 10240

    skill="${quotaAxiPackage}/share/agent-skills/quota-axi/SKILL.md"
    grep -F 'Invoke the declaratively packaged CLI with `quota-axi`.' "$skill"
    if grep -F 'npx -y quota-axi' "$skill"; then
      exit 1
    fi

    touch "$out"
  ''
