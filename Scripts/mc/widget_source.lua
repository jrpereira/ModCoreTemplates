-- UE4SS event source for live category selectors. Install while main.lua is
-- loading, before game-thread startup.
local ObjectSelector = require('mc.object_selector')
local Widget = require('mc.widget')
local M = {}
local function safe(object, method, ...)
    return ObjectSelector.call(object, method, ...)
end
local unwrap = Widget.unwrap
local function isa(object, class)
    return safe(object, 'IsA', class) == true or safe(object, 'IsA', 'Class ' .. class) == true
end
local function eventClass(selector)
    local class = ObjectSelector.className(selector)
    if selector.class then return selector.class end
    local owner = selector.object:match('^%S+%s+(.-):WidgetTree%.[%w_]+$')
    if owner then return owner, '/Script/UMG.' .. class end
end
function M.new(categories, api)
    api = api or _G
    for _, name in ipairs({'FindAllOf','NotifyOnNewObject','RegisterHook','UnregisterHook',
        'RegisterLoadMapPreHook','RegisterLoadMapPostHook','IsInGameThread'}) do
        assert(type(api[name]) == 'function', 'UE4SS object source requires ' .. name)
    end
    local bridge=api.UE4SSLuaEventBridge
    local lifetimes=type(bridge)=='table' and bridge.lifetimes or nil
    local ok,caps=false,nil
    if type(bridge)=='table' and type(bridge.GetCapabilities)=='function' then
        ok,caps=pcall(bridge.GetCapabilities)
    end

    -- Lifetime capture may be unavailable after a failed ABI probe. The
    -- original map-scoped address/name identity remains usable in that case.
    assert(ok
        and type(caps)=='table'
        and (tonumber(caps.api or 0)>=5
            or tonumber(bridge.API_VERSION or 0)>=5)
        and type(lifetimes)=='table'
        and type(lifetimes.captureObject)=='function',
        'MCT requires UE4SSLuaEventBridge API 5 object lifetimes')
    local source = {}
    local selectors, notifyClasses, hasGroups, hasWidgets = {}, {}, false, false
    for _, category in ipairs(categories) do
        for _, selector in pairs(category.objects or {}) do
            if selector.source == 'create' then
                -- Construction belongs to the selected managed template.
            elseif selector.from then
                hasGroups, hasWidgets = true, true
            else
                ObjectSelector.className(selector)
                if selector.within then hasGroups = true end
                if selector.object and selector.object:find(':WidgetTree.',1,true)
                    or selector.class and selector.class:find('/Script/UMG.',1,true) then
                    hasWidgets = true
                end
                local first, second = eventClass(selector)
                if first then notifyClasses[first] = true end
                if second then notifyClasses[second] = true end
            end
        end
    end
    local known = setmetatable({}, {__mode='k'})
    local knownAddresses = {}
    local pendingRemoval = {}
    local built = {}
    local sink, getEpoch, subscribed, active = nil, nil, false, true
    local loading, currentWorld, generation = false, nil, 1
    local identityFailureReported=false
    local lifetimeMode=nil
    local hooks = {}
    local function errorReport(stage, message)
        local error = {stage=stage,message=tostring(message)}
        if type(api.MCTOnError)=='function' then pcall(api.MCTOnError,error)
        else print('[MCT] ' .. error.stage .. ': ' .. error.message) end
    end
    source.onError = function(error) errorReport(error.stage or 'object', error.message) end
    local function onGameThread()
        return api.IsInGameThread() == true
    end
    function source.watch(roots)
        assert(onGameThread(), 'selector activation requires the game thread')
        selectors=roots
        known=setmetatable({}, {__mode='k'})
        knownAddresses={}
        pendingRemoval={}
    end
    local function token(object)
        if not ObjectSelector.valid(object) then return nil end
        local address = safe(object,'GetAddress')
        if type(address) ~= 'number' then return nil end
        local name = safe(object,'GetFullName')
        if type(name) ~= 'string' then return nil end
        if lifetimeMode=='legacy' then
            return tostring(generation) .. ':' .. tostring(address) .. ':' .. name
        end
        local captured,lifetime,why=pcall(lifetimes.captureObject,object)
        if captured and type(lifetime)=='string' then
            lifetimeMode='native'
            return tostring(generation) .. ':' .. lifetime .. ':' .. tostring(address) .. ':' .. name
        end
        if lifetimeMode==nil and captured and why=='object lifetime service is unavailable' then
            lifetimeMode='legacy'
            errorReport('identity', 'native object lifetimes unavailable; using map-scoped address identity')
            return tostring(generation) .. ':' .. tostring(address) .. ':' .. name
        end
        if not identityFailureReported then
            identityFailureReported=true
            errorReport('identity',captured and (why or 'native lifetime unavailable') or lifetime)
        end
        return nil
    end
    source.identity = token
    local function world(object)
        local value = safe(object,'GetWorld')
        return ObjectSelector.valid(value) and value or nil
    end
    local function sameWorld(object)
        if not currentWorld then return true end
        local value = world(object)
        return value ~= nil and safe(value,'GetAddress') == currentWorld.address
            and token(value) == currentWorld.token
    end
    local function remember(object)
        known[object] = true
        for _, value in ipairs({object, ObjectSelector.owner(object)}) do
            local address = safe(value, 'GetAddress')
            if type(address) == 'number' then
                knownAddresses[address] = safe(value, 'GetFullName')
            end
        end
    end
    function source.valid(object)
        if not ObjectSelector.valid(object) then return false end
        local full = safe(object,'GetFullName')
        return type(full) == 'string' and not full:find('Default__',1,true)
            and not full:find('REINST_',1,true)
    end
    function source.ready(object)
        if loading or not source.valid(object) then return false end
        if isa(object,'/Script/UMG.Widget') then
            local owner = isa(object,'/Script/UMG.UserWidget') and object or ObjectSelector.owner(object)
            if not source.valid(owner) or not sameWorld(owner) then return false end
            local ownerToken = token(owner)
            if not ownerToken then return false end
            local parent = source.parent(object)
            local parented = source.valid(parent)
            if owner ~= object and not parented then
                -- Only the WidgetTree root may be parentless while its owner is
                -- in the viewport. A removed child must lose readiness.
                local ok, root = pcall(function() return owner.WidgetTree.RootWidget end)
                if not ok or not source.valid(root)
                    or safe(root,'GetAddress') ~= safe(object,'GetAddress') then return false end
            end
            if built[ownerToken] == false then return false end
            if built[ownerToken] == true then return true end
            -- Nested game HUDs are children of another UserWidget. IsInViewport
            -- is unavailable for them in Dawnwalker; a live world and panel
            -- parent establish readiness for a WidgetTree child.
            return safe(owner,'IsInViewport') == true or parented
        end
        return world(object) ~= nil and sameWorld(object)
    end
    function source.matches(object, selector)
        return source.valid(object) and ObjectSelector.matches(object, selector)
    end
    function source.parent(object)
        if not source.valid(object) then return nil end
        local parent
        if isa(object,'/Script/UMG.Widget') then parent = safe(object,'GetParent')
        else parent = safe(object,'GetOuter') end
        return source.valid(parent) and parent or nil
    end
    function source.find(selector)
        assert(onGameThread(), 'object discovery requires the game thread')
        assert(not selector.from, 'scoped targets are resolved from their parent')
        -- UE4SS returns nil when a blueprint class is not loaded yet.
        local found = api.FindAllOf(ObjectSelector.className(selector)) or {}
        assert(type(found)=='table', 'FindAllOf returned a non-array value')
        local result = {}
        for _, object in ipairs(found) do
            if source.matches(object, selector) then
                result[#result+1] = object
                remember(object)
            end
        end
        return result
    end
    function source.child(parent, class)
        if not source.valid(parent) then return nil end
        local count = safe(parent, 'GetChildrenCount')
        if type(count) ~= 'number' then return nil end
        local found
        for index=0,count-1 do
            local child = safe(parent, 'GetChildAt', index)
            if source.valid(child) and source.matches(child, {class=class}) then
                assert(not found, 'ambiguous scoped child: '..class)
                found = child
            end
        end
        return found
    end
    function source.member(parent, path)
        if not source.valid(parent) then return nil end
        local current = parent
        for name in path:gmatch('[^.]+') do
            if name=='@owner' then current=ObjectSelector.owner(current)
            else current = Widget.property(current, name) end
            if not source.valid(current) then return nil end
        end
        return current
    end
    function source.screen(object)
        assert(onGameThread(), 'viewport discovery requires the game thread')
        if not source.valid(object) or type(api.StaticFindObject) ~= 'function' then return nil end
        local layout = api.StaticFindObject('/Script/UMG.Default__WidgetLayoutLibrary')
        if not ObjectSelector.valid(layout) then return nil end
        local size = safe(layout, 'GetViewportSize', ObjectSelector.owner(object) or object)
        local width, height = size and tonumber(Widget.property(size, 'X')),
            size and tonumber(Widget.property(size, 'Y'))
        if not width or not height or width <= 0 or height <= 0
            or width == math.huge or height == math.huge then return nil end
        return {width=width,height=height,left=0,center=width/2,right=width,
            bottom=0,middle=height/2,top=height}
    end
    local function emit(kind, object)
        if not active or not sink then return end
        if not onGameThread() then
            errorReport('object-event', 'UE4SS delivered a lifecycle event off the game thread')
            return
        end
        sink({kind=kind,object=object,epoch=getEpoch()})
    end
    local function changed(object)
        if not source.valid(object) then return end
        local matched=false
        for _,selector in ipairs(selectors) do
            if source.matches(object,selector) then matched=true;break end
        end
        if not matched then return end
        remember(object)
        emit('changed',object)
    end
    local function wakeKnown()
        for object in pairs(known) do
            if source.valid(object) then emit('changed',object) end
        end
    end
    local function knownObject(object)
        if not ObjectSelector.valid(object) then return false end
        local address = safe(object, 'GetAddress')
        local name = address and knownAddresses[address]
        return name ~= nil and safe(object, 'GetFullName') == name
    end
    local function related(object)
        local seen={}
        for _=1,32 do
            if not ObjectSelector.valid(object) then return false end
            local address=safe(object,'GetAddress')
            if not address or seen[address] then return false end
            seen[address]=true
            if knownObject(object) then return true end
            object=safe(object,'GetParent')
        end
        return false
    end
    local function hook(path, before, after)
        local pre, post = api.RegisterHook(path,before,after)
        assert(type(pre)=='number' and type(post)=='number', 'invalid hook IDs: '..path)
        hooks[#hooks+1] = {path=path,pre=pre,post=post}
    end
    local function install()
        for class in pairs(notifyClasses) do
            api.NotifyOnNewObject(class,function(object)
                if not active then return end
                local current = unwrap(object)
                if source.valid(current) then changed(current) end
            end)
        end
        -- Verified in the installed UE4SS build: Construct/Destruct and
        -- OnInitialized reject RegisterHook, but these viewport methods work.
        for _, name in ipairs({'AddToViewport','AddToPlayerScreen'}) do
            hook('/Script/UMG.UserWidget:'..name,function() end,function(context)
                if not active then return end
                local owner = unwrap(context)
                if not related(owner) then return end
                local id = token(owner)
                if id then built[id] = true; wakeKnown() end
            end)
        end
        hook('/Script/UMG.Widget:RemoveFromParent',function(context)
            if not active then return end
            local owner = unwrap(context)
            if not related(owner) then return end
            local address = safe(owner, 'GetAddress')
            if type(address) == 'number' then pendingRemoval[address] = true end
            if isa(owner,'/Script/UMG.UserWidget') then
                local id = token(owner)
                if id then built[id] = false; wakeKnown() end
            end
        end,function(context)
            if not active then return end
            local address = safe(unwrap(context), 'GetAddress')
            if type(address) == 'number' and pendingRemoval[address] then
                pendingRemoval[address] = nil
                wakeKnown()
            end
        end)
        if hasGroups or hasWidgets then
            -- A removed UserWidget is unready until it joins a panel again.
            hook('/Script/UMG.PanelWidget:AddChild',function() end,function(parentParam, childParam)
                if not active then return end
                local parent=unwrap(parentParam)
                local child = unwrap(childParam)
                if not related(parent) and not knownObject(child) then return end
                if source.valid(child) then
                    if isa(child,'/Script/UMG.UserWidget') then
                        local id = token(child)
                        if id then built[id] = nil end
                    end
                end
                wakeKnown()
            end)
            for _, name in ipairs({'RemoveChild','ClearChildren'}) do
                hook('/Script/UMG.PanelWidget:'..name,function() end,function(parentParam)
                    if active and related(unwrap(parentParam)) then wakeKnown() end
                end)
            end
        end
        api.RegisterLoadMapPreHook(function()
            if not active then return end
            loading, currentWorld, built = true, nil, {}
            wakeKnown() -- detach while old references are still valid
            known=setmetatable({}, {__mode='k'})
            knownAddresses={}
            pendingRemoval={}
        end)
        api.RegisterLoadMapPostHook(function(_, worldParam)
            if not active then return end
            generation = generation + 1
            local current = unwrap(worldParam)
            local id = token(current)
            emit('world_invalidated')
            if not id then
                errorReport('world', 'map completed without a valid current world')
                return
            end
            currentWorld = {address=safe(current,'GetAddress'),token=id}
            loading = false
            emit('world_ready')
        end)
    end
    local ok, why = pcall(install)
    if not ok then
        active = false
        for i=#hooks,1,-1 do
            local h=hooks[i]; pcall(api.UnregisterHook,h.path,h.pre,h.post)
        end
        error('object source hook installation failed: '..tostring(why))
    end
    function source.subscribe(callback, epoch)
        assert(active and not subscribed, 'object source already subscribed or stopped')
        assert(type(callback)=='function' and type(epoch)=='function', 'object sink and epoch required')
        sink, getEpoch, subscribed = callback, epoch, true
        return function() sink, getEpoch, subscribed = nil,nil,false end
    end
    function source.stop()
        if not active then return end
        active, sink, getEpoch, subscribed = false,nil,nil,false
        for i=#hooks,1,-1 do
            local h=hooks[i]; pcall(api.UnregisterHook,h.path,h.pre,h.post)
        end
    end
    return source
end
return M
