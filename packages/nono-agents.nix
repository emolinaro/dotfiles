{
  claude = {
    clientArguments = [ ];
    filteredJsonPaths = [
      {
        filter = "del(.hooks)";
        source = ".claude/settings.json";
        target = ".claude/settings.json";
      }
    ];
    persistentFiles = [
      ".claude/.credentials.json"
    ];
    profile = "dotfiles-claude";
    stagedPaths = [
      {
        source = ".agents";
        target = ".agents";
      }
      {
        source = ".claude/CLAUDE.md";
        target = ".claude/CLAUDE.md";
      }
      {
        source = ".claude/skills";
        target = ".claude/skills";
      }
    ];
  };
  codex = {
    clientArguments = [
      "--sandbox"
      "danger-full-access"
      "--ask-for-approval"
      "on-request"
    ];
    filteredJsonPaths = [ ];
    persistentFiles = [
      ".codex/auth.json"
    ];
    profile = "dotfiles-codex";
    stagedPaths = [
      {
        source = ".agents";
        target = ".agents";
      }
      {
        source = ".codex/AGENTS.md";
        target = ".codex/AGENTS.md";
      }
      {
        source = ".codex/config.toml";
        target = ".codex/config.toml";
      }
      {
        source = ".codex/hooks.json";
        target = ".codex/hooks.json";
      }
      {
        source = ".codex/plugins";
        target = ".codex/plugins";
      }
      {
        source = ".codex/rules";
        target = ".codex/rules";
      }
      {
        source = ".codex/skills";
        target = ".codex/skills";
      }
    ];
  };
  opencode = {
    clientArguments = [ ];
    filteredJsonPaths = [ ];
    persistentFiles = [
      ".local/share/opencode/auth.json"
    ];
    profile = "dotfiles-opencode";
    stagedPaths = [
      {
        source = ".agents";
        target = ".agents";
      }
      {
        source = ".config/opencode/AGENTS.md";
        target = ".config/opencode/AGENTS.md";
      }
      {
        source = ".config/opencode/opencode.json";
        target = ".config/opencode/opencode.json";
      }
      {
        source = ".config/opencode/plugins";
        target = ".config/opencode/plugins";
      }
      {
        source = ".config/opencode/skills";
        target = ".config/opencode/skills";
      }
    ];
  };
  pi = {
    clientArguments = [ ];
    filteredJsonPaths = [ ];
    persistentFiles = [
      ".pi/agent/auth.json"
    ];
    profile = "dotfiles-pi";
    stagedPaths = [
      {
        source = ".agents";
        target = ".agents";
      }
      {
        source = ".pi/agent/AGENTS.md";
        target = ".pi/agent/AGENTS.md";
      }
      {
        source = ".pi/agent/settings.json";
        target = ".pi/agent/settings.json";
      }
    ];
  };
}
