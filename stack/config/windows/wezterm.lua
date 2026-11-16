local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- ── Font & appearance ────────────────────────────────────────────────────────

config.font = wezterm.font('Cascadia Code', { weight = 'Regular' })
config.font_size = 11.0
config.color_scheme = 'Tokyo Night'
config.enable_tab_bar = true
config.tab_bar_at_bottom = true
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = false

-- ── Domains ──────────────────────────────────────────────────────────────────

config.wsl_domains = {
  { name = 'WSL:Ubuntu', distribution = 'Ubuntu', default_cwd = '/home/deanj' },
}

config.ssh_domains = {
  {
    name = 'dell-server',
    remote_address = 'dell-server',
    username = 'srvr',
    -- Multiplexes panes/tabs natively over SSH; no separate tmux needed on remote
    multiplexing = 'WezTerm',
  },
}

-- ── Default profile: WSL2 Ubuntu ─────────────────────────────────────────────

config.default_domain = 'WSL:Ubuntu'

-- Default shell command: attach to existing argus Zellij session or create it.
-- Update this once Zellij replaces tmux (ADR-002).
config.default_prog = { 'bash', '-ic', 'zellij attach argus 2>/dev/null || tmux attach -t main || bash' }

-- ── Per-project tab colours ───────────────────────────────────────────────────

local project_colors = {
  argus       = '#F59E0B',
  atto1       = '#2563EB',
  ['ios-scripts'] = '#EC4899',
  ['linux-server'] = '#10B981',
  myargus     = '#EAB308',
  budget      = '#22C55E',
  ['vault-sync'] = '#F43F5E',
  stockade    = '#F97316',
  ['erto-apps']  = '#A855F7',
  cmdpal      = '#06B6D4',
  ['ghostty-win'] = '#84CC16',
}

wezterm.on('format-tab-title', function(tab, _tabs, _panes, _config, _hover, _max_width)
  local title = tab.active_pane.title or ''
  for project, color in pairs(project_colors) do
    if title:lower():find(project, 1, true) then
      return {
        { Background = { Color = color } },
        { Foreground = { Color = '#FFFFFF' } },
        { Text = ' ' .. title .. ' ' },
      }
    end
  end
  -- Default: no colour override
  return { { Text = ' ' .. title .. ' ' } }
end)

-- ── Keys ─────────────────────────────────────────────────────────────────────

config.keys = {
  -- New tab
  { key = 't', mods = 'CTRL|SHIFT', action = wezterm.action.SpawnTab 'CurrentPaneDomain' },
  -- Split horizontal / vertical
  { key = 'd', mods = 'CTRL|SHIFT', action = wezterm.action.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'e', mods = 'CTRL|SHIFT', action = wezterm.action.SplitVertical   { domain = 'CurrentPaneDomain' } },
  -- Tab navigation
  { key = 'LeftArrow',  mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTabRelative(-1) },
  { key = 'RightArrow', mods = 'CTRL|SHIFT', action = wezterm.action.ActivateTabRelative(1) },
  -- Pane navigation
  { key = 'h', mods = 'CTRL|SHIFT', action = wezterm.action.ActivatePaneDirection 'Left' },
  { key = 'l', mods = 'CTRL|SHIFT', action = wezterm.action.ActivatePaneDirection 'Right' },
  { key = 'k', mods = 'CTRL|SHIFT', action = wezterm.action.ActivatePaneDirection 'Up' },
  { key = 'j', mods = 'CTRL|SHIFT', action = wezterm.action.ActivatePaneDirection 'Down' },
  -- Open dell-server SSH tab
  {
    key = 's',
    mods = 'CTRL|SHIFT|ALT',
    action = wezterm.action.SpawnTab { DomainName = 'dell-server' },
  },
}

return config
