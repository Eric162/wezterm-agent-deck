package.path = table.concat({
    './plugin/?.lua',
    './plugin/?/init.lua',
    './plugin/components/?.lua',
    package.path,
}, ';')

package.preload['wezterm'] = function()
    return require('tests.stub_wezterm')
end

local t = require('tests.harness')
local runner = t.new_runner()

runner:test('config.set merges defaults and validates', function()
    local config = require('config')
    local wezterm = require('wezterm')

    config.set({
        update_interval = 50,
        cooldown_ms = -1,
        max_lines = 5,
        icons = { style = 'nope' },
        tab_title = { position = 'middle' },
    })

    local cfg = config.get()

    t.eq(cfg.update_interval, 5000)
    t.eq(cfg.cooldown_ms, 2000)
    t.eq(cfg.max_lines, 100)
    t.eq(cfg.icons.style, 'unicode')
    t.eq(cfg.tab_title.position, 'left')

    t.truthy(#wezterm._logs.warn > 0, 'expected warnings logged')
end)

runner:test('detector.detect_agent matches executable, argv, and children', function()
    local detector = require('detector')

    local pane = {
        pane_id = function() return 1 end,
        get_foreground_process_info = function()
            return {
                executable = '/usr/bin/node',
                argv = { 'node', 'cli.js', 'opencode' },
                children = {
                    { executable = '/opt/bin/claude-code', argv = { 'claude-code' } },
                },
            }
        end,
        get_foreground_process_name = function()
            return '/usr/bin/node'
        end,
    }

    local cfg = {
        agents = {
            opencode = { patterns = { 'opencode' } },
            claude = { patterns = { 'claude', 'claude%-code' } },
        },
    }

    t.eq(detector.detect_agent(pane, cfg), 'opencode')

    detector.clear_cache(1)
    pane.get_foreground_process_info = function()
        return {
            executable = '/usr/bin/node',
            argv = { 'node', 'cli.js' },
            children = {
                { executable = '/opt/bin/claude-code', argv = { 'claude-code' } },
            },
        }
    end
    t.eq(detector.detect_agent(pane, cfg), 'claude')
end)

runner:test('status.detect_status prefers idle prompt over stale working', function()
    local status = require('status')

    local pane = {
        get_lines_as_text = function()
            return table.concat({
                'some output',
                'Esc to interrupt',
                'done',
                '> ',
            }, '\n')
        end,
        get_logical_lines_as_text = function()
            return ''
        end,
    }

    local cfg = { max_lines = 100, agents = { opencode = {} } }

    t.eq(status.detect_status(pane, 'opencode', cfg), 'idle')
end)

runner:test('status.detect_status finds waiting in recent output', function()
    local status = require('status')

    local pane = {
        get_lines_as_text = function()
            return table.concat({
                'do you trust this command?',
                '(Y/n)',
            }, '\n')
        end,
        get_logical_lines_as_text = function()
            return ''
        end,
    }

    local cfg = { max_lines = 100, agents = { opencode = {} } }

    t.eq(status.detect_status(pane, 'opencode', cfg), 'waiting')
end)

runner:test('components render placeholders and badge counts', function()
    local config = require('config')
    local components = require('components')

    config.set({
        colors = {
            working = '#00ff00',
            waiting = '#ffff00',
            idle = '#0000ff',
            inactive = '#888888',
        },
        icons = {
            style = 'unicode',
            unicode = {
                working = 'W',
                waiting = 'A',
                idle = 'I',
                inactive = 'N',
            },
        },
    })

    local cfg = config.get()

    local label_items = components.render('label', {
        status = 'working',
        agent_type = 'opencode',
        config = cfg,
    }, {
        type = 'label',
        format = '{agent_type}:{status}',
    })

    local label_text = nil
    for _, item in ipairs(label_items) do
        if item.Text then
            label_text = item.Text
        end
    end
    t.eq(label_text, 'opencode:working')

    local badge_items = components.render('badge', {
        counts = { working = 2, waiting = 1, idle = 0, inactive = 0 },
        config = cfg,
    }, {
        type = 'badge',
        filter = 'waiting',
        label = 'waiting',
    })

    local badge_text = nil
    for _, item in ipairs(badge_items) do
        if item.Text then
            badge_text = item.Text
        end
    end
    t.eq(badge_text, '1 waiting')
end)

runner:run()
