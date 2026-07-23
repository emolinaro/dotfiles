{
  nonoPackage,
  pkgs,
  profiles,
}:

pkgs.runCommand "nono-profiles-test"
  {
    nativeBuildInputs = [
      nonoPackage
      pkgs.jq
    ];
  }
  ''
    set -euo pipefail

    export HOME="$TMPDIR/home"
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
      and (.filesystem.unix_socket // []) == []
      and .workdir.access == "none"
      and (.filesystem.allow | index("@git:common-dir") == null)
      and (.filesystem.allow | index("$HOME/.gstack") != null)
      and (.filesystem.read | index("$HOME/.local/share/gstack/repos/gstack") != null)
      and (.filesystem.read | index("$HOME/.gstack/repos/gstack") == null)
      and (.filesystem.deny | contains([
        "/tmp",
        "/private/tmp",
        "/private/var/folders",
        "/var/folders",
        "$SSH_AUTH_SOCK"
      ]))
      and (.environment.allow_vars | contains([
        "HOME",
        "PATH",
        "TERM"
      ]))
      and (.environment.allow_vars | index("*") == null)
      and .environment.set_vars.XDG_CONFIG_HOME == "$HOME/.config"
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

    for agent in claude codex opencode pi; do
      resolved="$TMPDIR/dotfiles-$agent.resolved.json"
      nono profile show --raw --json "dotfiles-$agent" > "$resolved"
      jq --exit-status --arg agent "$agent" '
        def filesystem_grants: [
          .filesystem.allow[],
          .filesystem.read[],
          .filesystem.write[],
          .filesystem.allow_file[],
          .filesystem.read_file[],
          .filesystem.write_file[]
        ];
        def forbidden_path:
          test(
            "Library/Keychains|(^|/)\\.ssh($|/)|(^|/)\\.aws($|/)|(^|/)\\.kube($|/)|(^|/)\\.docker($|/)|Documents/GITHUB|Application Support/(Google/Chrome|Chromium|Firefox|Microsoft Edge|Arc|BraveSoftware|Vivaldi)|Library/Safari";
            "i"
          );
        def forbidden_group:
          (. == "claude_code_macos" and $agent != "claude")
          or (. == "codex_macos" and $agent != "codex")
          or . == "user_caches_macos"
          or . == "user_caches_linux"
          or . == "vscode_macos"
          or . == "vscode_linux";

        .workdir.access == "none"
        and .security.capability_elevation == false
        and .network.block == false
        and (filesystem_grants | map(forbidden_path | not) | all)
        and ([.groups.include[]?] | map(forbidden_group | not) | all)
      ' "$resolved" >/dev/null
    done

    jq --exit-status '
      ([(.groups.include // [])[] | if type == "object" then .name else . end]
        | index("claude_code_macos") == null)
      and (.filesystem.deny | contains([
        "$HOME/.claude/hooks",
        "$HOME/.claude/plugins",
        "$HOME/.claude/settings.json"
      ]))
    ' "$profile_dir/dotfiles-claude.json" >/dev/null

    jq --exit-status '
      ([(.groups.include // [])[] | if type == "object" then .name else . end]
        | index("codex_macos") == null)
      and (.filesystem.deny | contains([
        "$HOME/.codex/AGENTS.md",
        "$HOME/.codex/config.toml",
        "$HOME/.codex/skills"
      ]))
    ' "$profile_dir/dotfiles-codex.json" >/dev/null

    jq --exit-status '
      .filesystem.deny | contains([
        "$HOME/.config/opencode/AGENTS.md",
        "$HOME/.config/opencode/opencode.json",
        "$HOME/.config/opencode/plugins",
        "$HOME/.config/opencode/skills"
      ])
    ' "$profile_dir/dotfiles-opencode.json" >/dev/null

    jq --exit-status '
      .filesystem.deny | contains([
        "$HOME/.pi/agent/AGENTS.md",
        "$HOME/.pi/agent/extensions"
      ])
    ' "$profile_dir/dotfiles-pi.json" >/dev/null

    touch "$out"
  ''
