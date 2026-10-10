-- Resolve class-qualified definitions against live Unreal objects. In particular,
-- a WidgetTree asset path is not the full path of a live widget instance.
local M = {}
local Objects = require('mc.objects')
local call, valid = Objects.call, Objects.valid
local function pathOf(fullName)
    return type(fullName) == 'string' and fullName:match('^%S+%s+(.+)$')
end
local function shortClass(path)
    return path:match('%.([^%.]+)$')
end
function M.className(selector)
    assert(type(selector) == 'table', 'selector required')
    local path = selector.object or selector.class
    assert(type(path) == 'string' and path ~= '', 'selector target required')
    if selector.object then
        local class = path:match('^(%S+)%s+')
        assert(class, 'object selector needs a class-qualified path')
        return class
    end
    local class = shortClass(path)
    assert(class, 'class selector needs a class path')
    return class
end
function M.owner(object)
    if not valid(object) then return nil end
    local seen = {}
    local outer = call(object, 'GetOuter')
    while valid(outer) do
        local address = call(outer, 'GetAddress')
        if not address or seen[address] then return nil end
        seen[address] = true
        local widgetClass = call(outer, 'IsA', '/Script/UMG.UserWidget')
        if widgetClass == true then
            return outer
        end
        outer = call(outer, 'GetOuter')
    end
end
function M.widgetOwner(object, selector)
    if not selector.object or not valid(object) then return nil end
    local requestedType, body = selector.object:match('^(%S+)%s+(.+)$')
    if not requestedType then return nil end
    local ownerClass, widgetName = body:match('^(.-):WidgetTree%.([%w_]+)$')
    if not ownerClass then return nil end
    local full = call(object, 'GetFullName')
    if type(full) ~= 'string' or full:sub(1, #requestedType + 1) ~= requestedType .. ' '
        or full:match('%.([^%.]+)$') ~= widgetName then return nil end
    local tree = call(object, 'GetOuter')
    local treeFull = valid(tree) and call(tree, 'GetFullName') or nil
    local treeName = type(treeFull) == 'string' and treeFull:match('%.([^%.]+)$')
    if treeName ~= 'WidgetTree' and not (treeName and treeName:match('^WidgetTree_%d+$')) then
        return nil
    end
    local owner = call(tree, 'GetOuter')
    if not valid(owner) then return nil end
    local ownerFull = call(owner, 'GetFullName')
    if type(ownerFull) ~= 'string' or not ownerFull:find('/Engine/Transient', 1, true)
        or ownerFull:find('Default__', 1, true) then return nil end
    local class = call(owner, 'GetClass')
    if not valid(class) or pathOf(call(class, 'GetFullName')) ~= ownerClass then return nil end
    return owner
end
function M.matches(object, selector)
    if not valid(object) then return false end
    if selector.class then
        if not selector.class:find('/', 1, true) then
            local full = call(object, 'GetFullName')
            return type(full) == 'string' and full:match('^(%S+)') == selector.class
        end
        local ok, match = pcall(function() return object:IsA(selector.class) end)
        if ok and match then return true end
        ok, match = pcall(function() return object:IsA('Class ' .. selector.class) end)
        return ok and match == true
    end
    if M.widgetOwner(object, selector) then return true end
    local full = call(object, 'GetFullName')
    return type(full) == 'string' and not full:find('Default__', 1, true)
        and not selector.object:find(':WidgetTree%.') and full == selector.object
end
return M
