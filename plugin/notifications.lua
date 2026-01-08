-- Notifications module for WezTerm Agent Deck
-- Handles toast notifications when agents need attention
local wezterm = require('wezterm')

local M = {}

-- Rate limiting state
local last_notification = {}  -- pane_id -> timestamp
local MIN_NOTIFICATION_GAP_MS = 10000  -- Minimum 10 seconds between notifications per pane

-- Notification queue for batch processing
local notification_queue = {}
local MAX_QUEUE_SIZE = 10

--- Check if we can send a notification (rate limiting)
---@param pane_id number Pane ID
---@return boolean True if notification is allowed
local function can_notify(pane_id)
    local now = os.time() * 1000
    local last = last_notification[pane_id] or 0
    
    return (now - last) >= MIN_NOTIFICATION_GAP_MS
end

--- Record that a notification was sent
---@param pane_id number Pane ID
local function record_notification(pane_id)
    last_notification[pane_id] = os.time() * 1000
end

--- Get notification title based on agent type
---@param agent_type string Agent type
---@return string Notification title
local function get_notification_title(agent_type)
    local titles = {
        opencode = 'OpenCode',
        claude = 'Claude',
        gemini = 'Gemini',
        codex = 'Codex',
        aider = 'Aider',
    }
    
    return titles[agent_type] or (agent_type:sub(1, 1):upper() .. agent_type:sub(2))
end

--- Get notification message based on status
---@param status string Status (usually 'waiting')
---@return string Notification message
local function get_notification_message(status)
    if status == 'waiting' then
        return 'Needs your input'
    else
        return 'Status changed to ' .. status
    end
end

--- Send a toast notification
---@param window userdata|nil WezTerm window object (can be nil)
---@param title string Notification title
---@param message string Notification message
---@param timeout_ms number Timeout in milliseconds
local function send_toast(window, title, message, timeout_ms)
    if window then
        local success, err = pcall(function()
            window:toast_notification(title, message, nil, timeout_ms)
        end)
        
        if not success then
            wezterm.log_warn('[agent-deck] Failed to send notification: ' .. tostring(err))
        end
    else
        -- Queue notification if no window available
        if #notification_queue < MAX_QUEUE_SIZE then
            table.insert(notification_queue, {
                title = title,
                message = message,
                timeout_ms = timeout_ms,
                timestamp = os.time() * 1000,
            })
        end
    end
end

--- Process queued notifications
---@param window userdata WezTerm window object
function M.process_queue(window)
    if not window or #notification_queue == 0 then
        return
    end
    
    local now = os.time() * 1000
    local processed = {}
    
    for i, notification in ipairs(notification_queue) do
        -- Skip old notifications (older than 30 seconds)
        if (now - notification.timestamp) < 30000 then
            send_toast(window, notification.title, notification.message, notification.timeout_ms)
        end
        table.insert(processed, i)
    end
    
    -- Remove processed notifications (in reverse order to maintain indices)
    for i = #processed, 1, -1 do
        table.remove(notification_queue, processed[i])
    end
end

--- Notify that an agent is waiting for input
---@param pane userdata WezTerm pane object
---@param agent_type string Agent type
---@param config table Plugin configuration
function M.notify_waiting(pane, agent_type, config)
    if not config.notifications.enabled or not config.notifications.on_waiting then
        return
    end
    
    local pane_id = pane:pane_id()
    
    -- Check rate limiting
    if not can_notify(pane_id) then
        return
    end
    
    -- Get window for toast
    local window = nil
    local success, err = pcall(function()
        local tab = pane:tab()
        if tab then
            window = tab:window()
        end
    end)
    
    if not success then
        wezterm.log_warn('[agent-deck] Could not get window for notification: ' .. tostring(err))
    end
    
    -- Build notification
    local title = get_notification_title(agent_type) .. ' - Attention Needed'
    local message = get_notification_message('waiting')
    local timeout = config.notifications.timeout_ms or 4000
    
    -- Send notification
    send_toast(window, title, message, timeout)
    
    -- Record for rate limiting
    record_notification(pane_id)
end

--- Notify of a status change
---@param pane userdata WezTerm pane object
---@param agent_type string Agent type
---@param old_status string Previous status
---@param new_status string New status
---@param config table Plugin configuration
function M.notify_status_change(pane, agent_type, old_status, new_status, config)
    -- Only notify for important transitions
    if new_status ~= 'waiting' then
        return
    end
    
    M.notify_waiting(pane, agent_type, config)
end

--- Clear notification state for a pane
---@param pane_id number Pane ID
function M.clear_state(pane_id)
    if pane_id then
        last_notification[pane_id] = nil
    else
        last_notification = {}
        notification_queue = {}
    end
end

--- Get queue size (for debugging)
---@return number Queue size
function M.get_queue_size()
    return #notification_queue
end

return M
