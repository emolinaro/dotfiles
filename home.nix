{
  axiToolsPackage,
  chromeDevtoolsAxiSkill,
  config,
  gnhfPackage,
  ghAxiSkill,
  gstackRev,
  herdrPackage,
  homeDirectory,
  lavishSkill,
  lib,
  nonoPackage,
  pkgs,
  quotaAxiSkill,
  superpowersRev,
  superpowersSkill,
  tasksAxiSkill,
  username,
  ...
}:

let
  agentRegistry = import ./runtime/nono-agents.nix;
  agentNames = builtins.attrNames agentRegistry;
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  gstackCheckout = "${config.home.homeDirectory}/.local/share/gstack/repos/gstack";
  gstackCheckoutMigration = pkgs.callPackage ./runtime/gstack-checkout-migration.nix { };
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  nonoProfiles = ./home/.config/nono/profiles;
  aicPackage = pkgs.callPackage ./packages/aic.nix { };
  noMistakesPackage = pkgs.callPackage ./packages/no-mistakes.nix { };
  treehousePackage = pkgs.callPackage ./packages/treehouse.nix { };
  ezaIcons = if isLinux then "never" else "always";
  homebrewPrefix = if pkgs.stdenv.hostPlatform.isAarch64 then "/opt/homebrew" else "/usr/local";
  platformPath = if isLinux then "/usr/local/bin" else "${homebrewPrefix}/bin:/usr/local/bin";
  herdrCommand = if isLinux then lib.getExe herdrPackage else "${homebrewPrefix}/bin/herdr";
  # macOS GUI apps discover fonts through CoreText, not the Nix profile path.
  # Keep the Hack Nerd Font family linked into ~/Library/Fonts so WezTerm sees it after reboot.
  hackFontEntry =
    variant:
    lib.mkIf (!isLinux) {
      force = true;
      source = "${pkgs.nerd-fonts.hack}/share/fonts/truetype/NerdFonts/Hack/HackNerdFont-${variant}.ttf";
    };
  linuxAgentPackages = {
    claude = pkgs.claude-code;
    codex = pkgs.codex;
    opencode = pkgs.opencode;
    pi = pkgs.pi-coding-agent;
  };
  agentExecutables = lib.genAttrs agentNames (
    name: if isLinux then lib.getExe linuxAgentPackages.${name} else "${homebrewPrefix}/bin/${name}"
  );
  agentWrappers = pkgs.callPackage ./runtime/nono-agent-wrappers.nix {
    inherit
      agentExecutables
      agentRegistry
      homeDirectory
      nonoPackage
      ;
    profiles = nonoProfiles;
  };
  nonoProfileNames = map (name: agentRegistry.${name}.profile) agentNames;
in

