local M = {}

M._logs = {
    info = {},
    warn = {},
    error = {},
}

function M.log_info(msg)
    table.insert(M._logs.info, tostring(msg))
end

function M.log_warn(msg)
    table.insert(M._logs.warn, tostring(msg))
end

function M.log_error(msg)
    table.insert(M._logs.error, tostring(msg))
end

function M.format(items)
    return items
end

return M
