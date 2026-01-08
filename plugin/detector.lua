-- Agent detection module for WezTerm Agent Deck
-- Detects AI coding agents running in terminal panes via process information
local wezterm = require('wezterm')

local M = {}

-- Cache for agent detection results
-- Structure: { pane_id -> { agent_type, timestamp } }
local detection_cache = {}
local CACHE_TTL_MS = 5000  -- Cache results for 5 seconds

--- Check if a string matches any pattern in a list
---@param str string String to check
---@param patterns table List of patterns (Lua patterns)
---@return boolean True if any pattern matches
local function matches_any_pattern(str, patterns)
    if not str or not patterns then
        return false
    end
    
    local str_lower = str:lower()
    
    for _, pattern in ipairs(patterns) do
        if str_lower:find(pattern:lower()) then
            return true
        end
    end
    
    return false
end

--- Extract executable name from full path
---@param path string Full executable path
---@return string Executable name
local function get_executable_name(path)
    if not path then
        return ''
    end
    
    -- Handle both Unix and Windows paths
    local name = path:match('[/\\]([^/\\]+)$') or path
    
    -- Remove common extensions
    name = name:gsub('%.exe$', '')
    
    return name
end

--- Check if cache entry is still valid
---@param entry table Cache entry with timestamp
---@return boolean True if still valid
local function is_cache_valid(entry)
    if not entry then
        return false
    end
    
    local now = os.time() * 1000
    return (now - entry.timestamp) < CACHE_TTL_MS
end

--- Detect agent type from process information
---@param pane userdata WezTerm pane object
---@param config table Plugin configuration
---@return string|nil Agent type name or nil if no agent detected
function M.detect_agent(pane, config)
    local pane_id = pane:pane_id()
    
    -- Check cache first
    local cached = detection_cache[pane_id]
    if is_cache_valid(cached) then
        return cached.agent_type
    end
    
    local agent_type = nil
    
    -- Try to get process info (more reliable)
    local success, process_info = pcall(function()
        return pane:get_foreground_process_info()
    end)
    
    if success and process_info then
        -- Check executable path/name
        local executable = process_info.executable or ''
        local exe_name = get_executable_name(executable)
        
        -- Check argv for agent names (useful when running via npx, bunx, etc.)
        local argv = process_info.argv or {}
        local argv_str = table.concat(argv, ' ')
        
        -- Check each configured agent
        for agent_name, agent_config in pairs(config.agents) do
            local patterns = agent_config.patterns or { agent_name }
            
            -- Check executable name
            if matches_any_pattern(exe_name, patterns) then
                agent_type = agent_name
                break
            end
            
            -- Check full argv string (catches npx claude, bunx opencode, etc.)
            if matches_any_pattern(argv_str, patterns) then
                agent_type = agent_name
                break
            end
        end
        
        -- Check children processes too (agent might be a child of shell)
        if not agent_type and process_info.children then
            for _, child in ipairs(process_info.children) do
                local child_exe = get_executable_name(child.executable or '')
                local child_argv = table.concat(child.argv or {}, ' ')
                
                for agent_name, agent_config in pairs(config.agents) do
                    local patterns = agent_config.patterns or { agent_name }
                    
                    if matches_any_pattern(child_exe, patterns) or
                       matches_any_pattern(child_argv, patterns) then
                        agent_type = agent_name
                        break
                    end
                end
                
                if agent_type then
                    break
                end
            end
        end
    end
    
    -- Fallback: try get_foreground_process_name (simpler but less info)
    if not agent_type then
        local name_success, process_name = pcall(function()
            return pane:get_foreground_process_name()
        end)
        
        if name_success and process_name then
            local exe_name = get_executable_name(process_name)
            
            for agent_name, agent_config in pairs(config.agents) do
                local patterns = agent_config.patterns or { agent_name }
                
                if matches_any_pattern(exe_name, patterns) then
                    agent_type = agent_name
                    break
                end
            end
        end
    end
    
    -- Update cache
    detection_cache[pane_id] = {
        agent_type = agent_type,
        timestamp = os.time() * 1000,
    }
    
    return agent_type
end

--- Clear detection cache for a pane
---@param pane_id number Pane ID
function M.clear_cache(pane_id)
    if pane_id then
        detection_cache[pane_id] = nil
    else
        detection_cache = {}
    end
end

--- Get all detected agents (from cache)
---@return table<number, string> Map of pane_id -> agent_type
function M.get_cached_agents()
    local result = {}
    local now = os.time() * 1000
    
    for pane_id, entry in pairs(detection_cache) do
        if (now - entry.timestamp) < CACHE_TTL_MS and entry.agent_type then
            result[pane_id] = entry.agent_type
        end
    end
    
    return result
end

return M
