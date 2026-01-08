# WezTerm Agent Deck Plugin Implementation Plan

## Overview

WezTerm Agent Deck is a plugin for WezTerm that monitors and displays the status of AI coding agents (OpenCode, Claude, etc.) running in terminal panes. It provides real-time status indicators in tab titles and the status bar, with notification support for when agents need user attention.

## Core Requirements

1. **Monitor agent status** from multiple OpenCode processes running in terminal panes
2. **Display status indicators** in the tab bar with composable/configurable display options
3. **Provide notifications** when agents need attention (permission prompts, questions)
4. **Extensible design** to support additional AI agents beyond OpenCode

## Research Foundation

Two research documents inform this implementation:

- **`research/001-code-squad-agent-deck.md`** - Analyzed agent-deck and code-squad tools to understand:
  - Agent status detection patterns
  - 4-state status model (working, waiting, idle, inactive)
  - UI/UX patterns for agent monitoring
  
- **`research/002-wezterm-plugin.md`** - WezTerm plugin development research covering:
  - Plugin API and event system
  - Pane inspection capabilities
  - Configuration patterns
  - Display integration points

### Key WezTerm APIs

- `pane:get_lines_as_text([nlines])` - Get terminal text as string for status pattern detection
- `pane:get_logical_lines_as_text([nlines])` - Get unwrapped logical lines (better for pattern matching)
- `pane:get_foreground_process_name()` - Get executable path for agent detection
- `pane:get_foreground_process_info()` - Get full process info (pid, argv, executable, cwd, children)
- `pane:get_dimensions()` - Get pane dimensions including `scrollback_rows`

## Architecture

```
wezterm-agent-deck/
├── plugin/
│   ├── init.lua              # Entry point, setup(), apply_to_config()
│   ├── config.lua            # Configuration management & defaults
│   ├── detector.lua          # Agent detection via process info
│   ├── status.lua            # Status detection via pane text patterns
│   ├── components/
│   │   ├── init.lua          # Component registry
│   │   ├── icon.lua          # Status icon (●/◐/○)
│   │   ├── label.lua         # Text label
│   │   ├── badge.lua         # Count badge
│   │   └── separator.lua     # Visual separator
│   ├── renderer.lua          # Composable format string rendering
│   └── notifications.lua     # Toast notification manager
├── .luarc.json              # Lua language server config
├── .stylua.toml             # Lua formatter config
├── README.md                # Usage documentation
└── plans/
    └── 001-wezterm-agent-deck.md  # This document
```

## Design Decisions

1. **Status Source**: Parse pane text output to detect agent status patterns
2. **Agent Scope**: Focus on OpenCode initially, extensible architecture for other agents
3. **Detection Method**: Process-based detection via `pane:get_foreground_process_info()` - more reliable than output pattern matching alone
4. **Polling Interval**: Default 5 seconds (configurable via `status_update_interval`)
5. **Display Focus**: Pane/tab-focused status indicators, with optional aggregate view in status bar
6. **Component System**: Composable components that users can arrange (icon, label, badge, separator)

## Status Model

Based on agent-deck/code-squad research, we'll implement a 4-state model:

| Status | Color | Description | Detection Patterns |
|--------|-------|-------------|-------------------|
| **working** | Green | Agent actively processing | "Esc to interrupt", spinner chars (⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏), thinking words |
| **waiting** | Yellow | User input needed | "Esc to cancel", "Yes, allow once", "(Y/n)", permission prompts |
| **idle** | Blue | Ready for input | Empty ">" prompt at end of output |
| **inactive** | Gray | No agent detected | No matching process found |

### Anti-Flicker Logic
- 2-second cooldown before transitioning from working to idle
- Prevents rapid status changes during brief pauses

## Configuration API

```lua
local wezterm = require 'wezterm'
local agent_deck = wezterm.plugin.require('https://github.com/user/wezterm-agent-deck')

agent_deck.setup({
  -- Polling interval (ms) - default 5 seconds
  update_interval = 5000,
  
  -- Agent detection via process name matching
  agents = {
    opencode = { 
      patterns = { 'opencode' },
      -- Optional: override status detection patterns
      status_patterns = {
        working = { "Esc to interrupt", "[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]" },
        waiting = { "Esc to cancel", "Yes, allow once", "%(Y/n%)" },
        idle = { "^%s*>%s*$" }
      }
    },
    claude = { patterns = { 'claude', 'claude%-code' } },
    -- Extensible for other agents
  },
  
  -- Tab title format (composable)
  tab_title = {
    enabled = true,
    position = "left",  -- "left" or "right" of existing title
    components = {
      { type = "icon" },
      { type = "separator", text = " " },
    },
  },
  
  -- Right status (aggregate view)
  right_status = {
    enabled = true,
    components = {
      { type = "badge", filter = "waiting", label = "waiting" },
      { type = "separator", text = " | " },
      { type = "badge", filter = "working", label = "working" },
    },
  },
  
  -- Colors (auto-derived from theme if not specified)
  colors = {
    working = "green",
    waiting = "yellow", 
    idle = "blue",
    inactive = "gray",
  },
  
  -- Notifications
  notifications = {
    enabled = true,
    on_waiting = true,  -- Notify when agent needs input
    timeout_ms = 4000,
  },
  
  -- Advanced options
  cooldown_ms = 2000,  -- Anti-flicker delay
  max_lines = 100,     -- Max lines to scan for patterns
})

-- Apply to WezTerm config
agent_deck.apply_to_config(config)
```

## Component System

Components are the building blocks for status displays:

