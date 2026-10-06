-- Test double for UE4SSLuaEventBridge lifetimes (API 6 weak handles).
-- alive(object) is the native lifetime; by default the object's IsValid.
-- Like the bridge, a handle whose object died stays empty.
local M = {}

local function isValid(object)
    local ok, value = pcall(function() return object:IsValid() end)
    return ok and value == true
end

function M.service(alive)
    alive = alive or isValid
    local tokens, count = setmetatable({}, {__mode='k'}), 0
    local service = {held=0}
    local function token(object)
        if not tokens[object] then count = count + 1; tokens[object] = tostring(count) end
        return tokens[object]
    end
    local Handle = {}
    Handle.__index = Handle
    function Handle:get()
        if self.object ~= nil and alive(self.object) then return self.object end
        self.object = nil
    end
    function Handle:identity() return self.token, self.address end
    function Handle:release()
        if self.released then return end
        self.object, self.released = nil, true
        service.held = service.held - 1
    end
    function service.captureObject(object)
        if object == nil or not alive(object) then return nil, 'object must be a live UE4SS UObject wrapper' end
        return token(object)
    end
    function service.weak(object)
        if object == nil or not alive(object) then return nil, 'object must be a live UE4SS UObject wrapper' end
        service.held = service.held + 1
        return setmetatable({object=object, token=token(object)}, Handle)
    end
    -- A new token for object, as when its address is reused by another object.
    function service.renew(object) tokens[object] = nil end
    return service
end

-- Use a service for every mc.objects caller that has no object source.
function M.install(alive)
    local service = M.service(alive)
    require('mc.objects').useLifetimes(service)
    return service
end

-- A UE4SSLuaEventBridge table for an object source's api.
-- bridge.loopStart() delivers pending onLoopStart callbacks, as the first update does.
function M.bridge(service)
    service = service or M.service()
    local pending = {}
    local bridge = {API_VERSION=6, lifetimes=service,
        GetCapabilities=function()
            return {api=6, object_lifetimes=true, weak_handles=true, loop_start=true}
        end}
    function bridge.onLoopStart(callback)
        local record = {callback=callback}
        pending[#pending+1] = record
        return function()
            local live = record.callback ~= nil
            record.callback = nil
            return live
        end
    end
    function bridge.loopStart()
        local ready = pending
        pending = {}
        for _, record in ipairs(ready) do
            local callback = record.callback
            record.callback = nil
            if callback then callback() end
        end
    end
    return bridge
end

return M
