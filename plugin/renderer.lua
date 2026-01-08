-- Renderer module for WezTerm Agent Deck
-- Renders composable components for tab titles and status bar
local wezterm = require('wezterm')

local M = {}

-- Lazy load components to avoid circular dependencies
local components = nil
local function get_components()
    if not components then
        components = require('components')
    end
    return components
end

--- Get default tab title
---@param tab table Tab object
---@return string Default title
local function get_default_title(tab)
    local pane = tab.active_pane
    
    -- Try to get a meaningful title
    local title = pane.title or ''
    
    if title == '' then
        -- Try process name
        local process_name = pane.foreground_process_name or ''
        if process_name ~= '' then
            -- Extract just the executable name
            title = process_name:match('[/\\]([^/\\]+)$') or process_name
        end
    end
    
    if title == '' then
        title = 'Terminal'
    end
    
    return title
end

--- Render tab title with agent status
---@param agent_state table|nil Agent state { agent_type, status, ... }
---@param tab table WezTerm tab object
---@param tab_config table Tab title configuration
---@param colors table Color configuration
---@return table FormatItem array for wezterm.format()
function M.render_tab_title(agent_state, tab, tab_config, colors)
    local comps = get_components()
    local config_module = require('config')
    local config = config_module.get()
    
    -- Build context for component rendering
    local context = {
        status = agent_state and agent_state.status or 'inactive',
        agent_type = agent_state and agent_state.agent_type or nil,
        tab = tab,
        config = config,
    }
    
    -- Get the default title
    local default_title = get_default_title(tab)
    
    -- If no agent, just return the title
    if not agent_state then
        return {
            { Text = ' ' .. default_title .. ' ' },
        }
    end
    
    -- Render components
    local component_items = comps.render_all(tab_config.components or {}, context)
    
    -- Build result based on position
    local result = {}
    
    -- Add padding
    table.insert(result, { Text = ' ' })
    
    if tab_config.position == 'left' then
        -- Add components first
        for _, item in ipairs(component_items) do
            table.insert(result, item)
        end
        -- Then title
        table.insert(result, { Text = default_title })
    else
        -- Title first
        table.insert(result, { Text = default_title })
        -- Then components
        for _, item in ipairs(component_items) do
            table.insert(result, item)
        end
    end
    
    -- Add padding
    table.insert(result, { Text = ' ' })
    
    return result
end

--- Render right status bar with agent counts
---@param counts table<string, number> Status counts { working = n, waiting = n, ... }
---@param status_config table Right status configuration
---@param colors table Color configuration
---@return table FormatItem array for wezterm.format()
function M.render_right_status(counts, status_config, colors)
    local comps = get_components()
    local config_module = require('config')
    local config = config_module.get()
    
    -- Check if there are any agents
    local total = 0
    for _, count in pairs(counts) do
        total = total + count
    end
    
    if total == 0 then
        return {}
    end
    
    -- Build context
    local context = {
        counts = counts,
        config = config,
    }
    
    -- Render components
    local result = comps.render_all(status_config.components or {}, context)
    
    -- Filter out empty separators (when adjacent badges are 0)
    local filtered = {}
    local last_was_text = false
    
    for i, item in ipairs(result) do
        local is_separator = false
        local is_empty = false
        
        -- Check if this is a separator (contains ' | ' or similar)
        if item.Text then
            local text = item.Text
            -- Check if it's only whitespace/separators
            if text:match('^[%s|%-]+$') then
                is_separator = true
            end
            -- Check if previous badge rendered nothing
            is_empty = text == ''
        end
        
        if not is_empty then
            if is_separator and not last_was_text then
                -- Skip separator if nothing before it
            else
                table.insert(filtered, item)
                last_was_text = item.Text and not item.Text:match('^[%s|%-]+$')
            end
        end
    end
    
    -- Remove trailing separators
    while #filtered > 0 do
        local last = filtered[#filtered]
        if last.Text and last.Text:match('^[%s|%-]+$') then
            table.remove(filtered)
        else
            break
        end
    end
    
    -- Add padding
    if #filtered > 0 then
        table.insert(filtered, 1, { Text = ' ' })
        table.insert(filtered, { Text = ' ' })
    end
    
    return filtered
end

--- Create a simple status string
---@param status string Status name
---@param agent_type string|nil Agent type
---@param config table|nil Configuration
---@return string Simple status string
function M.simple_status(status, agent_type, config)
    local config_module = require('config')
    config = config or config_module.get()
    
    local icon = config_module.get_status_icon(status, config)
    
    if agent_type then
        return icon .. ' ' .. agent_type
    else
        return icon
    end
end

--- Create a formatted status with color
---@param status string Status name
---@param agent_type string|nil Agent type
---@param config table|nil Configuration
---@return table FormatItem array
function M.formatted_status(status, agent_type, config)
    local config_module = require('config')
    config = config or config_module.get()
    
    local icon = config_module.get_status_icon(status, config)
    local color = config_module.get_status_color(status, config)
    
    local text = icon
    if agent_type then
        text = text .. ' ' .. agent_type
    end
    
    return {
        { Foreground = { Color = color } },
        { Text = text },
        { Attribute = { Intensity = 'Normal' } },
    }
end

return M