| Component | Purpose | Options |
|-----------|---------|---------|
| `icon` | Status indicator (●◐○) | `pane`, `style` (nerd/unicode/emoji) |
| `label` | Text display | `format`, `pane`, `max_width` |
| `badge` | Count badge | `filter` (working/waiting/idle/all), `label` |
| `separator` | Visual separator | `text`, `fg`, `bg` |
| `agent_name` | Agent type display | `pane`, `short` (true/false) |

### Component Examples

```lua
-- Icon with different styles
{ type = "icon", style = "nerd" }     -- Nerd font icons
{ type = "icon", style = "unicode" }  -- Unicode symbols (●◐○)
{ type = "icon", style = "emoji" }    -- Emoji (🟢🟡🔵⚫)

-- Badge with filters
{ type = "badge", filter = "waiting", label = "!" }
{ type = "badge", filter = "all" }  -- Shows total agent count

-- Custom label
{ type = "label", format = "Agent: {agent_name} ({status})" }
```

## Event System

The plugin will emit events for extensibility:

- `agent_deck.status_changed` - Fired when an agent's status changes
  - Parameters: `(window, pane, old_status, new_status, agent_type)`
- `agent_deck.agent_detected` - Fired when a new agent is detected
  - Parameters: `(window, pane, agent_type)`
- `agent_deck.agent_finished` - Fired when an agent process terminates
  - Parameters: `(window, pane, agent_type)`
- `agent_deck.attention_needed` - Fired when agent enters waiting state
  - Parameters: `(window, pane, agent_type, reason)`

## Implementation Phases

### Phase 1: Core Infrastructure (Days 1-2)
- [ ] Create plugin structure and build system
- [ ] Implement `init.lua` with setup() and apply_to_config()
- [ ] Create `config.lua` with defaults and validation
- [ ] Set up package.path for internal requires
- [ ] Add .luarc.json and .stylua.toml

### Phase 2: Agent Detection (Days 3-4)
- [ ] Implement `detector.lua` with process-based detection
- [ ] Use `pane:get_foreground_process_info()` to identify agents
- [ ] Create agent registry with pattern matching
- [ ] Add caching layer with TTL to reduce API calls
- [ ] Handle cross-platform executable path differences

### Phase 3: Status Detection (Days 5-6)
- [ ] Implement `status.lua` with pattern matching engine
- [ ] Strip ANSI codes before pattern matching
- [ ] Add cooldown logic for anti-flicker
- [ ] Support custom pattern overrides per agent
- [ ] Optimize scanning (limit to last N lines)

### Phase 4: Display Components (Days 7-8)
- [ ] Create component registry in `components/init.lua`
- [ ] Implement core components (icon, label, badge, separator)
- [ ] Add `renderer.lua` for composable rendering
- [ ] Support multiple icon styles (nerd/unicode/emoji)
- [ ] Theme-aware color selection

### Phase 5: Tab Integration (Days 9-10)
- [ ] Hook into `format-tab-title` event
- [ ] Render components based on configuration
- [ ] Support left/right positioning
- [ ] Preserve existing tab title content
- [ ] Handle active/inactive tab styling

### Phase 6: Status Bar Integration (Days 11-12)
- [ ] Hook into `update-status` event
- [ ] Implement aggregate view logic
- [ ] Support filtering (show only waiting agents)
- [ ] Add click handlers for navigation
- [ ] Optimize for minimal status bar space

### Phase 7: Notifications (Days 13-14)
- [ ] Implement `notifications.lua`
- [ ] Use `window:toast_notification()` API
- [ ] Add notification queue management
- [ ] Support custom notification messages
- [ ] Rate limiting to prevent spam

### Phase 8: Polish & Documentation (Days 15-16)
- [ ] Auto-detect colors from active color scheme
- [ ] Write comprehensive README with examples
- [ ] Add example configurations
- [ ] Create troubleshooting guide
- [ ] Performance profiling and optimization

## Technical Considerations

### Performance
- Use `status_update_interval` to control polling frequency
- Cache process detection results with appropriate TTL
- Limit text scanning to recent output (configurable max_lines)
- Batch updates to reduce event overhead

### Cross-Platform Support
- Handle Windows/Unix path separators in process detection
- Test on macOS, Linux, and Windows
- Account for different terminal emulator behaviors

### Limitations
- Only works for local panes (not SSH or multiplexer sessions)
- Requires agents to output recognizable patterns
- Pattern matching may have false positives/negatives

### Error Handling
- Graceful degradation if APIs unavailable
- Clear error messages in logs
- Fallback to inactive status on errors

## Success Metrics

1. **Reliability**: Accurate status detection with <1% false positives
2. **Performance**: <50ms update latency, <1% CPU usage
3. **Usability**: Zero-config experience for common agents
4. **Extensibility**: Easy to add new agents and components

## Future Enhancements

1. **Agent Communication**: Direct API integration with agents
2. **History Tracking**: Log of agent activities and durations
3. **Multi-Window Support**: Global agent overview across windows
4. **Custom Actions**: Keyboard shortcuts for agent control
5. **Statistics**: Time tracking and productivity metrics

## References

- [WezTerm Plugin API Documentation](https://wezfurlong.org/wezterm/config/lua/plugin/index.html)
- [Agent-Deck GitHub Repository](https://github.com/roobert/agent-deck.nvim)
- [Code-Squad GitHub Repository](https://github.com/shanehull/code-squad.nvim)
- [WezTerm Configuration Examples](https://github.com/wez/wezterm/tree/main/docs/examples)
