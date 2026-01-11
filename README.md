# WezTerm Agent Deck

A WezTerm plugin that monitors and displays the status of AI coding agents (OpenCode, Claude, etc.) running in terminal panes. It provides real-time status indicators in tab titles and the status bar, with notification support for when agents need user attention.

## Features

- **Real-time Agent Monitoring**: Detects AI coding agents running in terminal panes
- **Status Detection**: Identifies agent states (working, waiting for input, idle)
- **Tab Title Integration**: Shows agent status icons in tab titles
- **Status Bar**: Aggregate view of all agents in the right status bar
- **Toast Notifications**: Get notified when agents need your attention
- **Extensible**: Easy to add support for additional AI agents
- **Composable**: Customizable display components

## Installation

Add the plugin to your WezTerm configuration:

```lua
local wezterm = require('wezterm')
local agent_deck = wezterm.plugin.require('https://github.com/yourusername/wezterm-agent-deck')

local config = wezterm.config_builder()

-- Apply with default settings
agent_deck.apply_to_config(config)

return config
```

## Configuration

### Canonical "Inline" Setup (like OpenCode)

If you want something that behaves like the inline setup we’ve been iterating on (scan every pane in the window, show one dot per pane in each tab, and avoid stale "working" when OpenCode has finished), you can drop this into your `~/.config/wezterm/wezterm.lua`.

This approach does **not** rely on the plugin loader and is useful while developing locally.

```lua
local wezterm = require 'wezterm'

local config = wezterm.config_builder()

-- Tune responsiveness
config.status_update_interval = 500

local agent_colors = {
  working = '#A6E22E',
  waiting = '#E6DB74',
  idle = '#66D9EF',
  inactive = '#888888',
}

local agent_icons = {
  working = '●',
  waiting = '◐',
  idle = '○',
  inactive = '◌',
}

local agent_states = {}
local opencode_activity = {}
local prev_agent_states = {}

local function bump_refresh(window)
  pcall(function()
    local overrides = window:get_config_overrides() or {}
    overrides.__agent_deck_refresh = (overrides.__agent_deck_refresh or 0) + 1
    window:set_config_overrides(overrides)
  end)
end

local function detect_opencode_status(pane_id, pane)
  local status = 'idle'

  local now_ms = (function()
    local ok, t = pcall(function() return tonumber(wezterm.time.now()) end)
    if ok and t then return math.floor(t * 1000) end
    return os.time() * 1000
  end)()

  local ok, text = pcall(function() return pane:get_lines_as_text(150) end)
  if not ok or not text or #text == 0 then
    return status
  end

  local lines = {}
  for line in text:gmatch('[^\n]+') do
    table.insert(lines, line)
  end

  local tail_start = math.max(1, #lines - 10 + 1)
  local tail_text = table.concat(lines, '\n', tail_start, #lines)
  local tail_lower = tail_text:lower()

  -- Track whether the OpenCode UI is actively changing; its animated blocks
  -- update the viewport while the agent is working.
  local entry = opencode_activity[pane_id]
  if not entry then
    opencode_activity[pane_id] = { last = tail_text, last_change_ms = now_ms }
  elseif entry.last ~= tail_text then
    entry.last = tail_text
    entry.last_change_ms = now_ms
  end

  local waiting_patterns = {
    'allow once', 'allow always', 'deny',
    'esc to cancel', 'yes, allow',
    '(y/n)', '[y/n]', '(Y/n)', '[Y/n]', '(y/N)', '[y/N]',
    'proceed?', 'continue?',
    'permission',
  }

  for _, pat in ipairs(waiting_patterns) do
    if tail_lower:find(pat, 1, true) then
      return 'waiting'
    end
  end

  local working_patterns = {
    'esc to interrupt',
    'esc interrupt',
    -- Common OpenCode spinner/block glyphs
    '█', '■', '▮', '▪', '▰',
  }

  for _, pat in ipairs(working_patterns) do
    if tail_lower:find(pat, 1, true) or tail_text:find(pat, 1, true) then
      status = 'working'
      break
    end
  end

  -- If it looks "working" but the viewport hasn't changed recently,
  -- treat it as idle (avoids stale "working" after completion).
  if status == 'working' then
    entry = opencode_activity[pane_id]
    if not entry or (now_ms - entry.last_change_ms) > 2000 then
      status = 'idle'
    end
  end

  return status
end

local function update_pane_agent_state(pane)
  local pane_id = pane:pane_id()

  local ok, info = pcall(function() return pane:get_foreground_process_info() end)
  local argv = ok and info and table.concat(info.argv or {}, ' '):lower() or ''
  local exe = ok and info and (info.executable or ''):lower() or ''

  local is_opencode = exe:find('opencode', 1, true) or argv:find('opencode', 1, true)
  if not is_opencode then
    agent_states[pane_id] = nil
    opencode_activity[pane_id] = nil
    return
  end

  agent_states[pane_id] = {
    agent_type = 'opencode',
    status = detect_opencode_status(pane_id, pane),
  }
end

wezterm.on('update-status', function(window, pane)
  for _, tab in ipairs(window:mux_window():tabs()) do
    for _, p in ipairs(tab:panes()) do
      update_pane_agent_state(p)
    end
  end

  local state_changed = false
  for pane_id, state in pairs(agent_states) do
    local prev = prev_agent_states[pane_id]
    if not prev or prev.status ~= state.status then
      state_changed = true
      break
    end
  end

  prev_agent_states = {}
  for pane_id, state in pairs(agent_states) do
    prev_agent_states[pane_id] = { status = state.status }
  end

  if state_changed then
    bump_refresh(window)
  end
end)

wezterm.on('format-tab-title', function(tab, tabs, panes, cfg, hover, max_width)
  local title = tab.tab_title
  if not title or #title == 0 then
    local process = tab.active_pane.foreground_process_name or tab.active_pane.title or ''
    title = process:gsub('(.*[/\\])(.*)', '%2')
  end
  if not title or #title == 0 then
    title = 'Terminal'
  end

  local formatted = { { Text = ' ' } }
  local dots = {}
  for _, pane_info in ipairs(tab.panes or {}) do
    local st = agent_states[pane_info.pane_id]
    if st then
      table.insert(dots, st)
    end
  end

  for i, st in ipairs(dots) do
    local color = agent_colors[st.status] or agent_colors.inactive
    local icon = agent_icons[st.status] or agent_icons.inactive
    table.insert(formatted, { Foreground = { Color = color } })
    table.insert(formatted, { Text = icon })
    if i < #dots then
      -- Thin space between dots
      table.insert(formatted, { Text = ' ' })
    end
  end

  table.insert(formatted, { Foreground = 'Default' })
  table.insert(formatted, { Text = string.format(' %d: %s ', tab.tab_index + 1, title) })

  return wezterm.format(formatted)
end)

return config
```

