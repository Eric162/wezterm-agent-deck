-- Configuration management for WezTerm Agent Deck
local wezterm = require('wezterm')

local M = {}

-- Default configuration
local default_config = {
    -- Polling interval (ms) - default 5 seconds
    update_interval = 5000,
    
    -- Agent detection via process name matching
    agents = {
        opencode = {
            patterns = { 'opencode' },
            status_patterns = nil,  -- Use defaults
        },
        claude = {
            patterns = { 'claude', 'claude%-code' },
            status_patterns = nil,
        },
        gemini = {
            patterns = { 'gemini' },
            status_patterns = nil,
        },
        codex = {
            patterns = { 'codex' },
            status_patterns = nil,
        },
        aider = {
            patterns = { 'aider' },
            status_patterns = nil,
        },
    },
    
    -- Tab title format (composable)
    tab_title = {
        enabled = true,
        position = 'left',  -- 'left' or 'right' of existing title
        components = {
            { type = 'icon' },
            { type = 'separator', text = ' ' },
        },
    },
    
    -- Right status (aggregate view)
    right_status = {
        enabled = true,
        components = {
            { type = 'badge', filter = 'waiting', label = 'waiting' },
            { type = 'separator', text = ' | ' },
            { type = 'badge', filter = 'working', label = 'working' },
        },
    },
    
    -- Colors (can be color names or hex)
    colors = {
        working = 'green',
        waiting = 'yellow',
        idle = 'blue',
        inactive = 'gray',
    },
    
    -- Icon styles
    icons = {
        style = 'unicode',  -- 'unicode', 'nerd', or 'emoji'
        unicode = {
            working = '●',
            waiting = '◔',
            idle = '○',
            inactive = '◌',
        },
        nerd = {
            working = '',  -- nf-fa-circle
            waiting = '',  -- nf-fa-adjust
            idle = '',  -- nf-fa-circle_o
            inactive = '',  -- nf-cod-circle_outline
        },
        emoji = {
            working = '🟢',
            waiting = '🟡',
            idle = '🔵',
            inactive = '⚪',
        },
    },
    
    -- Notifications
    notifications = {
        enabled = true,
        on_waiting = true,  -- Notify when agent needs input
        timeout_ms = 4000,
    },
    
    -- Advanced options
    cooldown_ms = 2000,  -- Anti-flicker delay before transitioning from working to idle
    max_lines = 100,     -- Max lines to scan for patterns
}

-- Current configuration (merged with user options)
local current_config = nil

--- Deep merge two tables
---@param t1 table Base table
---@param t2 table Table to merge into base
---@return table Merged table
local function deep_merge(t1, t2)
    local result = {}
    
    -- Copy all from t1
    for k, v in pairs(t1) do
        if type(v) == 'table' and type(t2[k]) == 'table' then
            result[k] = deep_merge(v, t2[k])
        elseif t2[k] ~= nil then
            result[k] = t2[k]
        else
            result[k] = v
        end
    end
    
    -- Add any keys from t2 not in t1
    for k, v in pairs(t2) do
        if result[k] == nil then
            result[k] = v
        end
    end
    
    return result
end

--- Deep copy a table
---@param t table Table to copy
---@return table Copied table
local function deep_copy(t)
    if type(t) ~= 'table' then
        return t
    end
    
    local result = {}
    for k, v in pairs(t) do
        result[k] = deep_copy(v)
    end
    return result
end

--- Set configuration with user options
---@param opts table|nil User configuration options
function M.set(opts)
    if not opts then
        current_config = deep_copy(default_config)
        return
    end
    
    current_config = deep_merge(default_config, opts)
    
    -- Validate configuration
    M.validate(current_config)
end

--- Get current configuration
---@return table Current configuration
function M.get()
    if not current_config then
        current_config = deep_copy(default_config)
    end
    return current_config
end

--- Get default configuration
---@return table Default configuration
function M.get_defaults()
    return deep_copy(default_config)
end

--- Validate configuration
---@param config table Configuration to validate
function M.validate(config)
    -- Validate update_interval
    if type(config.update_interval) ~= 'number' or config.update_interval < 100 then
        wezterm.log_warn('[agent-deck] update_interval should be >= 100ms, using default')
        config.update_interval = default_config.update_interval
    end
    
    -- Validate cooldown_ms
    if type(config.cooldown_ms) ~= 'number' or config.cooldown_ms < 0 then
        wezterm.log_warn('[agent-deck] cooldown_ms should be >= 0ms, using default')
        config.cooldown_ms = default_config.cooldown_ms
    end
    
    -- Validate max_lines
    if type(config.max_lines) ~= 'number' or config.max_lines < 10 then
        wezterm.log_warn('[agent-deck] max_lines should be >= 10, using default')
        config.max_lines = default_config.max_lines
    end
    
    -- Validate icon style
    local valid_styles = { unicode = true, nerd = true, emoji = true }
    if not valid_styles[config.icons.style] then
        wezterm.log_warn('[agent-deck] Invalid icon style, using unicode')
        config.icons.style = 'unicode'
    end
    
    -- Validate tab_title position
    if config.tab_title.position ~= 'left' and config.tab_title.position ~= 'right' then
        wezterm.log_warn('[agent-deck] tab_title.position should be "left" or "right", using "left"')
        config.tab_title.position = 'left'
    end
end

--- Get color for a status
---@param status string Status name (working, waiting, idle, inactive)
---@param config table|nil Configuration (uses current if nil)
---@return string Color value
function M.get_status_color(status, config)
    config = config or M.get()
    return config.colors[status] or config.colors.inactive
end

--- Get icon for a status
---@param status string Status name (working, waiting, idle, inactive)
---@param config table|nil Configuration (uses current if nil)
---@return string Icon character
function M.get_status_icon(status, config)
    config = config or M.get()
    local style = config.icons.style
    local icons = config.icons[style]
    
    if not icons then
        icons = config.icons.unicode
    end
    
    return icons[status] or icons.inactive
end

return M
