{
  agentRegistry,
  nonoPackage,
  pkgs,
  profiles,
}:

let
  agentNames = builtins.attrNames agentRegistry;
in
pkgs.runCommand "nono-profiles-test"
  {
    nativeBuildInputs = [
      nonoPackage
      pkgs.jq
    ];
  }
  ''
    set -euo pipefail

    export HOME="$TMPDIR/host-home"
    export DOTFILES_AGENT_HOME="$TMPDIR/agent-home"
    export DOTFILES_HOST_HOME="$HOME"
    export SSH_AUTH_SOCK="$TMPDIR/ssh-agent.sock"
    export XDG_CONFIG_HOME="$HOME/.config"
    profile_dir="$XDG_CONFIG_HOME/nono/profiles"
    mkdir -p "$profile_dir"
    cp -R ${profiles}/. "$profile_dir/"
    chmod -R u+w "$HOME"

    for profile_file in "$profile_dir"/*.json; do
      jq --exit-status . "$profile_file" >/dev/null
      nono profile validate --strict --json "$profile_file" >/dev/null
    done

    jq --exit-status '
      .linux.af_unix_mediation == "pathname"
      and .allow_launch_services != true
      and .allow_parent_of_protected == true
      and (.filesystem.unix_socket // [] | contains([
        "$DOTFILES_JOB_CONTROL_SOCKET",
        "/nix/var/nix/daemon-socket/socket"
      ]))
      and .workdir.access == "none"
      and (.groups.exclude | contains([
        "homebrew_linux",
        "homebrew_macos",
        "system_read_linux_core",
        "system_read_macos",
        "system_write_linux",
        "system_write_macos"
      ]))
      and (.filesystem.allow | contains([
        "$DOTFILES_AGENT_HOME/.gstack",
        "$TMPDIR"
      ]))
      and (.filesystem.allow | index("$HOME/.gstack") == null)
      and (.filesystem.read | contains([
        "$DOTFILES_HOST_HOME/.agents",
        "$DOTFILES_HOST_HOME/.local/share/gstack/repos/gstack"
      ]))
      and (.filesystem.read | index("$DOTFILES_HOST_HOME/.gstack") == null)
      and (.filesystem.read_file | contains([
        "$DOTFILES_AGENT_HOME/.config/git/config"
      ]))
      and (.filesystem.deny | map(if type == "object" then .path else . end) | contains([
        "$DOTFILES_HOST_HOME/.cache/herdr/herdr.sock",
        "$DOTFILES_HOST_HOME/.config/herdr/herdr.sock",
        "$SSH_AUTH_SOCK"
      ]))
      and (.filesystem.write | map(if type == "object" then .path else . end) | contains([
        "/dev/fd"
      ]))
      and (.filesystem.write | map(if type == "object" then .path else . end) | index("/dev/pts") == null)
      and (.filesystem.read | map(if type == "object" then .path else . end) | index("/dev/pts") == null)
      and (.filesystem.allow_file | map(if type == "object" then .path else . end) | contains([
        "/dev/null",
        "/dev/dtracehelper",
        "/dev/random",
        "/dev/tty",
        "/dev/urandom",
        "/dev/stdout",
        "/dev/stderr"
      ]))
      and (.filesystem.read | map(if type == "object" then .path else . end) | contains([
        "/dev/fd",
        "/System/Library",
        "/System/Cryptexes",
        "/System/Volumes/Preboot/Cryptexes/OS",
        "/System/Volumes/Preboot/Cryptexes/OS/System/Library",
        "/System/Volumes/Preboot/Cryptexes/OS/usr/lib",
        "/home/linuxbrew/.linuxbrew/Cellar",
        "/home/linuxbrew/.linuxbrew/opt",
        "/opt/homebrew/Cellar",
        "/opt/homebrew/etc",
        "/opt/homebrew/opt",
        "/nix"
      ]))
      and (.filesystem.read | map(if type == "object" then .path else . end) | all(
        . != "/private"
        and . != "/private/var"
        and . != "/var"
        and . != "/tmp"
        and . != "/Volumes"
        and . != "/System/Volumes"
        and . != "/Applications"
        and . != "/home/linuxbrew/.linuxbrew"
        and . != "/opt"
        and . != "/opt/homebrew"
      ))
      and (.filesystem.read_file | map(if type == "object" then .path else . end) | contains([
        "/Library/Preferences/Logging/com.apple.diagnosticd.filter.plist"
      ]))
      and (.environment.allow_vars | contains([
        "DOTFILES_JOB_CONTROL_SOCKET",
        "DOTFILES_JOB_CONTROL_TOKEN",
        "GIT_DIR",
        "GIT_WORK_TREE",
        "HOME",
        "PATH",
        "TERM"
      ]))
      and (.environment.allow_vars | index("*") == null)
      and .environment.set_vars.HOME == "$HOME"
      and .environment.set_vars.CFFIXED_USER_HOME == "$HOME"
      and .environment.set_vars.XDG_CACHE_HOME == "$HOME/.cache"
      and .environment.set_vars.XDG_CONFIG_HOME == "$HOME/.config"
      and .environment.set_vars.XDG_DATA_HOME == "$HOME/.local/share"
      and (.platform_overrides.macos.filesystem.deny | contains([
        "$DOTFILES_WORKTREE_ROOT/.git"
      ]))
      and .environment.set_vars.XDG_RUNTIME_DIR == "$HOME/.run"
      and .environment.set_vars.XDG_STATE_HOME == "$HOME/.local/state"
      and .environment.set_vars.HERDR_SOCKET_PATH == null
      and ([.groups.include[] | if type == "object" then .name else . end]
        | index("user_caches_macos") == null
        and index("user_caches_linux") == null)
      and (.environment.deny_vars | contains([
        "ANTHROPIC_*",
        "OPENAI_*",
        "GEMINI_*",
        "AWS_*",
        "AZURE_*",
        "GOOGLE_*",
        "KUBECONFIG",
        "DOCKER_*",
        "SSH_*"
      ]))
    ' "$profile_dir/dotfiles-agent-base.json" >/dev/null

    for agent in ${pkgs.lib.escapeShellArgs agentNames}; do
      resolved="$TMPDIR/dotfiles-$agent.resolved.json"
      nono profile show --raw --json "dotfiles-$agent" > "$resolved"
      jq --exit-status --arg agent "$agent" '
        def writable_grants: [
          .filesystem.allow[],
          .filesystem.write[],
          .filesystem.allow_file[],
          .filesystem.write_file[]
        ];
        def allowlisted_host_writable:
          . == "$DOTFILES_HOST_HOME/.codex"
          or . == "$DOTFILES_HOST_HOME/.codex/config.toml"
          or . == "$DOTFILES_HOST_HOME/.codex/hooks.json"
          or . == "$DOTFILES_HOST_HOME/.claude.json"
          or . == "$DOTFILES_HOST_HOME/.pi/agent"
          or . == "$DOTFILES_HOST_HOME/.pi/agent/trust.json";
        def forbidden_path:
          if type == "string" then
            test(
              "\\$DOTFILES_HOST_HOME/(\\.claude($|/)|\\.codex($|/)|\\.config/opencode($|/)|\\.local/share/opencode($|/)|\\.pi($|/)|\\.gstack($|/)|Library/Keychains)|(^|/)\\.ssh($|/)|(^|/)\\.aws($|/)|(^|/)\\.kube($|/)|(^|/)\\.docker($|/)|Documents/GITHUB|Application Support/(Google/Chrome|Chromium|Firefox|Microsoft Edge|Arc|BraveSoftware|Vivaldi)|Library/Safari";
              "i"
            )
            and (allowlisted_host_writable | not)
          else
            false
          end;
        def forbidden_group:
          . == "claude_code_macos"
          or . == "codex_macos"
          or . == "user_caches_macos"
          or . == "user_caches_linux"
          or . == "vscode_macos"
          or . == "vscode_linux";

        .workdir.access == "none"
        and .security.capability_elevation == false
        and .network.block == false
        and .network.network_profile == "developer"
        and (writable_grants | map(forbidden_path | not) | all)
        and ([.groups.include[]?] | map(forbidden_group | not) | all)
      ' "$resolved" >/dev/null
    done

    jq --exit-status '
      (.filesystem.allow | contains([
        "$DOTFILES_AGENT_HOME/.claude",
        "$DOTFILES_AGENT_HOME/.cache/claude",
        "$DOTFILES_AGENT_HOME/.cache/claude-cli-nodejs",
        "$DOTFILES_AGENT_HOME/.cache/axi-tools",
        "$DOTFILES_AGENT_HOME/.local/state/claude/locks"
      ]))
      and (.filesystem.allow_file | contains([
        "$DOTFILES_AGENT_HOME/.claude.json",
        "$DOTFILES_AGENT_HOME/.claude.json.lock",
        "$DOTFILES_AGENT_HOME/.claude.lock",
        "$DOTFILES_HOST_HOME/.claude.json"
      ]))
      and (.filesystem.read | contains([
        "$DOTFILES_HOST_HOME/.cache/axi-tools",
        "$DOTFILES_HOST_HOME/.claude/CLAUDE.md",
        "$DOTFILES_HOST_HOME/.claude/settings.json",
        "$DOTFILES_HOST_HOME/.claude/skills"
      ]))
      and ((.filesystem.deny // []) | length == 0)
    ' "$profile_dir/dotfiles-claude.json" >/dev/null

    jq --exit-status '
      (.filesystem.allow | contains([
        "$DOTFILES_AGENT_HOME/.codex",
        "$DOTFILES_AGENT_HOME/.cache/axi-tools",
        "$DOTFILES_AGENT_HOME/.lavish-axi",
        "$DOTFILES_HOST_HOME/.codex"
      ]))
      and (.filesystem.allow_file | contains([
        "$DOTFILES_HOST_HOME/.codex/config.toml",
        "$DOTFILES_HOST_HOME/.codex/hooks.json"
      ]))
      and (.filesystem.read | contains([
        "$DOTFILES_HOST_HOME/.cache/axi-tools",
        "$DOTFILES_HOST_HOME/.codex/AGENTS.md",
        "$DOTFILES_HOST_HOME/.codex/config.toml",
        "$DOTFILES_HOST_HOME/.codex/herdr-agent-state.sh",
        "$DOTFILES_HOST_HOME/.codex/hooks.json",
        "$DOTFILES_HOST_HOME/.codex/plugins",
        "$DOTFILES_HOST_HOME/.codex/rules",
        "$DOTFILES_HOST_HOME/.codex/skills"
      ]))
      and .platform_overrides.macos.environment.set_vars.SSL_CERT_FILE == "/private/etc/ssl/cert.pem"
      and .platform_overrides.macos.environment.set_vars.CODEX_CA_CERTIFICATE == "/private/etc/ssl/cert.pem"
      and ((.filesystem.deny // []) | length == 0)
    ' "$profile_dir/dotfiles-codex.json" >/dev/null

    jq --exit-status '
      (.filesystem.allow | contains([
        "$DOTFILES_AGENT_HOME/.opencode",
        "$DOTFILES_AGENT_HOME/.config/opencode",
        "$DOTFILES_AGENT_HOME/.cache/opencode",
        "$DOTFILES_AGENT_HOME/.cache/axi-tools",
        "$DOTFILES_AGENT_HOME/.local/share/opencode",
        "$DOTFILES_AGENT_HOME/.local/share/opentui",
        "$DOTFILES_AGENT_HOME/.npm",
        "$DOTFILES_AGENT_HOME/.local/state/opencode"
      ]))
      and (.filesystem.read | contains([
        "$DOTFILES_HOST_HOME/.cache/axi-tools",
        "$DOTFILES_HOST_HOME/.config/opencode/AGENTS.md",
        "$DOTFILES_HOST_HOME/.config/opencode/opencode.json",
        "$DOTFILES_HOST_HOME/.config/opencode/plugins",
        "$DOTFILES_HOST_HOME/.config/opencode/skills"
      ]))
      and ((.filesystem.deny // []) | length == 0)
    ' "$profile_dir/dotfiles-opencode.json" >/dev/null

    jq --exit-status '
      (.filesystem.allow | contains([
        "$DOTFILES_AGENT_HOME/.pi",
        "$DOTFILES_AGENT_HOME/.cache/axi-tools"
      ]))
      and (.filesystem.write | contains(["$DOTFILES_HOST_HOME/.pi/agent"]))
      and (.filesystem.allow_file | contains(["$DOTFILES_HOST_HOME/.pi/agent/trust.json"]))
      and (.filesystem.read | contains([
        "$DOTFILES_HOST_HOME/.cache/axi-tools",
        "$DOTFILES_HOST_HOME/.pi/agent/AGENTS.md",
        "$DOTFILES_HOST_HOME/.pi/agent/settings.json"
      ]))
      and .platform_overrides.macos.environment.set_vars.OPENSSL_CONF == "/private/etc/ssl/openssl.cnf"
      and ((.filesystem.deny // []) | length == 0)
    ' "$profile_dir/dotfiles-pi.json" >/dev/null

    jq --exit-status '
      (.filesystem.allow | contains([
        "$DOTFILES_AGENT_HOME/.dsh",
        "$DOTFILES_AGENT_HOME/.dsh-tui",
        "$DOTFILES_AGENT_HOME/.cache/axi-tools",
        "$DOTFILES_AGENT_HOME/.cache/dsh-tui-standalone",
        "$DOTFILES_AGENT_HOME/.cache/pnpm",
        "$DOTFILES_AGENT_HOME/.local/share/pnpm"
      ]))
      and ((.filesystem.deny // []) | length == 0)
    ' "$profile_dir/dotfiles-dsh.json" >/dev/null

    touch "$out"
  ''