### Basic Configuration

```lua
local wezterm = require('wezterm')
local agent_deck = wezterm.plugin.require('https://github.com/yourusername/wezterm-agent-deck')

local config = wezterm.config_builder()

agent_deck.apply_to_config(config, {
    -- Polling interval (ms) - default 5000
    update_interval = 5000,
    
    -- Anti-flicker delay (ms) - default 2000
    cooldown_ms = 2000,
    
    -- Enable/disable features
    tab_title = {
        enabled = true,
        position = 'left',  -- 'left' or 'right'
    },
    right_status = {
        enabled = true,
    },
    notifications = {
        enabled = true,
        on_waiting = true,
        timeout_ms = 4000,
    },
})

return config
```

### Custom Colors

```lua
agent_deck.apply_to_config(config, {
    colors = {
        working = '#00ff00',   -- Green
        waiting = '#ffff00',   -- Yellow
        idle = '#0088ff',      -- Blue
        inactive = '#888888',  -- Gray
    },
})
```

### Icon Styles

Choose from three icon styles: `unicode`, `nerd` (Nerd Fonts), or `emoji`:

```lua
agent_deck.apply_to_config(config, {
    icons = {
        style = 'nerd',  -- 'unicode', 'nerd', or 'emoji'
    },
})
```

### Custom Tab Title Components

```lua
agent_deck.apply_to_config(config, {
    tab_title = {
        enabled = true,
        position = 'left',
        components = {
            { type = 'icon' },
            { type = 'separator', text = ' ' },
            { type = 'agent_name', short = true },
        },
    },
})
```

### Custom Status Bar

```lua
agent_deck.apply_to_config(config, {
    right_status = {
        enabled = true,
        components = {
            { type = 'badge', filter = 'waiting', label = 'waiting' },
            { type = 'separator', text = ' | ' },
            { type = 'badge', filter = 'working', label = 'working' },
        },
    },
})
```

### Adding Custom Agents

