{
  nvimKeys,
  pkgs,
  weztermConfig,
}:

pkgs.runCommand "clipboard-keybindings-test"
  {
    nativeBuildInputs = [
      pkgs.gawk
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail

    require_line() {
      local needle="$1"
      local file="$2"
      local description="$3"
      if ! grep -Fq -- "$needle" "$file"; then
        echo "missing: $description" >&2
        exit 1
      fi
    }

    cmd_c_callback="$TMPDIR/cmd-c-callback.lua"
    awk '
      /key = "c",/ { capture = 1 }
      capture { print }
      capture && /^  },$/ { exit }
    ' "${weztermConfig}" > "$cmd_c_callback"

    require_line 'config.enable_kitty_keyboard = true' "${weztermConfig}" \
      'WezTerm Kitty keyboard protocol'
    require_line 'mods = "CMD"' "$cmd_c_callback" \
      'Cmd+C WezTerm binding'
    require_line 'window:get_selection_text_for_pane(pane) == ""' "$cmd_c_callback" \
      'empty WezTerm selection branch'
    require_line 'wezterm.action.SendKey({ key = "c", mods = "CMD" })' "$cmd_c_callback" \
      'Cmd+C forwarding action'
    require_line 'wezterm.action.CopyTo("Clipboard")' "$cmd_c_callback" \
      'terminal selection copy action'
    require_line "vim.keymap.set('v', '<D-c>', '\"+y'," "${nvimKeys}" \
      'Neovim visual selection clipboard mapping'

    touch "$out"
  ''
