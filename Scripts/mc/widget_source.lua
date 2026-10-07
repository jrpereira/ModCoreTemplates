-- UE4SS event source for live category selectors. Create while main.lua is
-- loading; activate with the categories that have templates before the
-- runtime's first snapshot.
local ObjectSelector = require('mc.object_selector')
local Objects = require('mc.objects')
local Widget = require('mc.widget')
local Log = require('mc_log')
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
-- Reported stages that degrade gracefully; every other failure is an ERROR, and a failed
-- startup is CRITICAL.
local levels={identity='warn',config='warn',['config migration']='warn',
    ['object-event']='warn',startup='critical'}

-- log: an mc_log logger (or a plain function); reports go to api.MCTOnError instead when set.
function M.new(categories, api, log)
    api = api or _G
    log = Log.wrap(log or Log.new({name='ModCoreTemplates'}))
    -- Map changes need no LoadMap hooks: the old world's objects become invalid and
    -- the new HUD is announced through object creation and viewport events.
    for _, name in ipairs({'FindAllOf','NotifyOnNewObject','RegisterHook','UnregisterHook',
        'IsInGameThread','ExecuteInGameThread'}) do
        assert(type(api[name]) == 'function', 'UE4SS object source requires ' .. name)
    end
    local bridge=api.UE4SSLuaEventBridge
    local lifetimes=type(bridge)=='table' and bridge.lifetimes or nil
    local ok,caps=false,nil
    if type(bridge)=='table' and type(bridge.GetCapabilities)=='function' then
        ok,caps=pcall(bridge.GetCapabilities)
    end

    -- Objects are kept only as weak handles. If the bridge's ABI probe fails,
    -- holding fails and nothing is kept or attached: there is no fallback.
    assert(ok
        and type(caps)=='table'
        and (tonumber(caps.api or 0)>=6
            or tonumber(bridge.API_VERSION or 0)>=6)
        and type(lifetimes)=='table'
        and type(lifetimes.captureObject)=='function'
        and type(lifetimes.weak)=='function',
        'MCT requires UE4SSLuaEventBridge API 6 weak handles')
    Objects.useLifetimes(lifetimes)
    -- Adds the bridge's reason when its lifetime service is down.
    local function lifetimeFailure(why)
        local current=select(2,pcall(bridge.GetCapabilities))
        local reason=type(current)=='table' and current.object_lifetimes~=true
            and current.object_lifetimes_reason
        return tostring(why)..(reason and ' (object lifetimes unavailable: '..tostring(reason)..')' or '')
    end
    local source = {log=log}
    local selectors, notifyClasses, ownerClasses, hasWithin, hasWidgets = {}, {}, {}, false, false
    local function analyze(used)
        for _, category in ipairs(used) do
            -- Roots read by scoped targets; their members may not exist at creation.
            local scopedRoots = {}
            for _, selector in pairs(category.objects or {}) do
                if selector.from then scopedRoots[selector.from] = true end
            end
            for name, selector in pairs(category.objects or {}) do
                if selector.source == 'create' then
                    -- Construction belongs to the selected managed template.
                elseif selector.from then
                    -- Scoped targets are read again from their root on every
                    -- reconcile, so they need no events of their own.
                else
                    ObjectSelector.className(selector)
                    if selector.within then hasWithin = true end
                    if selector.object and selector.object:find(':WidgetTree.',1,true)
                        or selector.class and selector.class:find('/Script/UMG.',1,true) then
                        hasWidgets = true
                    end
                    -- A WidgetTree child is found through its owner's creation
                    -- and the owner revisits, not by watching its widget class.
                    local first, second = eventClass(selector)
                    if first then notifyClasses[first] = true end
                    -- A root with scoped targets is revisited too: a nested HUD is
                    -- announced before its WidgetTree is filled and never enters the
                    -- viewport, so nothing else would reconcile it again.
                    if first and (second or scopedRoots[name]) then ownerClasses[first] = true end
                end
            end
        end
    end
    -- Live roots by lifetime token, as weak handles: an unrelated hook during a
    -- save load visits them after the old world was collected.
    local known = {}
    local knownAddresses = {}
    -- Parents of known roots and their owners; clearing one may remove a root.
    local panelAddresses = {}
    local pendingRemoval = {}
    local built = {}
    local sink, getEpoch, subscribed, active = nil, nil, false, true
    local mutationDepth, wakePending = 0, false
    local identityFailureReported=false
    local hooks, hookSpecs = {}, {}
    local refreshHooks = function() end
    -- level (optional) overrides the stage's level for one report.
    local function errorReport(stage, message, level)
        local error = {stage=stage,message=tostring(message)}
        if type(api.MCTOnError)=='function' then pcall(api.MCTOnError,error)
        else log[level or levels[stage] or 'error'](error.stage, ': ', error.message) end
    end
    source.onError = function(error) errorReport(error.stage or 'object', error.message) end
    local function onGameThread()
        return api.IsInGameThread() == true
    end
    local function forgetKnown()
        for _,handle in pairs(known) do Objects.release(handle) end
        known={}
    end
    -- The live known roots; dead ones are dropped without being read.
    local function knownObjects()
        local result={}
        for key,handle in pairs(known) do
            local object=Objects.get(handle)
            if object then result[#result+1]=object
            else known[key]=nil; Objects.release(handle) end
        end
        return result
    end
    function source.watch(roots)
        assert(onGameThread(), 'selector activation requires the game thread')
        selectors=roots
        forgetKnown()
        knownAddresses={}
        panelAddresses={}
        pendingRemoval={}
        refreshHooks()
    end
    local function token(object)
        if not ObjectSelector.valid(object) then return nil end
        local address = safe(object,'GetAddress')
        if type(address) ~= 'number' then return nil end
        local name = safe(object,'GetFullName')
        if type(name) ~= 'string' then return nil end
        local captured,lifetime,why=pcall(lifetimes.captureObject,object)
        if captured and type(lifetime)=='string' then
            return lifetime .. ':' .. tostring(address) .. ':' .. name
        end
        if not identityFailureReported then
            identityFailureReported=true
            errorReport('identity',lifetimeFailure(captured and (why or 'native lifetime unavailable') or lifetime))
        end
        return nil
    end
    source.identity = token
    local function world(object)
        local value = safe(object,'GetWorld')
        return ObjectSelector.valid(value) and value or nil
    end
    local function remember(object)
        local handle,why=Objects.hold(object)
        if not handle then
            if not identityFailureReported then
                identityFailureReported=true
                errorReport('identity',lifetimeFailure(why))
            end
            return
        end
        local key=(handle:identity()) or handle
        if known[key] then Objects.release(handle) else known[key]=handle end
        for _, value in ipairs({object, ObjectSelector.owner(object)}) do
            local address = safe(value, 'GetAddress')
            if type(address) == 'number' then
                knownAddresses[address] = safe(value, 'GetFullName')
            end
        end
        refreshHooks()
    end
    function source.valid(object)
        if not ObjectSelector.valid(object) then return false end
        local full = safe(object,'GetFullName')
        return type(full) == 'string' and not full:find('Default__',1,true)
            and not full:find('REINST_',1,true)
    end
    -- A UserWidget that CommonUI hosts for another one (the game HUD inside
    -- WBP_UIFrontend) has no panel parent and is not in the viewport itself; it
    -- is ready while the UserWidget whose WidgetTree owns it is ready.
    local function hosted(owner, depth)
        local tree = safe(owner, 'GetOuter')
        if not source.valid(tree) or not isa(tree, '/Script/UMG.WidgetTree') then return false end
        local host = safe(tree, 'GetOuter')
        if not source.valid(host) or not isa(host, '/Script/UMG.UserWidget') then return false end
        return depth > 0 and source.ready(host, depth - 1)
    end
    function source.ready(object, depth)
        depth = depth or 4
        if not source.valid(object) then return false end
        if isa(object,'/Script/UMG.Widget') then
            local owner = isa(object,'/Script/UMG.UserWidget') and object or ObjectSelector.owner(object)
            if not source.valid(owner) then return false end
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
            return safe(owner,'IsInViewport') == true or parented or hosted(owner, depth)
        end
        return world(object) ~= nil
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
        local hud=ObjectSelector.owner(object) or object
        local size = safe(layout, 'GetViewportSize', hud)
        local scale=tonumber(safe(layout,'GetViewportScale',hud))
        local width, height = size and tonumber(Widget.property(size, 'X')),
            size and tonumber(Widget.property(size, 'Y'))
        if not width or not height or width <= 0 or height <= 0
            or width == math.huge or height == math.huge
            or not scale or scale<=0 or scale==math.huge then return nil end
        width,height=width/scale,height/scale
        return {width=width,height=height,left=0,center=width/2,right=width,
            bottom=0,middle=height/2,top=height,scale=scale}
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
    local function wakeKnownNow()
        for _,object in ipairs(knownObjects()) do
            if source.valid(object) then
                -- A lifecycle event reconciles every cached candidate. One
                -- representative object is enough to wake the runtime.
                emit('changed',object)
                return
            end
        end
    end
    local function wakeKnown()
        if mutationDepth > 0 then
            wakePending = true
            return
        end
        wakeKnownNow()
    end
    function source.mutate(callback)
        assert(type(callback) == 'function', 'mutation callback required')
        mutationDepth = mutationDepth + 1
        local ok, first, second, third = pcall(callback)
        mutationDepth = mutationDepth - 1
        if mutationDepth == 0 and wakePending then
            wakePending = false
            wakeKnownNow()
        end
        if not ok then error(first, 0) end
        return first, second, third
    end
    local function knownObject(object)
        if not ObjectSelector.valid(object) then return false end
        local address = safe(object, 'GetAddress')
        local name = address and knownAddresses[address]
        return name ~= nil and safe(object, 'GetFullName') == name
    end
    local function knownPanel(object)
        local address = safe(object, 'GetAddress')
        return type(address) == 'number'
            and (panelAddresses[address] == true or knownAddresses[address] ~= nil)
    end
    -- Ancestry is needed only by within groups; every other check is one lookup.
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
    local function anyKnownValid()
        return #knownObjects()>0
    end
    -- An unrelated call while every known root is gone means the game left
    -- the world (map change or main menu): drop the widget hooks.
    local function missed()
        if not anyKnownValid() then refreshHooks() end
    end
    -- Game state decides which widget hooks exist:
    --   idle     no live root (boot, main menu, loading): none
    --   waiting  a live root is not ready yet: all, including AddChild
    --   ready    every live root is ready: all except AddChild
    -- within groups keep AddChild while armed, since their members can join later.
    local function wanted()
        local armed, waiting = false, false
        -- Rebuilt from live roots so addresses from an earlier map cannot match.
        panelAddresses, knownAddresses = {}, {}
        for _,object in ipairs(knownObjects()) do
            if source.valid(object) then
                armed = true
                if not waiting and not source.ready(object) then waiting = true end
                for _, value in ipairs({object, ObjectSelector.owner(object)}) do
                    local address = safe(value, 'GetAddress')
                    if type(address) == 'number' then knownAddresses[address] = safe(value, 'GetFullName') end
                    local parent = safe(value, 'GetParent')
                    local address = ObjectSelector.valid(parent) and safe(parent, 'GetAddress')
                    if type(address) == 'number' then panelAddresses[address] = true end
                end
            end
        end
        return armed, waiting
    end
    local function applyHooks()
        local armed, waiting = wanted()
        for _, spec in ipairs(hookSpecs) do
            local want = armed and (not spec.waiting or waiting or hasWithin)
            local current = hooks[spec.path]
            if want and not current then
                local pre, post = api.RegisterHook(spec.path, spec.before, spec.after)
                assert(type(pre)=='number' and type(post)=='number', 'invalid hook IDs: '..spec.path)
                hooks[spec.path] = {pre=pre,post=post}
            elseif not want and current then
                hooks[spec.path] = nil
                pcall(api.UnregisterHook, spec.path, current.pre, current.post)
            end
        end
    end
    local function removeHooks()
        for _, spec in ipairs(hookSpecs) do
            local current = hooks[spec.path]
            if current then
                hooks[spec.path] = nil
                pcall(api.UnregisterHook, spec.path, current.pre, current.post)
            end
        end
    end
    -- Hooks change on the next game-thread dispatch, never inside a callback.
    local refreshQueued = false
    refreshHooks = function()
        if refreshQueued or not active then return end
        refreshQueued = true
        api.ExecuteInGameThread(function()
            refreshQueued = false
            if not active then return end
            local ok, why = pcall(applyHooks)
            if not ok then errorReport('object-event', 'widget hook update failed: '..tostring(why)) end
        end)
    end
    local function spec(path, before, after, waitingOnly)
        hookSpecs[#hookSpecs+1] = {path=path, before=before or function() end,
            after=after or function() end, waiting=waitingOnly}
    end
    local function install()
        local function revisitOwner(class,remaining)
            api.ExecuteInGameThread(function()
                if not active or not subscribed then return end
                for _,selector in ipairs(selectors) do
                    if eventClass(selector)==class then
                        for _,candidate in ipairs(source.find(selector)) do changed(candidate) end
                    end
                end
                if remaining>1 then revisitOwner(class,remaining-1) end
            end)
        end
        -- Root classes exist only in a loaded world, so these stay registered.
        for class in pairs(notifyClasses) do
            api.NotifyOnNewObject(class,function(object)
                if not active then return end
                local current = unwrap(object)
                if source.valid(current) then changed(current) end
                if ownerClasses[class] then
                    -- The owner notification can precede construction of its
                    -- WidgetTree children. Revisit exact child selectors on
                    -- the next game-thread dispatch, after that tree exists.
                    revisitOwner(class,3)
                end
            end)
        end
        local function ours(object)
            return knownObject(object) or hasWithin and related(object)
        end
        -- Verified in the installed UE4SS build: Construct/Destruct and
        -- OnInitialized reject RegisterHook, but these viewport methods work.
        for _, name in ipairs({'AddToViewport','AddToPlayerScreen'}) do
            spec('/Script/UMG.UserWidget:'..name,nil,function(context)
                if not active then return end
                local owner = unwrap(context)
                if not ours(owner) then return missed() end
                local id = token(owner)
                if id then built[id] = true; wakeKnown() end
                refreshHooks()
            end)
        end
        spec('/Script/UMG.Widget:RemoveFromParent',function(context)
            if not active then return end
            local owner = unwrap(context)
            if not ours(owner) then return missed() end
            local address = safe(owner, 'GetAddress')
            if type(address) == 'number' then pendingRemoval[address] = true end
            if isa(owner,'/Script/UMG.UserWidget') then
                local id = token(owner)
                if id then built[id] = false; wakeKnown() end
            end
            refreshHooks()
        end,function(context)
            if not active then return end
            local address = safe(unwrap(context), 'GetAddress')
            if type(address) == 'number' and pendingRemoval[address] then
                pendingRemoval[address] = nil
                wakeKnown()
                refreshHooks()
            end
        end)
        if hasWidgets then
            -- A removed UserWidget is unready until it joins a panel again.
            spec('/Script/UMG.PanelWidget:AddChild',nil,function(parentParam, childParam)
                if not active then return end
                local child = unwrap(childParam)
                if not (knownObject(child) or hasWithin and related(unwrap(parentParam))) then
                    return missed()
                end
                if source.valid(child) and isa(child,'/Script/UMG.UserWidget') then
                    local id = token(child)
                    if id then built[id] = nil end
                end
                wakeKnown()
                refreshHooks()
            end, true)
            spec('/Script/UMG.PanelWidget:RemoveChild',nil,function(parentParam, childParam)
                if not active then return end
                local parent = unwrap(parentParam)
                if not (knownObject(unwrap(childParam)) or knownPanel(parent)
                    or hasWithin and related(parent)) then return missed() end
                wakeKnown()
                refreshHooks()
            end)
            spec('/Script/UMG.PanelWidget:ClearChildren',nil,function(parentParam)
                if not active then return end
                local parent = unwrap(parentParam)
                if not (knownPanel(parent) or hasWithin and related(parent)) then return missed() end
                wakeKnown()
                refreshHooks()
            end)
        end
    end
    -- Notifications cannot be withdrawn, so they are registered once, for the
    -- categories that have templates.
    local activated = false
    function source.activate(used)
        assert(active and not activated, 'object source already activated or stopped')
        assert(type(used) == 'table', 'object source categories required')
        activated = true
        analyze(used)
        local ok, why = pcall(install)
        if not ok then
            active = false
            error('object source hook installation failed: '..tostring(why))
        end
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
        mutationDepth, wakePending = 0, false
        removeHooks()
        forgetKnown()
    end
    if categories then source.activate(categories) end
    return source
end
return M
