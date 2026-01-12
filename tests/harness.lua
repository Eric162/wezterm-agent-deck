local M = {}

local function fmt(value)
    if type(value) == 'string' then
        return string.format('%q', value)
    end
    return tostring(value)
end

function M.new_runner()
    local runner = {
        tests = {},
    }

    function runner:test(name, fn)
        table.insert(self.tests, { name = name, fn = fn })
    end

    function runner:run()
        local passed = 0
        local failed = 0

        for _, t in ipairs(self.tests) do
            local ok, err = pcall(t.fn)
            if ok then
                passed = passed + 1
            else
                failed = failed + 1
                io.stderr:write('FAIL: ' .. t.name .. '\n')
                io.stderr:write('  ' .. tostring(err) .. '\n')
            end
        end

        io.stdout:write(string.format('passed=%d failed=%d\n', passed, failed))

        if failed > 0 then
            os.exit(1)
        end
    end

    return runner
end

function M.eq(actual, expected, message)
    if actual ~= expected then
        error((message or 'not equal') .. ': actual=' .. fmt(actual) .. ' expected=' .. fmt(expected), 2)
    end
end

function M.truthy(value, message)
    if not value then
        error(message or 'expected truthy', 2)
    end
end

function M.falsy(value, message)
    if value then
        error(message or 'expected falsy', 2)
    end
end

return M
