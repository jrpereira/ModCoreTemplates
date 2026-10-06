-- Start the self-contained Lua runtime on UE4SS's game thread.
local Bootstrap = require('mc.bootstrap')
local Events = require('mc_events')
local M = {}
function M.start(options, api)
    api = api or _G
    assert(type(api.ExecuteInGameThread) == 'function', 'game-thread dispatch unavailable')
    local configured = {}
    for key, value in pairs(options) do configured[key] = value end
    if not configured.categories then
        configured.categories={}
        local execute=configured.execute or function(path) return assert(loadfile(path))() end
        for _,path in ipairs(configured.categoryFiles or {}) do
            local category=execute(path)
            assert(type(category)=='table',path..': expected category definition')
            configured.categories[#configured.categories+1]=category
        end
    end
    if not configured.host and not configured.objectSource then
        configured.objectSource = require('mc.widget_source').new(configured.categories, api, configured.log)
    end
    if configured.objectSource then
        assert(not configured.host, 'supply either objectSource or host')
        local source = configured.objectSource
        configured.host = require('mc.lua_references').new(source)
        configured.closeHost = source.stop
        configured.objectSource = nil
    end
    configured.subscribeLoopStart = function(callback)
        local active = true
        api.ExecuteInGameThread(function() if active then callback() end end)
        return function() active = false end
    end
    configured.queue = api.ExecuteInGameThread
    if configured.menuRoot then configured.menuShared = assert(api.ModRef, 'ModRef unavailable') end
    local bootstrap
    -- No group has focus until ModCore Controls reports its Default wheel.
    configured.state=configured.state or {revision=0,controls={group={}}}
    if not configured.events and api.ModRef and type(api.RegisterConsoleCommandHandler)=='function' then
        configured.events=Events.hub(api,configured.state,function(event)
            if bootstrap and bootstrap.runtime then bootstrap.runtime:stateChanged(event) end
        end)
        configured.closeState=function() return configured.events:stop() end
    end
    bootstrap=Bootstrap.new(configured)
    return bootstrap
end
return M