```lua
agent_deck.apply_to_config(config, {
    agents = {
        -- Built-in agents are auto-included, add your own:
        my_agent = {
            patterns = { 'my%-agent', 'myagent' },
            status_patterns = {
                working = { 'processing', 'thinking' },
                waiting = { 'enter input', 'y/n' },
                idle = { '^>%s*$' },
            },
        },
    },
})
```

## Status Model

| Status | Icon | Color | Description |
|--------|------|-------|-------------|
| **working** | `●` | Green | Agent is actively processing |
| **waiting** | `◐` | Yellow | User input needed |
| **idle** | `○` | Blue | Ready for input |
| **inactive** | `○` | Gray | No agent detected |

## Components

Components are the building blocks for customizing the display:

| Component | Purpose | Options |
|-----------|---------|---------|
| `icon` | Status indicator | - |
| `label` | Text display | `format`, `max_width` |
| `badge` | Count badge | `filter` (working/waiting/idle/all), `label` |
| `separator` | Visual separator | `text`, `fg`, `bg` |
| `agent_name` | Agent type display | `short` (boolean) |

### Label Format Placeholders

- `{status}` - Current status name
- `{agent_type}` - Agent type (opencode, claude, etc.)
- `{agent_name}` - Same as agent_type

Example:
```lua
{ type = 'label', format = '{agent_type}: {status}' }
```

## Events

The plugin emits events for extensibility:

```lua
-- Status changed
wezterm.on('agent_deck.status_changed', function(window, pane, old_status, new_status, agent_type)
    wezterm.log_info('Agent status changed: ' .. old_status .. ' -> ' .. new_status)
end)

-- Agent detected
wezterm.on('agent_deck.agent_detected', function(window, pane, agent_type)
    wezterm.log_info('Agent detected: ' .. agent_type)
end)

-- Agent finished
wezterm.on('agent_deck.agent_finished', function(window, pane, agent_type)
    wezterm.log_info('Agent finished: ' .. agent_type)
end)

-- Attention needed
wezterm.on('agent_deck.attention_needed', function(window, pane, agent_type, reason)
    wezterm.log_info('Agent needs attention: ' .. reason)
end)
```

## Supported Agents

Out of the box, the plugin supports:

- **OpenCode** (`opencode`)
- **Claude Code** (`claude`, `claude-code`)
- **Gemini** (`gemini`)
- **Codex** (`codex`)
- **Aider** (`aider`)

## Advanced Usage

### Programmatic Access

```lua
local agent_deck = wezterm.plugin.require('https://github.com/yourusername/wezterm-agent-deck')

-- Get state for a specific pane
local state = agent_deck.get_agent_state(pane_id)
-- Returns: { agent_type = "opencode", status = "working", ... }

-- Get all agent states
local all_states = agent_deck.get_all_agent_states()

-- Count agents by status
local counts = agent_deck.count_agents_by_status()
-- Returns: { working = 2, waiting = 1, idle = 0, inactive = 0 }
```

## Troubleshooting

### Agent not detected

1. Make sure the agent process name matches configured patterns
2. Check if the agent is the foreground process (not a child of tmux, etc.)
3. Try adding custom patterns:
   ```lua
   agents = {
       my_agent = { patterns = { 'custom%-pattern' } }
   }
   ```

### Status incorrect

1. Increase `max_lines` if output is truncated:
   ```lua
   max_lines = 200
   ```
2. Add custom status patterns for your agent
3. Increase `cooldown_ms` if status flickers

### Notifications not showing

1. Ensure `notifications.enabled = true`
2. Check `notifications.on_waiting = true`
3. Notifications are rate-limited (10s minimum between notifications per pane)

## Development

### Local Development

1. Clone the repository
2. Reference via file URL:
   ```lua
   local agent_deck = wezterm.plugin.require('file:///path/to/wezterm-agent-deck')
   ```
3. Update plugin after changes:
   ```lua
   -- In Debug Overlay (Ctrl+Shift+L):
   wezterm.plugin.update_all()
   ```

### Debug Logging

The plugin logs to WezTerm's debug console (Ctrl+Shift+L):
- Info: `[agent-deck] Plugin initialized`
- Warnings: `[agent-deck] Invalid configuration...`
- Errors: `[agent-deck] Error rendering component...`

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Acknowledgments

- Inspired by [agent-deck.nvim](https://github.com/roobert/agent-deck.nvim) and [code-squad](https://github.com/shanehull/code-squad.nvim)
- Built for the [WezTerm](https://wezfurlong.org/wezterm/) terminal emulator
