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
        -- Try Lua pattern match first, fall back to plain text if pattern is invalid
        local success, result = pcall(function()
            return str_lower:find(pattern:lower())
        end)
        if success and result then
            return true
        end
        -- Fallback to plain text search if pattern match failed
        if not success and str_lower:find(pattern:lower(), 1, true) then
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

--- Check if an agent is enabled in the configuration
---@param agent_name string Agent name to check
---@param config table Plugin configuration
---@return boolean True if agent should be checked
local function is_agent_enabled(agent_name, config)
    -- If enabled_agents is not set, all agents are enabled
    if not config.enabled_agents then
        return true
    end
    
    for _, enabled in ipairs(config.enabled_agents) do
        if enabled == agent_name then
            return true
        end
    end
    
    return false
end

--- Get patterns for a specific detection phase
--- Uses specific patterns if available, falls back to generic patterns
---@param agent_config table Agent configuration
---@param pattern_type string Type of patterns: 'executable', 'argv', 'title'
---@param agent_name string Agent name (used as ultimate fallback)
---@return table List of patterns to match
local function get_patterns_for_phase(agent_config, pattern_type, agent_name)
    local specific_key = pattern_type .. '_patterns'
    
    -- Priority 1: Specific patterns for this phase
    if agent_config[specific_key] and #agent_config[specific_key] > 0 then
        return agent_config[specific_key]
    end
    
    -- Priority 2: Generic patterns field
    if agent_config.patterns and #agent_config.patterns > 0 then
        return agent_config.patterns
    end
    
    -- Priority 3: Agent name as fallback
    return { agent_name }
end

--- Try to detect agent from executable path and argv
---@param executable string Full executable path
---@param argv_str string Joined argv string
---@param config table Plugin configuration
---@return string|nil Agent type name or nil
local function detect_from_process_info(executable, argv_str, config)
    local exe_name = get_executable_name(executable)
    
    for agent_name, agent_config in pairs(config.agents) do
        if is_agent_enabled(agent_name, config) then
            -- Check full executable path first (most specific)
            local exe_patterns = get_patterns_for_phase(agent_config, 'executable', agent_name)
            if matches_any_pattern(executable, exe_patterns) then
                return agent_name
            end
            
            -- Check executable name
            if matches_any_pattern(exe_name, exe_patterns) then
                return agent_name
            end
            
            -- Check argv string
            local argv_patterns = get_patterns_for_phase(agent_config, 'argv', agent_name)
            if matches_any_pattern(argv_str, argv_patterns) then
                return agent_name
            end
        end
    end
    
    return nil
end

--- Try to detect agent from pane title
---@param pane_title string Pane title
---@param config table Plugin configuration
---@return string|nil Agent type name or nil
local function detect_from_title(pane_title, config)
    if not pane_title or pane_title == '' then
        return nil
    end
    
    for agent_name, agent_config in pairs(config.agents) do
        if is_agent_enabled(agent_name, config) then
            local title_patterns = get_patterns_for_phase(agent_config, 'title', agent_name)
            if matches_any_pattern(pane_title, title_patterns) then
                return agent_name
            end
        end
    end
    
    return nil
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
    
    -- Phase 1: Try to get detailed process info (most reliable)
    local success, process_info = pcall(function()
        return pane:get_foreground_process_info()
    end)
    
    if success and process_info then
        local executable = process_info.executable or ''
        local name = process_info.name or ''
        local argv = process_info.argv or {}
        local argv_str = table.concat(argv, ' ')
        
        agent_type = detect_from_process_info(executable, argv_str, config)
        if not agent_type and name ~= '' then
            agent_type = detect_from_process_info(name, argv_str, config)
        end
        
        if not agent_type and process_info.children then
            for _, child in pairs(process_info.children) do
                local child_exe = child.executable or ''
                local child_name = child.name or ''
                local child_argv = table.concat(child.argv or {}, ' ')
                
                agent_type = detect_from_process_info(child_exe, child_argv, config)
                if not agent_type and child_name ~= '' then
                    agent_type = detect_from_process_info(child_name, child_argv, config)
                end
                if agent_type then
                    break
                end
            end
        end
    end
    
    -- Phase 2: Fallback to simpler process name
    if not agent_type then
        local name_success, process_name = pcall(function()
            return pane:get_foreground_process_name()
        end)
        
        if name_success and process_name then
            agent_type = detect_from_process_info(process_name, '', config)
        end
    end
    
    -- Phase 3: Fallback to pane title (for agents that set terminal title)
    if not agent_type then
        local title_success, pane_title = pcall(function()
            return pane:get_title()
        end)
        
        if title_success then
            agent_type = detect_from_title(pane_title, config)
        end
        
        -- Also try pane.title property as secondary source
        if not agent_type then
            local prop_success, prop_title = pcall(function()
                return pane.title
            end)
            
            if prop_success and prop_title ~= pane_title then
                agent_type = detect_from_title(prop_title, config)
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
