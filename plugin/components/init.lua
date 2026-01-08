-- Component registry for WezTerm Agent Deck
-- Manages composable display components
local wezterm = require('wezterm')

local M = {}

-- Component registry
local components = {}

--- Register a component
---@param name string Component name
---@param render_fn function Render function(context, opts) -> FormatItem[]
function M.register(name, render_fn)
    components[name] = render_fn
end

--- Get a component by name
---@param name string Component name
---@return function|nil Render function
function M.get(name)
    return components[name]
end

--- Render a component
---@param name string Component type
---@param context table Rendering context
---@param opts table Component options
---@return table FormatItem array
function M.render(name, context, opts)
    local render_fn = components[name]
    
    if not render_fn then
        wezterm.log_warn('[agent-deck] Unknown component type: ' .. tostring(name))
        return {}
    end
    
    local success, result = pcall(render_fn, context, opts or {})
    
    if not success then
        wezterm.log_error('[agent-deck] Error rendering component ' .. name .. ': ' .. tostring(result))
        return {}
    end
    
    return result or {}
end

--- Render multiple components
---@param component_list table List of component configs { type, ... }
---@param context table Rendering context
---@return table FormatItem array
function M.render_all(component_list, context)
    local result = {}
    
    for _, component_config in ipairs(component_list) do
        local component_type = component_config.type
        local items = M.render(component_type, context, component_config)
        
        for _, item in ipairs(items) do
            table.insert(result, item)
        end
    end
    
    return result
end

--- Get list of registered component names
---@return table List of component names
function M.list()
    local names = {}
    for name, _ in pairs(components) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

-- Load built-in components
local function load_builtin_components()
    -- Icon component
    M.register('icon', function(context, opts)
        local config_module = require('config')
        local config = context.config or config_module.get()
        local status = context.status or 'inactive'
        
        local icon = config_module.get_status_icon(status, config)
        local color = config_module.get_status_color(status, config)
        
        return {
            { Foreground = { Color = color } },
            { Text = icon },
            { Attribute = { Intensity = 'Normal' } },
        }
    end)
    
    -- Separator component
    M.register('separator', function(context, opts)
        local text = opts.text or ' '
        local fg = opts.fg
        local bg = opts.bg
        
        local result = {}
        
        if fg then
            table.insert(result, { Foreground = { Color = fg } })
        end
        if bg then
            table.insert(result, { Background = { Color = bg } })
        end
        
        table.insert(result, { Text = text })
        
        -- Reset
        table.insert(result, { Attribute = { Intensity = 'Normal' } })
        
        return result
    end)
    
    -- Label component
    M.register('label', function(context, opts)
        local format = opts.format or '{status}'
        local max_width = opts.max_width
        
        -- Replace placeholders
        local text = format
        text = text:gsub('{status}', context.status or 'inactive')
        text = text:gsub('{agent_type}', context.agent_type or 'unknown')
        text = text:gsub('{agent_name}', context.agent_type or 'unknown')
        
        -- Truncate if needed
        if max_width and #text > max_width then
            text = text:sub(1, max_width - 1) .. ''
        end
        
        local config_module = require('config')
        local config = context.config or config_module.get()
        local color = config_module.get_status_color(context.status or 'inactive', config)
        
        return {
            { Foreground = { Color = color } },
            { Text = text },
            { Attribute = { Intensity = 'Normal' } },
        }
    end)
    
    -- Badge component (shows count)
    M.register('badge', function(context, opts)
        local filter = opts.filter or 'all'
        local label = opts.label
        local counts = context.counts or {}
        
        local count = 0
        
        if filter == 'all' then
            for _, c in pairs(counts) do
                count = count + c
            end
        else
            count = counts[filter] or 0
        end
        
        -- Don't show badge if count is 0
        if count == 0 then
            return {}
        end
        
        local config_module = require('config')
        local config = context.config or config_module.get()
        local color = config_module.get_status_color(filter ~= 'all' and filter or 'working', config)
        
        local text = tostring(count)
        if label then
            text = text .. ' ' .. label
        end
        
        return {
            { Foreground = { Color = color } },
            { Text = text },
            { Attribute = { Intensity = 'Normal' } },
        }
    end)
    
    -- Agent name component
    M.register('agent_name', function(context, opts)
        local agent_type = context.agent_type or 'unknown'
        local short = opts.short
        
        local text = agent_type
        if short then
            -- First letter uppercase
            text = agent_type:sub(1, 1):upper()
        end
        
        local config_module = require('config')
        local config = context.config or config_module.get()
        local color = config_module.get_status_color(context.status or 'inactive', config)
        
        return {
            { Foreground = { Color = color } },
            { Text = text },
            { Attribute = { Intensity = 'Normal' } },
        }
    end)
end

-- Initialize built-in components
load_builtin_components()

return M
