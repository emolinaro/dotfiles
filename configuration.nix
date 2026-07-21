{ homeDirectory, username, ... }:

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel CPU

  # Avoid re-evaluating all nix-darwin options to generate the local manual and options.json.
  documentation.enable = false;

  system.primaryUser = username;
  programs.zsh = {
    enable = true;
    # Home Manager initializes native Zsh completion. Avoid running compinit twice,
    # and do not load bashcompinit, which is only Bash-completion compatibility inside Zsh.
    enableCompletion = false;
    enableBashCompletion = false;
    promptInit = "";
  };
  users.users.${username} = {
    home = homeDirectory;
  };
  system.stateVersion = 6;
  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = true;  # auto-hide the menu bar
      AppleShowAllExtensions = true;
    };
    dock.autohide = true;
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click
  };
  nix-homebrew = {
    enable = true;
    user = username;
  };
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" ];
    brews = [
      "herdr"
      "opencode"
      "pi-coding-agent"
    ];
    casks = [
      "wezterm"
      "orbstack"
      "claude-code"
      "codex"
    ];
  };
}
