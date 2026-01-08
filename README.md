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
