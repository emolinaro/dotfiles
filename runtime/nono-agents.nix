let
  commonWritableDirectories = [
    ".gstack"
  ];
  commonStagedPaths = [
    {
      source = ".agents";
      target = ".agents";
    }
    {
      copy = true;
      source = ".config/git/config";
      target = ".config/git/config";
    }
  ];
in
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
    stagedPaths = commonStagedPaths ++ [
      {
        source = ".claude/CLAUDE.md";
        target = ".claude/CLAUDE.md";
      }
      {
        source = ".claude/skills";
        target = ".claude/skills";
      }
      {
        source = ".claude.json";
        target = ".claude.json";
      }
    ];
    writableDirectories = commonWritableDirectories ++ [
      ".claude"
      ".cache/claude"
      ".cache/claude-cli-nodejs"
      ".local/state/claude/locks"
    ];
    writableFiles = [
      ".claude.json"
      ".claude.json.lock"
      ".claude.lock"
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
    stagedPaths = commonStagedPaths ++ [
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
    writableDirectories = commonWritableDirectories ++ [
      ".codex"
    ];
    writableFiles = [ ];
  };
  opencode = {
    clientArguments = [ ];
    filteredJsonPaths = [ ];
    persistentFiles = [
      ".local/share/opencode/auth.json"
    ];
    profile = "dotfiles-opencode";
    stagedPaths = commonStagedPaths ++ [
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
    writableDirectories = commonWritableDirectories ++ [
      ".opencode"
      ".config/opencode"
      ".cache/opencode"
      ".local/share/opencode"
      ".local/share/opentui"
      ".local/state/opencode"
    ];
    writableFiles = [ ];
  };
  pi = {
    clientArguments = [ ];
    filteredJsonPaths = [ ];
    persistentFiles = [
      ".pi/agent/auth.json"
    ];
    profile = "dotfiles-pi";
    stagedPaths = commonStagedPaths ++ [
      {
        source = ".pi/agent/AGENTS.md";
        target = ".pi/agent/AGENTS.md";
      }
      {
        source = ".pi/agent/settings.json";
        target = ".pi/agent/settings.json";
      }
      {
        source = ".pi/agent/trust.json";
        target = ".pi/agent/trust.json";
      }
    ];
    writableDirectories = commonWritableDirectories ++ [
      ".pi"
    ];
    writableFiles = [ ];
  };
}
