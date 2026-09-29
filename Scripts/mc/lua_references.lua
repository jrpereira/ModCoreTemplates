-- Lua-only references. Identity is scoped to the current map generation.
local M = {}
function M.new(source)
    for _, name in ipairs({'valid','identity','ready','matches','parent','find','watch','screen','subscribe','onError'}) do
        assert(type(source[name]) == 'function', 'object source requires ' .. name)
    end
    local host = {onError=source.onError}
    local records = setmetatable({}, {__mode='k'})
    local wrappers = setmetatable({}, {__mode='k'})
    local byIdentity = setmetatable({}, {__mode='v'})
    function host.valid(reference)
        local record = records[reference]
        return record ~= nil and source.valid(record.object) == true
            and source.identity(record.object) == record.id
    end
    function host.capture(object)
        if object == nil then return nil end
        if records[object] then return host.valid(object) and object or nil end
        local cached = wrappers[object]
        if cached then
            if host.valid(cached) then return cached end
            wrappers[object] = nil
        end
        if source.valid(object) ~= true then return nil end
        local id = source.identity(object)
        if type(id) ~= 'string' then return nil end
        local reference = byIdentity[id]
        if reference and not host.valid(reference) then reference = nil end
        if not reference then
            reference = {}
            records[reference] = {object=object, id=id}
            byIdentity[id] = reference
        end
        wrappers[object] = reference
        return reference
    end
    function host.identity(reference)
        return assert(records[reference], 'unknown Lua reference').id
    end
    function host.unwrap(reference)
        if host.valid(reference) then return records[reference].object end
    end
    function host.ready(reference)
        local object = host.unwrap(reference)
        return object ~= nil and source.ready(object) == true
    end
    function host.matches(reference, selector)
        local object = host.unwrap(reference)
        return object ~= nil and source.matches(object, selector) == true
    end
    function host.parent(reference)
        local object = host.unwrap(reference)
        if object then return host.capture(source.parent(object)) end
    end
    function host.find(selector)
        local result = {}
        for _, object in ipairs(source.find(selector)) do
            local reference = host.capture(object)
            if reference then result[#result+1] = reference end
        end
        return result
    end
    function host.watch(roots) return source.watch(roots) end
    function host.mutate(callback)
        if source.mutate then return source.mutate(callback) end
        return callback()
    end
    function host.child(reference, class)
        local object = host.unwrap(reference)
        if object then return host.capture(source.child(object, class)) end
    end
    function host.member(reference, path)
        local object = host.unwrap(reference)
        if object then return host.capture(source.member(object, path)) end
    end
    function host.screen(reference)
        local object = host.unwrap(reference)
        if object then return source.screen(object) end
    end
    function host.subscribe(callback, epoch)
        return source.subscribe(function(event)
            if event.kind == 'changed' then
                local reference = host.capture(event.object)
                if reference then callback({kind='changed', object=reference, epoch=event.epoch}) end
            else
                callback(event)
            end
        end, epoch)
    end
    return host
end
return M
