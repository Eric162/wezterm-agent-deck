-- Status detection module for WezTerm Agent Deck
-- Detects agent status from terminal pane text content via pattern matching
local wezterm = require('wezterm')

local M = {}

-- Default status patterns (used if agent doesn't override)
local default_patterns = {
    -- Working patterns - agent is actively processing
    working = {
        'esc to interrupt',
        'esc interrupt',
        'thinking',
        'pondering',
        'processing',
        'analyzing',
        'generating',
        'writing',
        'reading',
        'searching',
        'delegating work',
        'planning next steps',
        'gathering context',
        'searching the codebase',
        'searching the web',
        'making edits',
        'running commands',
        'gathering thoughts',
        'considering next steps',
        '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏',
        '█', '■', '▮', '▪', '▰',
    },
    
    -- Waiting patterns - agent needs user input (higher priority than working)
    waiting = {
        'esc to cancel',
        'yes, allow once',
        'yes, allow always',
        'no, and tell',
        'do you trust',
        'run this command',
        'execute this',
        'continue%?',
        'proceed%?',
        '%(y/n%)',
        '%(Y/n%)',
        '%[y/n%]',
        '%[Y/n%]',
        '%(y/N%)',
        '%(Y/N%)',
        '%[y/N%]',
        '%[Y/N%]',
        'approve this plan',
        'do you want to proceed',
        'press enter to continue',
        -- Menu selection indicators
        '' .. ' Yes',  -- Nerd font arrow
        '' .. ' No',
    },
    
    -- Idle patterns - agent is ready for input
    idle = {
        '^>%s*$',       -- Empty > prompt
        '^> $',         -- > prompt with space
        '^>$',          -- Just > at end of line
    },
}

-- ANSI escape code pattern
local ANSI_PATTERN = '\27%[%d*;?%d*;?%d*[A-Za-z]'
local OSC_PATTERN = '\27%].-\007'  -- OSC sequences ending in BEL
local OSC_ST_PATTERN = '\27%].-\27\\'  -- OSC sequences ending in ST

--- Strip ANSI escape codes from text
---@param text string Text with potential ANSI codes
---@return string Cleaned text
local function strip_ansi(text)
    if not text then
        return ''
    end
    
    -- Remove various escape sequences
    local result = text
    result = result:gsub(ANSI_PATTERN, '')
    result = result:gsub(OSC_PATTERN, '')
    result = result:gsub(OSC_ST_PATTERN, '')
    result = result:gsub('\27%[%?%d+[hl]', '')  -- Mode setting sequences
    result = result:gsub('\27%[%d*[ABCDEFGJKST]', '')  -- Cursor movement
    result = result:gsub('\27%[%d*;%d*[Hf]', '')  -- Cursor positioning
    result = result:gsub('\27%[%d*m', '')  -- SGR sequences
    result = result:gsub('\27%[[0-9;]*m', '')  -- Extended SGR
    result = result:gsub('\r', '')  -- Carriage return
    
    return result
end

--- Check if text matches any pattern in a list
---@param text string Text to check
---@param patterns table List of patterns
---@return boolean True if any pattern matches
local function matches_any(text, patterns)
    if not text or not patterns then
        return false
    end
    
    local text_lower = text:lower()
    
    for _, pattern in ipairs(patterns) do
        -- Try pattern match first
        local success, result = pcall(function()
            return text_lower:find(pattern:lower())
        end)
        
        if success and result then
            return true
        end
        
        -- Fallback to plain text search if pattern fails
        if not success then
            if text_lower:find(pattern:lower(), 1, true) then
                return true
            end
        end
    end
    
    return false
end

--- Get the last N lines from text
---@param text string Full text
---@param n number Number of lines to get
---@return string Last N lines
local function get_last_lines(text, n)
    if not text then
        return ''
    end
    
    local lines = {}
    for line in text:gmatch('[^\n]+') do
        table.insert(lines, line)
    end
    
    local start = math.max(1, #lines - n + 1)
    local result = {}
    
    for i = start, #lines do
        table.insert(result, lines[i])
    end
    
    return table.concat(result, '\n')
end

--- Get patterns for an agent (custom or default)
---@param agent_type string Agent type name
---@param config table Plugin configuration
---@return table Patterns table with working, waiting, idle keys
local function get_patterns_for_agent(agent_type, config)
    local agent_config = config.agents[agent_type]
    
    if agent_config and agent_config.status_patterns then
        -- Merge custom patterns with defaults
        return {
            working = agent_config.status_patterns.working or default_patterns.working,
            waiting = agent_config.status_patterns.waiting or default_patterns.waiting,
            idle = agent_config.status_patterns.idle or default_patterns.idle,
        }
    end
    
    return default_patterns
end

--- Detect agent status from pane content
---@param pane userdata WezTerm pane object
---@param agent_type string Agent type name
---@param config table Plugin configuration
---@return string Status: 'working', 'waiting', 'idle', or 'inactive'
function M.detect_status(pane, agent_type, config)
    if not agent_type then
        return 'inactive'
    end
    
    -- Get pane text content
    local success, text = pcall(function()
        return pane:get_lines_as_text(config.max_lines or 100)
    end)
    
    if not success or not text then
        -- Fallback: try logical lines
        success, text = pcall(function()
            return pane:get_logical_lines_as_text(config.max_lines or 100)
        end)
    end
    
    if not success or not text or text == '' then
        return 'inactive'
    end
    
    -- Strip ANSI codes
    local clean_text = strip_ansi(text)
    
    -- Get the relevant portion (last lines are most important)
    local recent_text = get_last_lines(clean_text, 30)
    
    -- Get patterns for this agent
    local patterns = get_patterns_for_agent(agent_type, config)
    
    -- Check in priority order: waiting > working > idle
    -- (waiting takes precedence because it needs user attention)
    
    if matches_any(recent_text, patterns.waiting) then
        return 'waiting'
    end
    
    if matches_any(recent_text, patterns.working) then
        return 'working'
    end
    
    -- Check for idle prompt (only in last few lines)
    local last_lines = get_last_lines(clean_text, 5)
    
    -- Check each line for idle pattern
    for line in last_lines:gmatch('[^\n]+') do
        local trimmed = line:match('^%s*(.-)%s*$') or ''
        for _, pattern in ipairs(patterns.idle) do
            local match_success, _ = pcall(function()
                return trimmed:match(pattern)
            end)
            if match_success then
                -- Actually check the result
                if trimmed:match(pattern) then
                    return 'idle'
                end
            end
        end
        
        -- Also check for simple ">" prompt
        if trimmed == '>' or trimmed == '> ' then
            return 'idle'
        end
    end
    
    return 'idle'
end

--- Get default patterns (for reference/debugging)
---@return table Default patterns
function M.get_default_patterns()
    return default_patterns
end

--- Strip ANSI codes (exported for use by other modules)
M.strip_ansi = strip_ansi

return M
