-- Shared helpers for live UE4SS objects. call, valid, same and parent take a
-- wrapper obtained in the current call: UE4SS IsValid reads the object, so a
-- wrapper kept across garbage collection reads freed memory. Keep an object
-- past the current call only as a weak handle from hold, and read it with get.
local M = {}

function M.call(object, method, ...)
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    if ok then return value end
end

function M.valid(object)
    return object ~= nil and M.call(object, 'IsValid') == true
end

-- Compare current live wrappers. This is not a persistent lifetime identity.
function M.same(a, b)
    if not M.valid(a) or not M.valid(b) then return false end
    local name = M.call(a, 'GetFullName')
    return type(name) == 'string' and name ~= '' and name == M.call(b, 'GetFullName')
end

-- UMG panel parent, not UObject outer ownership.
function M.parent(object)
    if not M.valid(object) then return nil end
    local parent = M.call(object, 'GetParent')
    return M.valid(parent) and parent or nil
end

-- UE4SSLuaEventBridge lifetimes; the session's own bridge unless set.
local lifetimes
function M.useLifetimes(service)
    assert(service == nil or type(service) == 'table', 'lifetime service must be a table')
    lifetimes = service
end
local function service()
    if lifetimes then return lifetimes end
    local bridge = rawget(_G, 'UE4SSLuaEventBridge')
    return type(bridge) == 'table' and type(bridge.lifetimes) == 'table' and bridge.lifetimes or nil
end

-- Weak handle for a fresh live wrapper: a hook argument, a lookup result, a
-- value read in this call, or a get result. Without weak handles nothing is
-- kept: nil and the reason.
function M.hold(object)
    if not M.valid(object) then return nil, 'object is not live' end
    local current = service()
    if not current or type(current.weak) ~= 'function' then
        return nil, 'UE4SSLuaEventBridge weak handles unavailable'
    end
    local ok, handle, why = pcall(current.weak, object)
    if ok and handle ~= nil then return handle end
    return nil, tostring(ok and (why or 'weak handle unavailable') or handle)
end

-- The live wrapper behind a handle from hold, or nil once its object died.
function M.get(handle)
    if handle == nil then return nil end
    local ok, object = pcall(function() return handle:get() end)
    if ok and M.valid(object) then return object end
end

function M.release(handle)
    if handle ~= nil then pcall(function() handle:release() end) end
end

return M
