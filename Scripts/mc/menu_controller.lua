-- Durable menu Apply -> one atomic settings/selection commit in the lifecycle.
local U = require('mc.util')
local M = {}
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

function M.new(menu, runtime, options)
    options = options or {}
    local values, lastState, revisions, stops = {}, {}, {}, {}
    local alive, bound = true, false
    local self = {}
    for _, row in ipairs(menu.rows) do
        if row.mcNavigation ~= 1 then values[row.Id] = tonumber(row.Default) end
    end
    for id, spec in pairs(menu.textSettings) do values[id] = spec.default end
    local defaults = U.copy(values)
    for id, value in pairs(options.values or {}) do if values[id] ~= nil then values[id] = value end end
    local function commit(nextValues)
        local state = menu.decodeState(nextValues)
        local changes = {}
        for category, settings in pairs(state) do
            if not equal(settings, lastState[category]) then changes[category] = settings end
        end
        runtime:commit(changes)
        values, lastState = nextValues, U.copy(state)
    end
    -- Saved settings never prevent startup: a combination that does not validate
    -- starts on the defaults instead.
    local started, why = pcall(commit, values)
    if not started then
        if options.onError then
            pcall(options.onError, {stage='config', message='saved settings unusable; using defaults: ' .. tostring(why)})
        end
        commit(defaults)
    end
    function self:values() return U.copy(values) end
    function self:apply(event)
        assert(alive, 'menu controller stopped')
        local provider = assert(menu.providers[event.providerId], 'unknown settings provider')
        assert(type(event.revision) == 'number' and event.revision >= 1
            and event.revision < math.huge and event.revision % 1 == 0, 'invalid Apply revision')
        if event.revision <= (revisions[event.providerId] or 0) then return false end
        assert(type(event.values) == 'table', 'Apply values required')
        -- Validate every row owned by the page before committing anything.
        local supplied = U.copy(event.values)
        local persisted = options.readValues and options.readValues() or {}
        for id in pairs(menu.textSettings) do supplied[id] = persisted[id] or values[id] end
        provider.decode(supplied)
        local nextValues = U.copy(values)
        for _, row in ipairs(provider.rows) do
            if row.mcNavigation ~= 1 then nextValues[row.Id] = supplied[row.Id] end
        end
        for id in pairs(menu.textSettings) do nextValues[id] = supplied[id] end
        commit(nextValues)
        revisions[event.providerId] = event.revision
        return true
    end
    function self:stop()
        alive = false
        local remaining,errors={},{}
        for _, stop in ipairs(stops) do
            local ok,result,detail=pcall(stop)
            if not ok or result==false then
                remaining[#remaining+1]=stop
                errors[#errors+1]=tostring(ok and detail or result)
            end
        end
        stops=remaining
        if #errors>0 then return false,table.concat(errors,'; ') end
        return true
    end
    function self:bind(settingsApi, queue)
        assert(alive and not bound, 'menu Apply subscription already bound or stopped')
        assert(type(queue) == 'function', 'game-thread queue required')
        bound = true
        local ids = {}; for id in pairs(menu.providers) do ids[#ids + 1] = id end; table.sort(ids)
        local ok, why = pcall(function()
            for _, id in ipairs(ids) do
                local stop = settingsApi.subscribe(id, function(event)
                    if not alive or event.providerId ~= id then return end
                    local snapshot = U.copy(event)
                    queue(function()
                        if not alive then return end
                        local applied, err = pcall(self.apply, self, snapshot)
                        if not applied and options.onError then options.onError({stage='settings', message=tostring(err)}) end
                    end)
                end)
                assert(type(stop) == 'function', 'settings subscription must return unsubscribe')
                stops[#stops + 1] = stop
            end
        end)
        if not ok then self:stop(); error(why) end
    end
    return self
end
return M
