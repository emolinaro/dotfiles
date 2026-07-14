{ config, homeDirectory, lib, pkgs, username, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  codexCommand = if isLinux then "${pkgs.codex}/bin/codex" else "codex";
  superpowersMarketplace = if isLinux then "superpowers-dev" else "openai-curated";
  superpowersPlugin = "superpowers@${superpowersMarketplace}";
  platformPath = if isLinux then "/usr/local/bin" else "/opt/homebrew/bin:/usr/local/bin";
in

{
  home.username = username;
  home.homeDirectory = homeDirectory;
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    git
    lazygit
    neovim
    highlight
    tree
    uv
    bun
    coreutils # gstack uses gtimeout to bound nested Codex calls
  ] ++ lib.optionals isLinux [
    pkgs.codex
    pkgs.docker-client
    pkgs.docker-compose
  ] ++ [
    
    # the font everything renders in
    nerd-fonts.hack
  ];
  fonts.fontconfig.enable = true;
  home.sessionVariables = {
    EDITOR = "nvim";
    DOTFILES = "${config.home.homeDirectory}/.dotfiles";
    CDPATH = "${config.home.homeDirectory}/Documents/GITHUB";
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = ''
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
      add = "git add .";
      push = "git push";
      pull = "git pull";
      m = "git switch main";
      k = "kubectl";
      grep = "grep --color=auto";
      dfh = "df -h";
      cp = "cp -i";
      mv = "mv -i";
      rm = "rm -i";
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

  programs.git.settings.user = {
    name = "emolinaro";
    email = "40191802+emolinaro@users.noreply.github.com";
  };

  programs.starship = {
    enable = true;

    settings = {
      add_newline = false;
      scan_timeout = 30;
      command_timeout = 1000;

      format = "$username$hostname$directory$git_branch$git_status$git_metrics$package$nix_shell$direnv$kubernetes$docker_context$python$nodejs$rust$golang$cmd_duration$line_break$jobs$status$character";
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
        truncation_symbol = "…/";
        truncate_to_repo = true;
        read_only = " 󰌾";
      };

      git_branch = {
        symbol = " ";
        style = "bold purple";
        format = "on [$symbol$branch]($style) ";
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
        disabled = false;
        added_style = "bold green";
        deleted_style = "bold red";
        format = "([+$added]($added_style) )([-$deleted]($deleted_style) )";
      };

      package = {
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

      rust = {
        symbol = "rs ";
        style = "bold red";
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


#  programs.starship = {
#    enable = true;
#    settings = {
#      add_newline = false;
#      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
#      character = {
#        success_symbol = "[❯](purple)";
#        error_symbol = "[❯](red)";
#      };
#      cmd_duration.format = "[$duration]($style) ";
#    };
#  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".codex/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/opencode/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";
  home.file.".config/wezterm" = lib.mkIf (!isLinux) {
    source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/wezterm";
  };
  home.file.".config/herdr" = lib.mkIf (!isLinux) {
    source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  };

  # Install Codex extensions automatically on a fresh machine. gstack keeps its
  # own checkout for upgrades, while Superpowers comes from Codex's marketplace.
  home.activation.codexExtensions = lib.hm.dag.entryAfter [ "installPackages" ] ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [ pkgs.bun pkgs.coreutils pkgs.gawk pkgs.git pkgs.jq pkgs.perl ]}:${platformPath}:$PATH:/usr/bin:/bin:/usr/sbin:/sbin"

    gstack_dir="$HOME/.gstack/repos/gstack"
    if [[ ! -d "$gstack_dir/.git" ]]; then
      $DRY_RUN_CMD mkdir -p "$(dirname "$gstack_dir")"
      $DRY_RUN_CMD ${pkgs.git}/bin/git clone --single-branch --depth 1 \
        https://github.com/garrytan/gstack.git "$gstack_dir"
    elif [[ -z "''${DRY_RUN:-}" ]]; then
      ${pkgs.git}/bin/git -C "$gstack_dir" pull --ff-only
    fi

    if [[ -z "''${DRY_RUN:-}" ]]; then
      "$gstack_dir/setup" --host codex --prefix --quiet
      if ! ${codexCommand} plugin marketplace list | grep -q '${superpowersMarketplace}'; then
        ${lib.optionalString isLinux "${codexCommand} plugin marketplace add obra/superpowers"}
        :
      fi
      if ! ${codexCommand} plugin list \
        | awk '$1 == "${superpowersPlugin}" && $2 ~ /^installed/ { found = 1 } END { exit !found }'; then
        ${codexCommand} plugin add ${superpowersPlugin}
      fi
    fi
  '';
}
