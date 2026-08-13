local wezterm = require("wezterm")

local config = wezterm.config_builder()

config.enable_kitty_graphics = true

local function with_alpha(color, alpha)
  local h, s, l, _ = wezterm.color.parse(color):hsla()
  return wezterm.color.from_hsla(h, s, l, alpha)
end

local function first_non_nil(...)
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if value ~= nil then
      return value
    end
  end
  return nil
end

-- ui
-- Use the WebGpu/Metal renderer: the default OpenGL front end freezes/crashes
-- when resuming from the macOS lock screen or display sleep (wezterm#7291).
config.front_end = "WebGpu"
config.color_scheme = "rose-pine-moon"
local window_bg_opacity = 0.8
local builtin_schemes = wezterm.color.get_builtin_schemes()
local active_scheme = builtin_schemes[config.color_scheme] or {}
local scheme_tab_bar = active_scheme.tab_bar or {}
local scheme_bg = active_scheme.background or "#232136"
local scheme_fg = active_scheme.foreground or "#e0def4"
local selection_bg = "#f6c177"
local selection_fg = "#232136"
local terminal_bg_with_alpha = with_alpha(scheme_bg, window_bg_opacity)
local inactive_tab_fg = first_non_nil(scheme_tab_bar.inactive_tab and scheme_tab_bar.inactive_tab.fg_color, scheme_fg)
local new_tab_fg = first_non_nil(scheme_tab_bar.new_tab and scheme_tab_bar.new_tab.fg_color, inactive_tab_fg)
local active_tab_bg = "#f6c177"
local active_tab_fg = "#232136"
local hover_tab_bg = "#9ccfd8"
local hover_tab_fg = "#232136"
config.colors = {
  selection_bg = selection_bg,
  selection_fg = selection_fg,
  tab_bar = {
    background = terminal_bg_with_alpha,
    active_tab = {
      bg_color = active_tab_bg,
      fg_color = active_tab_fg,
      intensity = "Bold",
    },
    inactive_tab = {
      bg_color = terminal_bg_with_alpha,
      fg_color = inactive_tab_fg,
    },
    inactive_tab_hover = {
      bg_color = hover_tab_bg,
      fg_color = hover_tab_fg,
    },
    new_tab = {
      bg_color = terminal_bg_with_alpha,
      fg_color = new_tab_fg,
    },
    new_tab_hover = {
      bg_color = hover_tab_bg,
      fg_color = hover_tab_fg,
    },
    inactive_tab_edge = terminal_bg_with_alpha,
  },
}
config.max_fps = 120
config.font = wezterm.font("Hack Nerd Font", { weight = "Regular" })
config.font_size = 15.0
config.window_background_opacity = window_bg_opacity
config.macos_window_background_blur = 50
config.hide_tab_bar_if_only_one_tab = true
config.skip_close_confirmation_for_processes_named = {}
config.window_close_confirmation = "AlwaysPrompt"
config.window_decorations = "RESIZE"
config.window_frame = {
  font = wezterm.font("Hack Nerd Font", { weight = "Bold" }),
  font_size = 15.0,
  active_titlebar_bg = terminal_bg_with_alpha,
  inactive_titlebar_bg = terminal_bg_with_alpha,
}

config.inactive_pane_hsb = {
  saturation = 0.0,
  brightness = 0.5,
}

-- keys
local maximize_window = wezterm.action_callback(function(window, _pane)
  window:maximize()
end)

local function snap_window(direction)
  return wezterm.action_callback(function(window, _pane)
    local screen = wezterm.gui.screens().active
    if not screen then
      return
    end

    local half_width = math.floor(screen.width / 2)
    local half_height = math.floor(screen.height / 2)
    local x = screen.x
    local y = screen.y
    local width = screen.width
    local height = screen.height

    if direction == "left" then
      width = half_width
    elseif direction == "right" then
      x = screen.x + half_width
      width = screen.width - half_width
    elseif direction == "top" then
      height = half_height
    elseif direction == "bottom" then
      y = screen.y + half_height
      height = screen.height - half_height
    end

    window:restore()
    window:set_inner_size(width, height)
    window:set_position(x, y)
  end)
end

config.disable_default_key_bindings = true
config.leader = { key = "Space", mods = "CTRL" }
config.keys = {
  -- clipboard
  -- CMD+C copies WezTerm's own selection when there is one (shells, Shift+drag
  -- over nvim). With no selection it forwards the key to the app so nvim can
  -- yank its visual selection (mapped in ~/.config/nvim/lua/keys.lua).
  {
    key = "c",
    mods = "CMD",
    action = wezterm.action_callback(function(window, pane)
      if window:get_selection_text_for_pane(pane) == "" then
        window:perform_action(wezterm.action.SendKey({ key = "c", mods = "CMD" }), pane)
      else
        window:perform_action(wezterm.action.CopyTo("Clipboard"), pane)
      end
    end),
  },
  { key = "v", mods = "CMD", action = wezterm.action.PasteFrom("Clipboard") },

  -- tabs
  { key = "c", mods = "LEADER", action = wezterm.action.SpawnTab("CurrentPaneDomain") },
  { key = "t", mods = "CMD", action = wezterm.action.SpawnTab("CurrentPaneDomain") },
  { key = "n", mods = "LEADER", action = wezterm.action.ActivateTabRelative(1) },
  { key = "p", mods = "LEADER", action = wezterm.action.ActivateTabRelative(-1) },
  { key = "}", mods = "CMD", action = wezterm.action.ActivateTabRelative(1) },
  { key = "{", mods = "CMD", action = wezterm.action.ActivateTabRelative(-1) },

  -- windows
  { key = "n", mods = "CMD", action = wezterm.action.SpawnWindow },
  { key = "w", mods = "CMD", action = wezterm.action.CloseCurrentTab({ confirm = true }) },
  { key = "f", mods = "CMD|CTRL", action = wezterm.action.ToggleFullScreen },
  { key = "LeftArrow", mods = "CTRL|ALT", action = snap_window("left") },
  { key = "RightArrow", mods = "CTRL|ALT", action = snap_window("right") },
  { key = "UpArrow", mods = "CTRL|ALT", action = snap_window("top") },
  { key = "DownArrow", mods = "CTRL|ALT", action = snap_window("bottom") },

  -- splits (panes)
  --  { key = "d", mods = "CTRL", action = wezterm.action.CloseCurrentPane({ confirm = true }) },
  { key = "v", mods = "LEADER", action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "-", mods = "LEADER", action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { key = "x", mods = "LEADER", action = wezterm.action.CloseCurrentPane({ confirm = true }) },
  { key = "z", mods = "LEADER", action = wezterm.action.TogglePaneZoomState },
  { key = "m", mods = "LEADER", action = maximize_window },

  -- pane navigation (vim-style)
  { key = "h", mods = "LEADER", action = wezterm.action.ActivatePaneDirection("Left") },
  { key = "j", mods = "LEADER", action = wezterm.action.ActivatePaneDirection("Down") },
  { key = "k", mods = "LEADER", action = wezterm.action.ActivatePaneDirection("Up") },
  { key = "l", mods = "LEADER", action = wezterm.action.ActivatePaneDirection("Right") },

  -- pane resizing
  { key = "h", mods = "LEADER|SHIFT", action = wezterm.action.AdjustPaneSize({ "Left", 5 }) },
  { key = "j", mods = "LEADER|SHIFT", action = wezterm.action.AdjustPaneSize({ "Down", 5 }) },
  { key = "k", mods = "LEADER|SHIFT", action = wezterm.action.AdjustPaneSize({ "Up", 5 }) },
  { key = "l", mods = "LEADER|SHIFT", action = wezterm.action.AdjustPaneSize({ "Right", 5 }) },

  -- font size
  { key = "=", mods = "CMD", action = wezterm.action.IncreaseFontSize },
  { key = "-", mods = "CMD", action = wezterm.action.DecreaseFontSize },
  { key = "0", mods = "CMD", action = wezterm.action.ResetFontSize },
}

return config
