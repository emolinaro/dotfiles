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
      and (.filesystem.unix_socket | sort) == ([
        "$HOME/.cache/herdr/herdr.sock",
        "$HOME/.config/herdr/herdr.sock"
      ] | sort)
      and .environment.set_vars.HERDR_SOCKET_PATH == null
      and ([.groups.include[] | if type == "object" then .name else . end]
        | index("user_caches_macos") == null
        and index("user_caches_linux") == null)
      and (.environment.deny_vars | contains([
        "AWS_*",
        "AZURE_*",
        "GOOGLE_*",
        "KUBECONFIG",
        "DOCKER_HOST",
        "SSH_AUTH_SOCK"
      ]))
    ' "$profile_dir/dotfiles-agent-base.json" >/dev/null

    for agent in claude codex opencode pi; do
      resolved="$TMPDIR/dotfiles-$agent.resolved.json"
      nono profile show --raw --json "dotfiles-$agent" > "$resolved"
      jq --exit-status '
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
          . == "claude_code_macos"
          or . == "codex_macos"
          or . == "user_caches_macos"
          or . == "user_caches_linux"
          or . == "vscode_macos"
          or . == "vscode_linux";

        .workdir.access == "readwrite"
        and .security.capability_elevation == false
        and .network.block == false
        and (filesystem_grants | map(forbidden_path | not) | all)
        and ([.groups.include[]?] | map(forbidden_group | not) | all)
      ' "$resolved" >/dev/null
    done

    touch "$out"
  ''