{
  home.username = username;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "24.11";

  # Avoid re-evaluating every Home Manager option to generate options.json.
  manual.manpages.enable = false;

  home.packages =
    with pkgs;
    [
      # cli i use constantly
      basedpyright
      bash-language-server
      btop
      bun
      aicPackage
      axiToolsPackage
      coreutils # gstack uses gtimeout to bound nested Codex calls
      delta
      delve
      dive
      dust # fast du for ./disk-usage.sh
      eza
      fd # fast find
      fzf # fuzzy finder
      gh
      git
      gnumake
      go
      golangci-lint
      gopls
      gotools
      grpcurl
      hadolint
      highlight
      htop
      httpie
      jq # json on the command line
      just
      kitty.kitten # kitten CLI only, no kitty terminal
      k9s
      kubectl
      kubelogin-oidc
      kubectx
      kubernetes-helm
      lazygit
      neovim
      nodejs
      nonoPackage
      noMistakesPackage
      gnhfPackage
      pre-commit
      python3
      ripgrep # fast search
      ruff
      shellcheck
      shfmt
      stern
      tmux
      tree
      treehousePackage
      tree-sitter
      uv
      watchexec
      yq-go
      agentWrappers
    ]
    ++ lib.optionals isLinux (
      builtins.attrValues linuxAgentPackages
      ++ [
        pkgs.docker-client
        pkgs.docker-compose
        pkgs.gcc # nvim-treesitter compiles parsers with cc
        herdrPackage
        pkgs.lazydocker # OrbStack provides the equivalent UI on macOS
        pkgs.procps
      ]
    )
    ++ [
      # the font everything renders in
      nerd-fonts.hack
    ];
  fonts.fontconfig.enable = true;
  home.sessionVariables = {
    EDITOR = "nvim";
    DOTFILES = "${config.home.homeDirectory}/.dotfiles";
    CDPATH = "${config.home.homeDirectory}/Documents/GITHUB";
    # GNU ls colors: directories blue, symlinks cyan, executables green.
    LS_COLORS = "di=1;34:ln=1;36:ex=1;32:fi=0";
    NO_MISTAKES_NO_UPDATE_CHECK = "1";
    NONO_NO_PACK_UPDATE_HINTS = "1";
    NONO_NO_UPDATE_CHECK = "1";
  }
  // lib.optionalAttrs isLinux {
    # Keep the portable Herdr config symlinked, but put runtime sockets on a local filesystem.
    HERDR_SOCKET_PATH = "${config.home.homeDirectory}/.cache/herdr/herdr.sock";
  };
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true; # ghost text from history
    syntaxHighlighting.enable = true; # commands turn green when valid
    initContent = ''
      ${lib.optionalString isLinux ''
        # Set a consistent theme in xterm-compatible remote terminals.
        printf '\033]11;#000000\007\033]10;#f5f5f5\007'
      ''}

      # Make Starship right prompt align cleanly in Zsh
      ZLE_RPROMPT_INDENT=0

      bindkey '^f' autosuggest-accept

      # Home / End keys
      bindkey '\e[H'  beginning-of-line
      bindkey '\e[F'  end-of-line
      bindkey '\eOH'  beginning-of-line
      bindkey '\eOF'  end-of-line
      bindkey '\e[1~' beginning-of-line
      bindkey '\e[4~' end-of-line
      bindkey '\e[7~' beginning-of-line
      bindkey '\e[8~' end-of-line

      # Delete key
      bindkey '\e[3~' delete-char

      # PageUp / PageDown
      # Useful behavior: search history using the current command prefix
      bindkey '\e[5~' history-beginning-search-backward
      bindkey '\e[6~' history-beginning-search-forward

      # Terminal-info based fallback
      [[ -n "$terminfo[khome]"  ]] && bindkey "$terminfo[khome]"  beginning-of-line
      [[ -n "$terminfo[kend]"   ]] && bindkey "$terminfo[kend]"   end-of-line
      [[ -n "$terminfo[kdch1]"  ]] && bindkey "$terminfo[kdch1]"  delete-char
      [[ -n "$terminfo[kpp]"    ]] && bindkey "$terminfo[kpp]"    history-beginning-search-backward
      [[ -n "$terminfo[knp]"    ]] && bindkey "$terminfo[knp]"    history-beginning-search-forward

    '';
    shellAliases = {
      ".." = "cd ..";
      ls = "eza --icons=${ezaIcons}";
      ll = "eza -laF --icons=${ezaIcons}";
      llo = "eza -laF --sort=new --icons=${ezaIcons}";
      la = "eza -aF --icons=${ezaIcons}";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      status = "git status";
      m = "git switch main";
      k = "kubectl";
      grep = "grep --color=auto";
      dfh = "df -h";
      cp = "cp -i";
      mv = "mv -i";
      rm = "rm -i";
      vi = "nvim";
    };
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;

    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
      "--preview='(highlight -O ansi -l {} 2> /dev/null || cat {} || tree -C {}) 2> /dev/null | head -200'"
      "--bind pgup:preview-up,pgdn:preview-down"
      "--color preview-bg:240"
    ];
  };

  programs.git.settings = {
    user = {
      name = "emolinaro";
      email = "emil.molinaro@gmail.com";
    };
    fetch.prune = true;
    push.autoSetupRemote = true;
    rerere.enabled = true;
    rerere.autoUpdate = true;
    merge.conflictStyle = "zdiff3";
    worktree.guessRemote = true;
    core.editor = "nvim";
    core.pager = "delta";
    commit.verbose = true;
    interactive.diffFilter = "delta --color-only";
    delta = {
      navigate = true;
      line-numbers = true;
      side-by-side = false;
    };
  };

  programs.starship = {
    enable = true;

    settings = {
      add_newline = false;
      scan_timeout = 20;
      command_timeout = 300;

      format = "$username$hostname$directory$custom$git_branch$git_status$git_metrics$package$nix_shell$direnv$kubernetes$docker_context$python$nodejs$golang$cmd_duration$line_break$jobs$status$character";
      right_format = "$time";

      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
        vimcmd_symbol = "[❮](green)";
      };

      username = {
        show_always = false;
        style_user = "bold purple";
        format = "[$user]($style) ";
      };

      hostname = {
        ssh_only = true;
        style = "bold dimmed green";
        format = "[@$hostname]($style) ";
      };

      directory = {
        style = "bold cyan";
        truncation_length = 4;
        truncation_symbol = "⋯/";
        truncate_to_repo = true;
        read_only = " 󰌾";
      };

      custom.treehouse = {
        when = ''
          repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 1
          case "$repo_root" in
            "$HOME/.treehouse/"*) exit 0 ;;
            *) exit 1 ;;
          esac
        '';
        shell = [
          "/bin/bash"
          "--noprofile"
          "--norc"
        ];
        command = ''
          printf ""
        '';
        style = "bold green";
        format = "[$output]($style) ";
      };

      git_branch = {
        symbol = " ";
        style = "bold purple";
        format = "[$symbol$branch]($style) ";
      };

      git_status = {
        style = "bold red";
        format = "([$all_status$ahead_behind]($style) )";

        conflicted = "=";
        ahead = "⇡";
        behind = "⇣";
        diverged = "⇕";
        untracked = "?";
        stashed = "≡";
        modified = "!";
        staged = "+";
        renamed = "»";
        deleted = "✘";
      };

      git_metrics = {
        disabled = true;
        added_style = "bold green";
        deleted_style = "bold red";
        format = "([+$added]($added_style) )([-$deleted]($deleted_style) )";
      };

      package = {
        disabled = true;
        symbol = "pkg ";
        style = "bold 208";
        format = "[$symbol$version]($style) ";
      };

      nix_shell = {
        symbol = "❄ ";
        style = "bold blue";
        heuristic = true;
        format = "[$symbol$state]($style) ";
      };

      direnv = {
        disabled = false;
        symbol = "env ";
        style = "bold orange";
        format = "[$symbol$loaded/$allowed]($style) ";
      };

      kubernetes = {
        disabled = false;
        symbol = "☸ ";
        style = "bold blue";
        format = "[$symbol$context(::$namespace)]($style) ";

        contexts = [
          {
            context_pattern = ".*prod.*";
            context_alias = "prod";
            style = "bold red";
            symbol = "☸ ";
          }
          {
            context_pattern = ".*production.*";
            context_alias = "prod";
            style = "bold red";
            symbol = "☸ ";
          }
          {
            context_pattern = ".*dev.*";
            context_alias = "dev";
            style = "bold green";
            symbol = "☸ ";
          }
          {
            context_pattern = ".*test.*";
            context_alias = "test";
            style = "bold yellow";
            symbol = "☸ ";
          }
        ];
      };

      docker_context = {
        symbol = " ";
        style = "bold blue";
        format = "[$symbol$context]($style) ";
      };

      python = {
        symbol = "py ";
        style = "bold yellow";
        format = "[$symbol$pyenv_prefix$version $virtualenv]($style) ";
      };

      nodejs = {
        symbol = "node ";
        style = "bold green";
        format = "[$symbol$version]($style) ";
      };

      golang = {
        symbol = "go ";
        style = "bold cyan";
        format = "[$symbol$version]($style) ";
      };

      cmd_duration = {
        min_time = 500;
        style = "bold yellow";
        format = "took [$duration]($style) ";
      };

      jobs = {
        symbol = "✦ ";
        style = "bold blue";
        number_threshold = 2;
        symbol_threshold = 1;
      };

      status = {
        disabled = false;
        symbol = "✘ ";
        style = "bold red";
        format = "[$symbol$status]($style) ";
      };

      time = {
        disabled = false;
        time_format = "%H:%M";
        style = "dimmed white";
        format = "[$time]($style)";
      };
    };
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  # Git reads ~/.config/git/ignore by default (no core.excludesFile needed).
  home.file.".config/git/ignore".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/git/ignore";
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".zprofile" = lib.mkIf (!isLinux) {
    force = true;
    text = ''
      # OrbStack CLI integration; Homebrew setup is handled by nix-darwin.
      source ~/.orbstack/shell/init.zsh 2>/dev/null || true
    '';
  };
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".agents/skills/chrome-devtools-axi".source = chromeDevtoolsAxiSkill;
  home.file.".agents/skills/gh-axi".source = ghAxiSkill;
  home.file.".agents/skills/lavish".source = lavishSkill;
  home.file.".agents/skills/quota-axi".source = quotaAxiSkill;
  home.file.".agents/skills/superpowers" = {
    force = true;
    source = superpowersSkill;
  };
  home.file.".agents/skills/tasks-axi".source = tasksAxiSkill;
  home.file.".no-mistakes/config.yaml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.no-mistakes/config.yaml";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".pi/agent/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/opencode.json".text = builtins.toJSON {
    model = "openai/gpt-5.6-sol";
    plugin = [
      "superpowers@git+https://github.com/obra/superpowers.git#${superpowersRev}"
    ];
    provider.openai.models."gpt-5.6-sol" = {
      attachment = true;
      cost = {
        cache_read = 0.5;
        input = 5;
        output = 30;
      };
      family = "gpt-sol";
      id = "gpt-5.6-sol";
      limit = {
        context = 1050000;
        input = 922000;
        output = 128000;
      };
      modalities = {
        input = [
          "text"
          "image"
          "pdf"
        ];
        output = [ "text" ];
      };
      name = "GPT-5.6 Sol";
      reasoning = true;
      release_date = "2026-07-09";
      temperature = false;
      tool_call = true;
    };
    small_model = "openai/gpt-5.6-sol";
  };
  home.file.".config/wezterm" = lib.mkIf (!isLinux) {
    source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  };
  home.file."Library/Fonts/HackNerdFont-Regular.ttf" = hackFontEntry "Regular";
  home.file."Library/Fonts/HackNerdFont-Bold.ttf" = hackFontEntry "Bold";
  home.file."Library/Fonts/HackNerdFont-Italic.ttf" = hackFontEntry "Italic";
  home.file."Library/Fonts/HackNerdFont-BoldItalic.ttf" = hackFontEntry "BoldItalic";
  home.file.".config/tmux" = {
    force = true;
    source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/tmux";
  };
  home.file.".local/share/tmux/plugins/resurrect".source = pkgs.tmuxPlugins.resurrect;
  home.file.".local/share/tmux/plugins/continuum".source = pkgs.tmuxPlugins.continuum;
  home.file.".local/share/tmux/plugins/yank".source = pkgs.tmuxPlugins.yank;
  home.file.".config/treehouse".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/treehouse";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  home.file.".config/nono/profiles".source = nonoProfiles;

  home.activation.treeSitterParsers = lib.mkIf isLinux (
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      if [[ -z "''${DRY_RUN:-}" ]]; then
        export PATH="${
          lib.makeBinPath [
            pkgs.curl
            pkgs.gcc
            pkgs.git
            pkgs.tree-sitter
          ]
        }:$PATH"
        ${pkgs.neovim}/bin/nvim --headless "+Lazy! build nvim-treesitter" +qa
      fi
    ''
  );

  home.activation.nonoProfiles = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    if [[ -z "''${DRY_RUN:-}" ]]; then
      export DOTFILES_AGENT_HOME="$HOME/.cache/nono/profile-validation"
      export DOTFILES_HOST_HOME="$HOME"
      export SSH_AUTH_SOCK="''${SSH_AUTH_SOCK:-/nonexistent/nono-ssh-agent.sock}"
      for profile in ${lib.escapeShellArgs nonoProfileNames}; do
        ${lib.getExe nonoPackage} profile validate --strict \
          "${nonoProfiles}/$profile.json"
      done
    fi
  '';

  home.activation.gstackCheckoutMigration = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    set -euo pipefail
    if [[ -z "''${DRY_RUN:-}" ]]; then
      ${lib.getExe gstackCheckoutMigration} ${lib.escapeShellArg gstackCheckout}
    else
      ${lib.getExe gstackCheckoutMigration} --dry-run ${lib.escapeShellArg gstackCheckout}
    fi
  '';

  # Keep gstack writable because it builds platform-specific tooling.
  home.activation.codexExtensions =
    lib.hm.dag.entryAfter
      [
        "gstackCheckoutMigration"
        "installPackages"
      ]
      ''
        set -euo pipefail
        export PATH="${
          lib.makeBinPath [
            pkgs.bun
            pkgs.coreutils
            pkgs.gawk
            pkgs.git
            pkgs.jq
            pkgs.perl
          ]
        }:${platformPath}:$PATH:/usr/bin:/bin:/usr/sbin:/sbin"

        gstack_dir=${lib.escapeShellArg gstackCheckout}
        if [[ ! -d "$gstack_dir/.git" ]]; then
          $DRY_RUN_CMD mkdir -p "$(dirname "$gstack_dir")"
          # Clone without a working tree, then materialize the flake-pinned revision.
          # A plain clone would leave default-branch files that are not the pin.
          $DRY_RUN_CMD ${pkgs.git}/bin/git clone --no-checkout \
            https://github.com/garrytan/gstack.git "$gstack_dir"
          if [[ -z "''${DRY_RUN:-}" ]]; then
            ${pkgs.git}/bin/git -C "$gstack_dir" fetch --depth 1 origin ${lib.escapeShellArg gstackRev}
            ${pkgs.git}/bin/git -C "$gstack_dir" checkout --detach ${lib.escapeShellArg gstackRev}
          fi
        fi

        if [[ -z "''${DRY_RUN:-}" ]]; then
          # Recover clones left empty by an interrupted earlier bootstrap/activate.
          if [[ ! -e "$gstack_dir/setup" ]]; then
            ${pkgs.git}/bin/git -C "$gstack_dir" fetch --depth 1 origin ${lib.escapeShellArg gstackRev}
            ${pkgs.git}/bin/git -C "$gstack_dir" checkout --detach ${lib.escapeShellArg gstackRev}
          fi

          setup_state_file="$HOME/.gstack/.dotfiles-setup-state"
          expected_setup_state="gstack=${gstackRev};hosts=auto-prefix-v1"
          current_setup_state=""
          if [[ -r "$setup_state_file" ]]; then
            current_setup_state="$(<"$setup_state_file")"
          fi
          legacy_setup_state="gstack=${gstackRev};superpowers=${superpowersRev};hosts=auto-prefix-v1"
          if [[ "$current_setup_state" == "$legacy_setup_state" ]]; then
            current_setup_state="$expected_setup_state"
            printf '%s\n' "$expected_setup_state" > "$setup_state_file"
          fi
          current_gstack_rev="$(${pkgs.git}/bin/git -C "$gstack_dir" rev-parse HEAD 2>/dev/null || true)"

          needs_gstack_setup=0
          if [[ "$current_setup_state" != "$expected_setup_state" \
            || "$current_gstack_rev" != ${lib.escapeShellArg gstackRev} \
            || ! -x "$gstack_dir/browse/dist/browse" \
            || ! -e "$HOME/.claude/skills/gstack" \
            || ! -e "$HOME/.codex/skills/gstack" \
            || ! -e "$HOME/.config/opencode/skills/gstack" ]]; then
            needs_gstack_setup=1
          fi

          if [[ "$needs_gstack_setup" -eq 1 ]]; then
            # A prefixed Claude install rewrites tracked skill names. Normalize only
            # before an update so the guard still detects genuine local changes.
            "$gstack_dir/bin/gstack-patch-names" "$gstack_dir" 0
            if [[ -n "$(${pkgs.git}/bin/git -C "$gstack_dir" status --porcelain)" ]]; then
              echo "error: $gstack_dir has local changes; refusing to replace them" >&2
              exit 1
            fi
            if [[ "$current_gstack_rev" != ${lib.escapeShellArg gstackRev} ]]; then
              ${pkgs.git}/bin/git -C "$gstack_dir" fetch --depth 1 origin ${lib.escapeShellArg gstackRev}
              ${pkgs.git}/bin/git -C "$gstack_dir" checkout --detach ${lib.escapeShellArg gstackRev}
            fi

            # One auto setup installs every available agent host without regenerating
            # the shared Codex skill set once per host.
            "$gstack_dir/setup" --host auto --prefix --quiet
            printf '%s\n' "$expected_setup_state" > "$setup_state_file"
          fi

          gstack_link="$HOME/.agents/skills/gstack"
          mkdir -p "$(dirname "$gstack_link")"
          if [[ -L "$gstack_link" ]]; then
            ln -sfn "$gstack_dir/.agents/skills" "$gstack_link"
          elif [[ ! -e "$gstack_link" ]]; then
            ln -s "$gstack_dir/.agents/skills" "$gstack_link"
          else
            echo "error: $gstack_link exists and is not a symlink" >&2
            exit 1
          fi

        fi
      '';

  # Install Herdr's official hooks/plugins after the managed agent configs exist.
  home.activation.herdrIntegrations = lib.hm.dag.entryAfter [ "codexExtensions" "nonoProfiles" ] ''
    if [[ -z "''${DRY_RUN:-}" ]]; then
      mkdir -p "$HOME/.pi/agent/extensions"
      ${herdrCommand} integration install claude
      ${herdrCommand} integration install codex
      ${herdrCommand} integration install opencode
      ${herdrCommand} integration install pi

      # Herdr writes an absolute Claude hook path and may append the same hook again.
      # Keep the tracked settings portable and the SessionStart hooks idempotent.
      portable_claude_settings="$(${pkgs.coreutils}/bin/mktemp)"
      ${pkgs.jq}/bin/jq '
        (.hooks.SessionStart[]?.hooks[]?
          | select((.command? // "") | contains("herdr-agent-state.sh"))
          | .command) = "bash \"$HOME/.claude/hooks/herdr-agent-state.sh\" session"
        | .hooks.SessionStart |= reduce .[] as $hook (
            [];
            if any(.[]; . == $hook) then . else . + [$hook] end
          )
      ' "$HOME/.claude/settings.json" > "$portable_claude_settings"
      ${pkgs.coreutils}/bin/cp "$portable_claude_settings" "${dotfiles}/home/.claude/settings.json"
      ${pkgs.coreutils}/bin/rm "$portable_claude_settings"
    fi
  '';
}
