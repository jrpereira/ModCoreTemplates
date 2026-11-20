-- Event-driven lifecycle: no timers or periodic scans.
local Selectors = require('mc.selectors')
local ManagedTemplate = require('mc.managed_template')
local TemplateTargets = require('mc.template_targets')
local Objects = require('mc.objects')
local Widget = require('mc.widget')
local array = require('mc.util').array
local copy = require('mc.util').copy
local M = {}
-- MCT's signals, each with its opposite. A signal holds from when it fires
-- until its opposite fires; none holds before it first fires.
M.SIGNALS = {
    MC_PlayerReady='MC_PlayerUnready', MC_PlayerUnready='MC_PlayerReady',
    MC_CombatStart='MC_CombatEnd', MC_CombatEnd='MC_CombatStart',
}
-- The signals that end their opposite.
M.ENDS = {MC_PlayerUnready=true, MC_CombatEnd=true}
-- MCT's update events: game happenings delivered, with their data, to the awake
-- templates of the categories whose update hook names them. They hold no state.
M.UPDATES = {MC_NPCAttackIndicator=true}
-- Template events delivered by the runtime itself, once per template rather than
-- per attachment: wake starts the template's event intake, sleep ends it, and
-- update carries an update event.
M.TEMPLATE_EVENTS = {wake=true, sleep=true, update=true}
-- The signals at which the screen is read again (see screenMoved): moments that come
-- after the game's options can have changed the resolution, window or UI scale, and
-- before an attack can show.
M.SCREEN_CHECKS = {MC_PlayerReady=true, MC_CombatStart=true}
-- MCT's own event, published after a turn touches a layoutEvent category.
M.LAYOUT_EVENT = 'templates.layout.changed'
-- category.hooks names the signals that time its templates:
--   attach   new attachments wait until it holds
--   wake     templates are awake, receiving events, while it holds; defaults to attach
--   sleep    puts them to sleep when it fires; defaults to wake's opposite, if any
--   update   an update event (M.UPDATES) its awake templates receive as update
local function compileHooks(definition)
    local name, hooks = definition.id, definition.hooks
    assert(type(hooks) == 'table', name .. '.hooks must be a table')
    for key, signal in pairs(hooks) do
        assert(key == 'attach' or key == 'wake' or key == 'sleep' or key == 'update',
            name .. '.hooks: unknown hook ' .. tostring(key))
        local known = key == 'update' and M.UPDATES or M.SIGNALS
        assert(known[signal] ~= nil, name .. '.hooks.' .. key .. ': unknown signal ' .. tostring(signal))
    end
    local wake = hooks.wake or hooks.attach
    assert(hooks.sleep == nil or wake, name .. '.hooks.sleep requires wake or attach')
    assert(hooks.sleep == nil or hooks.sleep ~= wake, name .. '.hooks: sleep must differ from wake')
    return {attach=hooks.attach, wake=wake, sleep=hooks.sleep, update=hooks.update}
end
-- Overlay complete setting values by key; nested values are copied, not merged.
local function overlay(base, overrides)
    local result = copy(base)
    for key, value in pairs(overrides) do result[key] = copy(value) end
    return result
end
local function same(left, right)
    if type(left) ~= 'table' or type(right) ~= 'table' then return left == right end
    for key, value in pairs(left) do
        if not same(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end
local function keys(values)
    local result = {}
    for key in pairs(values) do result[#result + 1] = key end
    table.sort(result)
    return result
end
-- A template's priority when it declares none: after those that do.
M.DEFAULT_PRIORITY = 100
-- A waiting root settles at the latest this many attachDelays after it was first found.
M.ATTACH_DEADLINE = 3
-- The group of templates in a category of which at most one is enabled or attached,
-- from template.uniqueBy: 'category' (one per category), 'priority' (one per priority
-- within the category) or false/nil (no limit, returns nil).
function M.uniqueKey(template)
    local by = template.uniqueBy
    assert(by == nil or by == false or by == 'category' or by == 'priority',
        'template.uniqueBy must be false, category or priority: ' .. tostring(template.id))
    assert(template.priority == nil or type(template.priority) == 'number',
        'template.priority must be a number: ' .. tostring(template.id))
    if by == 'category' then return 'category' end
    if by == 'priority' then return 'priority:' .. (template.priority or M.DEFAULT_PRIORITY) end
end
-- Template ids by priority, lowest first, then by id: templates attach, wake,
-- sleep and receive events in this order.
local function ordered(records)
    local result = keys(records)
    table.sort(result, function(a, b)
        local left, right = records[a].priority, records[b].priority
        if left ~= right then return left < right end
        return a < b
    end)
    return result
end
local function sameTargets(left,right,host)
    if not left or not right then return false end
    for name,object in pairs(left) do
        local replacement=right[name]
        if not replacement or not host.valid(object) or not host.valid(replacement)
            or host.identity(object)~=host.identity(replacement) then return false end
    end
    for name in pairs(right) do if left[name]==nil then return false end end
    return true
end
local function retainsTargets(previous,current,host)
    if not previous then return true end
    for name in pairs(previous) do
        if not current or not current[name] or not host.valid(current[name]) then return false end
    end
    return true
end
local function targetsValid(targets,host)
    for _,object in pairs(targets or {}) do
        if not host.valid(object) then return false end
    end
    return true
end
local function targetNames(targets)
    local names={}
    for name in pairs(targets or {}) do names[name]=true end
    return names
end

-- options: defer(ms, callback), which runs callback later on the game thread. Without
-- defer, attachDelay is ignored. unavailable lists signals whose game hook could
-- not be registered.
function M.new(host, definitions, templates, state, options)
    options = options or {}
    local defer = options.defer
    -- awakeChanged(runtime) runs after templates wake or sleep, e.g. so an
    -- update source watches the game only while someone listens.
    local awakeChanged = options.awakeChanged
    -- layoutChanged(categoryIds) runs once at the end of a serialized turn that ran
    -- any template or shared-object callback, or revealed a root, in a category
    -- declaring layoutEvent=true; ids are sorted. Turns that touched none stay silent.
    local layoutChanged = options.layoutChanged
    -- Lifecycle decisions at TRACE; each subject logs only when its message changes.
    local log = host.log and require('mc_log').wrap(host.log) or nil
    local traced = {}
    -- Callers check this before building a trace message's parts.
    local function tracing() return log ~= nil and log.enabled('TRACE') end
    local function trace(subject, ...)
        if not tracing() then return end
        local parts = {}
        for index = 1, select('#', ...) do parts[index] = tostring((select(index, ...))) end
        local message = table.concat(parts)
        if traced[subject] == message then return end
        traced[subject] = message
        log.trace(subject, ': ', message)
    end
    assert(defer == nil or type(defer) == 'function', 'defer must be a function')
    assert(awakeChanged == nil or type(awakeChanged) == 'function', 'awakeChanged must be a function')
    assert(layoutChanged == nil or type(layoutChanged) == 'function', 'layoutChanged must be a function')
    for _, name in ipairs({'valid','identity','ready','matches','parent','find','watch','screen','subscribe','onError'}) do
        assert(type(host[name]) == 'function', 'host requires ' .. name)
    end
    assert(host.unwrap == nil or type(host.unwrap) == 'function', 'host.unwrap must be a function')
    -- No group has focus until ModCore Controls reports its Default wheel.
    state=state or {revision=0,controls={group={}}}
    local self = {epoch=1, phase='new', errors={},state=state}
    local categories, byId, candidates, queue = {}, {}, {}, {}
    local activeRoots, searchSignature = {}, nil
    local busy, unsubscribe = false, nil
    local failedInTurn = nil
    -- When each signal last fired, as an ordinal; the signal being handled, if any.
    local fired, firings, currentSignal = {}, 0, nil
    -- A signal that can never fire, or whose opposite can never fire, holds for
    -- good and its firings are ignored: categories timed by it degrade to always
    -- attached and awake rather than never, or never again.
    -- An end that can never fire simply never ends its opposite.
    local unavailable = {}
    for _, signal in ipairs(options.unavailable or {}) do
        assert(M.SIGNALS[signal] ~= nil, 'unknown signal: '..tostring(signal))
        if not M.ENDS[signal] then
            unavailable[signal] = true
            unavailable[M.SIGNALS[signal]] = true
        end
    end
    local function holds(signal)
        if unavailable[signal] then return true end
        local at = fired[signal]
        local opposite = M.SIGNALS[signal]
        local ended = opposite and fired[opposite] or nil
        return at ~= nil and (ended == nil or at > ended)
    end
    local function attachOpen(category)
        local hooks = category.hooks
        return not (hooks and hooks.attach) or holds(hooks.attach)
    end
    local function wakeOpen(category)
        local hooks = category.hooks
        if not (hooks and hooks.wake) then return true end
        if not holds(hooks.wake) then return false end
        local slept = hooks.sleep and fired[hooks.sleep]
        -- An unavailable wake holds without ever firing: only its opposite ends it.
        local woke = fired[hooks.wake]
        return slept == nil or woke == nil or slept < woke
    end
    local function managedRecord(definition, graph, targets, externallyCreated)
        local specs=TemplateTargets.compile(graph,targets)
        local created={}
        for _,name in ipairs(graph.order) do
            local selector=graph.byName[name]
            if selector.create and not (externallyCreated and externallyCreated[name]) then
                created[#created+1]={name=name,class=selector.class,from=selector.from,
                    parent=selector.parent,adopt=selector.adopt,
                    layout=selector.layout,
                    opacity=selector.opacity,brushColor=selector.brushColor,
                    prepass=selector.prepass,
                    adoptLayout=selector.adoptLayout,
                    adoptOpacity=selector.adoptOpacity}
            end
        end
        return ManagedTemplate.new(definition,specs,graph.order,created,
            {priority=definition.priority or M.DEFAULT_PRIORITY,id=definition.id})
    end
    for _, definition in ipairs(definitions) do
        assert(type(definition.id) == 'string' and not categories[definition.id], 'duplicate/invalid category')
        assert(definition.settings == nil or type(definition.settings) == 'table', 'category settings must be a table')
        local graph=Selectors.compile(definition.objects or {})
        local mandatory={}
        for _,name in ipairs(graph.order) do
            if graph.byName[name].required then mandatory[#mandatory+1]=name end
        end
        local category = {settings=copy(definition.settings or {}), graph=graph,
            requiredGraph=Selectors.project(graph,mandatory),
            templates={}, objects={}, id=definition.id}
        assert(definition.layoutEvent == nil or type(definition.layoutEvent) == 'boolean',
            definition.id..'.layoutEvent must be a boolean')
        category.layoutEvent = definition.layoutEvent == true
        if definition.sharedObjects ~= nil then
            assert(array(definition.sharedObjects,definition.id..'.sharedObjects')>0,
                definition.id..'.sharedObjects must not be empty')
            local sharedGraph=Selectors.project(graph,definition.sharedObjects)
            local sharedDefinition={id='@category:'..definition.id,attach=function(_,_,original)
                return original
            end}
            local sharedNames={}
            for _,name in ipairs(definition.sharedObjects) do sharedNames[name]=true end
            category.sharedNames=sharedNames
            category.shared={definition=sharedDefinition,graph=sharedGraph,
                targetTree=TemplateTargets.compile(graph,definition.sharedObjects),
                manager=managedRecord(sharedDefinition,sharedGraph,definition.sharedObjects),
                attached={},exposed={},category=category}
        end
        -- preview.lend: a module page's preview borrows the shared created object that
        -- adopts the category's targets, whole, with them inside (see self:lend).
        local preview = definition.preview
        assert(preview == nil or type(preview) == 'table', definition.id..'.preview must be a table')
        if preview and preview.lend ~= nil then
            assert(preview.lend == true, definition.id..'.preview.lend must be true')
            assert(category.shared, definition.id..'.preview.lend requires sharedObjects')
            local names = {}
            for _, name in ipairs(definition.sharedObjects) do
                local selector = graph.byName[name]
                if selector.create and selector.adopt then names[#names + 1] = name end
            end
            assert(#names == 1, definition.id..'.preview.lend requires exactly one shared created object that adopts targets')
            category.lendName = names[1]
        end
        -- attachDelay (ms): the game may create a root before filling its content.
        -- A newly found root attaches this long after the last reconcile reached it,
        -- and at most ATTACH_DEADLINE times this long after it was first found.
        if definition.attachDelay ~= nil then
            assert(type(definition.attachDelay) == 'number' and definition.attachDelay > 0,
                definition.id..'.attachDelay must be a positive number of milliseconds')
            category.attachDelay = {ms=definition.attachDelay, roots={}}
        end
        if definition.hooks ~= nil then category.hooks = compileHooks(definition) end
        categories[definition.id] = category
    end
    for _, template in ipairs(templates) do
        assert(type(template.id) == 'string' and template.id ~= '' and not byId[template.id], 'duplicate/invalid template id')
        local category = assert(categories[template.category], 'unknown template category')
        assert(template.settings == nil or type(template.settings) == 'table', 'template settings must be a table')
        local graph=Selectors.project(category.graph,template.objects)
        local targetTree,targetNames=TemplateTargets.compile(category.graph,template.objects)
        assert(#graph.order>0, 'template must declare objects: '..template.id)
        assert(template.managed == nil or type(template.managed) == 'boolean',
            'template.managed must be boolean')
        local managed=template.managed~=false
        local manager
        if managed then
            manager=managedRecord(template,graph,template.objects,category.sharedNames)
        else
            for _,name in ipairs(graph.order) do
                assert(not graph.byName[name].create
                    or (category.sharedNames and category.sharedNames[name]),
                    'created objects require managed template: '..template.id)
            end
            assert(type(template.attach) == 'function' and type(template.update) == 'function'
                and type(template.detach) == 'function', 'template requires attach, update and detach')
        end
        assert(template.priority == nil or type(template.priority) == 'number',
            'template.priority must be a number: '..template.id)
        assert(template.events == nil or type(template.events) == 'table',
            'template.events must be a table: '..template.id)
        for name in pairs(M.TEMPLATE_EVENTS) do
            local callback = template.events and template.events[name]
            assert(callback == nil or type(callback) == 'function',
                'template event callback must be a function: '..template.id..' '..name)
        end
        local sharedTargets={}
        for _,name in ipairs(targetNames) do
            if category.sharedNames and category.sharedNames[name] then sharedTargets[#sharedTargets+1]=name end
        end
        -- enabled: selected in the menu. awake: receiving events (see syncAwake).
        -- unique: at most one template per key in the category is enabled or attached.
        local record = {definition=template, enabled=false, awake=false, unique=M.uniqueKey(template),
            defaults=copy(template.settings or {}),
            overrides={}, settings={}, revision=0, attached={}, pending={}, waiting={},
            manager=manager, graph=graph,
            targetTree=targetTree,sharedTargets=sharedTargets,
            priority=template.priority or M.DEFAULT_PRIORITY, category=category}
        byId[template.id], category.templates[template.id] = record, record
    end
    -- Categories and templates are fixed from here, so their orders are computed once.
    local categoryOrder, templateOrder = keys(categories), ordered(byId)
    for _, category in pairs(categories) do category.order = ordered(category.templates) end
    local function report(stage, id, message)
        local error = {stage=stage, template=id, message=tostring(message)}
        self.errors[#self.errors + 1] = error
        -- A diagnostic failure must not break another template's lifecycle.
        pcall(host.onError, error)
    end
    -- Categories with layoutEvent whose widgets callbacks may have changed this turn.
    local touched = nil
    -- The viewport cannot change within one game-thread turn: its screen is read once.
    local turnScreen = nil
    local function touch(category)
        if touched and category and category.layoutEvent then touched[category.id] = true end
    end
    local function serialize(operation)
        queue[#queue + 1] = operation
        if busy then return end
        busy = true
        failedInTurn, touched, turnScreen = {}, {}, nil
        local index = 1
        while index <= #queue do
            local ok, why = pcall(queue[index])
            if not ok then report('runtime', nil, why) end
            index = index + 1
        end
        local changed = keys(touched)
        queue, busy, failedInTurn, touched, turnScreen = {}, false, nil, nil, nil
        if layoutChanged and #changed > 0 then
            local ok, why = pcall(layoutChanged, changed)
            if not ok then report('layout', nil, why) end
        end
    end
    -- A template whose effective settings did not change keeps its revision, so an
    -- Apply does not rebuild it.
    local function refreshSettings(category, record)
        local settings = overlay(category.settings, overlay(record.defaults, record.overrides))
        if same(settings, record.settings) then return end
        record.settings = settings
        record.definition.settings = copy(record.settings)
        record.revision = record.revision + 1
    end
    local function mutate(callback)
        if type(host.mutate) == 'function' then return host.mutate(callback) end
        return callback()
    end
    local function invoke(record, operation, object, settings, targets, oldScreen)
        settings = settings or record.settings
        touch(record.category)
        -- Publish the same effective values for callbacks using template.settings.
        record.definition.settings = copy(settings)
        local screen,named
        local ok, value, why = pcall(function() return mutate(function()
            -- Templates receive the underlying UObject only after a final validity check.
            if not host.valid(object) then return false, 'not_ready' end
            if operation == 'detach' then screen=oldScreen end
            if operation ~= 'detach' then
                screen = turnScreen or host.screen(object)
                if not screen then return false, 'not_ready' end
                if busy then turnScreen = screen end
            end
            local target = object
            if host.unwrap then target = host.unwrap(object) end
            if target == nil then return false, 'not_ready' end
            local params = {settings=copy(settings),screen=copy(screen),state=copy(state)}
            named=TemplateTargets.arrange(record.targetTree,targets,host.unwrap,host.valid)
            if record.manager then
                local dependencies={}
                for _,name in ipairs(record.graph.order) do
                    local value=targets[name]
                    if value and host.valid(value) then
                        dependencies[name]=host.unwrap and host.unwrap(value) or value
                    end
                end
                return record.manager[operation](record.manager,target,named,params,dependencies)
            end
            return record.definition[operation](target, params, named)
        end) end)
        record.definition.settings = copy(record.settings)
        if ok and value ~= false then return true, screen, named end
        if not (ok and type(why)=='string' and
            (why == 'not_ready' or why:match('^not_ready:'))) then
            report(operation, record.definition.id, ok and (why or 'callback returned false') or value)
        elseif tracing() then
            trace(record.definition.id, operation, ' not ready: ', why)
        end
        return false
    end
    -- Templates lay out from the screen they attached with. Reads the screen once and
    -- marks every attachment laid out for another width, height or scale, so the next
    -- reconcile updates it as a settings revision would. Returns the set of their
    -- categories. A lent category's templates are detached; the preview keeps its screen.
    local function sameScreen(left, right)
        return type(left) == 'table' and type(right) == 'table' and left.width == right.width
            and left.height == right.height and left.scale == right.scale
    end
    local function screenMoved()
        local moved = {}
        for _, categoryName in ipairs(categoryOrder) do
            for _, id in ipairs(categories[categoryName].order) do
                for token, attached in pairs(categories[categoryName].templates[id].attached) do
                    if not turnScreen and host.valid(attached.object) then
                        local ok, screen = pcall(mutate, function() return host.screen(attached.object) end)
                        if ok and type(screen) == 'table' then turnScreen = screen end
                    end
                    if turnScreen and not sameScreen(turnScreen, attached.screen) then
                        attached.resized, moved[categoryName] = true, true
                        if log then
                            log.debug(id, ' ', tostring(token), ': screen now ', turnScreen.width, 'x',
                                turnScreen.height, ' @', tostring(turnScreen.scale))
                        end
                    end
                end
            end
        end
        return moved
    end
    -- A selected template is awake while its category's wake hook holds. Waking
    -- and sleeping reach it as its wake and sleep events, called as
    -- callback(params, event) with no attachment objects. A failing callback is
    -- reported and still changes the state, so a later sleep can undo a partial wake.
    local function syncAwake(category)
        local open = self.phase == 'running' and wakeOpen(category)
        local changed = false
        for _, id in ipairs(category.order) do
            local record = category.templates[id]
            local wanted = record.enabled and open
            if wanted ~= record.awake then
                record.awake = wanted
                changed = true
                local name = wanted and 'wake' or 'sleep'
                trace(id, name, currentSignal and ' on '..currentSignal or '')
                local callback = record.definition.events and record.definition.events[name]
                if callback then
                    touch(category)
                    local ok, why = pcall(function() return mutate(function()
                        return callback({settings=copy(record.settings), state=copy(state)},
                            {name=name, signal=currentSignal})
                    end) end)
                    if not ok then report(name, id, why) end
                end
            end
        end
        if changed and awakeChanged then
            local ok, why = pcall(awakeChanged, self)
            if not ok then report('awake', nil, why) end
        end
    end
    -- Lending (category.preview.lend, see self:lend). The category's shared created
    -- canvas (category.lendName) moves whole into the preview, the adopted objects
    -- untouched in their slots inside it. category.lend holds the request and, once
    -- lent, active: weak handles for the shared root, the canvas and its HUD parent, the
    -- canvas's index and slot there, the preview attachment's manager and the preview's
    -- own state. While lent the canvas counts as lent, not lost: the shared attachment
    -- stands (nothing that validates it reads the canvas's parent), sharedWanted holds,
    -- and the adopted objects still resolve through the HUD's members. Nothing but weak
    -- handles is read across frames, except the attachment's targets, used only while
    -- its manager finds them all alive.
    local function raw(value) return host.unwrap and host.unwrap(value) or value end
    local function lendAlive(lend)
        local active = lend and lend.active
        if not active then return false end
        if not (Objects.get(active.root) and Objects.get(lend.destination)
            and Objects.get(active.canvas) and Objects.get(active.home)) then return false end
        return not active.manager or active.manager:live(active.key)
    end
    -- Detaches the preview attachment: restored while its targets live, else forgotten.
    local function lendDetach(active)
        local manager = active.manager
        active.manager, active.targets = nil, nil
        if not (manager and manager:hasState(active.key)) then return end
        local ok, detached, why = pcall(function() return mutate(function() return manager:detach(active.key) end) end)
        if not (ok and detached) then
            report('preview', active.template, ok and why or detached)
            pcall(manager.forget, manager, active.key)
        end
    end
    -- Moves the lent canvas back to its HUD parent, at its index, with its slot; if that
    -- parent is gone (a save load, a HUD rebuild), the canvas only leaves the preview.
    -- Dead objects are not touched.
    local function lendReturn(active)
        local canvas, home = Objects.get(active.canvas), Objects.get(active.home)
        if canvas then
            local ok, why = pcall(function() return mutate(function()
                local parent = Objects.parent(canvas)
                if not home then
                    if parent then assert(parent:RemoveChild(canvas) ~= false, 'lent canvas could not leave the preview') end
                    return
                end
                if Objects.same(parent, home) then return end
                if parent then assert(parent:RemoveChild(canvas) ~= false, 'lent canvas could not leave the preview') end
                local slot = home:AddChild(canvas)
                assert(Objects.valid(slot), 'lent canvas could not return')
                Widget.rememberSlot(canvas, slot)
                Widget.restoreSlot(canvas, active.slot)
                -- AddChild appends: the siblings that were after it move after it again,
                -- each keeping its slot.
                local after = {}
                for index = active.order, home:GetChildrenCount() - 2 do after[#after + 1] = home:GetChildAt(index) end
                for _, child in ipairs(after) do
                    local saved = Widget.snapshotSlot(child, true)
                    assert(home:RemoveChild(child) ~= false, 'could not reorder after the lent canvas')
                    local moved = home:AddChild(child)
                    assert(Objects.valid(moved), 'could not restore a sibling of the lent canvas')
                    Widget.rememberSlot(child, moved)
                    Widget.restoreSlot(child, saved)
                end
            end) end)
            if not ok then report('preview', active.template, why) end
        end
        Objects.release(active.canvas); Objects.release(active.home)
        active.canvas, active.home = nil, nil
    end
    -- Ends a category's lend: the preview attachment detaches, the lent canvas goes home,
    -- and the next reconcile attaches the applied templates again.
    -- After a preview hands the canvas back, the applied template lays out again; if it
    -- could not (its widgets not measured yet, 'not_ready'), it tries again every quarter
    -- second, one pending timer, until it has, at most RETRIES times. The game's pause
    -- menu shows the HUD, so this does not wait for play to resume.
    local RETRIES = 40
    local reconcile
    local function laidOut(category)
        for _, record in pairs(category.templates) do
            if record.enabled and not next(record.attached) then return false end
        end
        return true
    end
    local function redrawWhenPlaying(category)
        if not defer then return end
        if category.redrawPending then return end
        category.redrawTries = (category.redrawTries or 0) + 1
        if category.redrawTries > RETRIES then category.redrawTries = nil; return end
        category.redrawPending = true
        local ok = pcall(defer, 250, function()
            serialize(function()
                category.redrawPending = nil
                if self.phase ~= 'running' or category.lend or laidOut(category) then
                    category.redrawTries = nil; return
                end
                if log then log.debug(category.id, ': not laid out after the preview; trying again') end
                local done = pcall(reconcile, {category.id})
                if not done and log then log.warn(category.id, ': laying out again failed') end
                if laidOut(category) then category.redrawTries = nil
                else redrawWhenPlaying(category) end
            end)
        end)
        if not ok then category.redrawPending = nil end
    end
    local revealRoot
    local function endLend(category, why)
        local lend = category.lend
        if not lend then return end
        category.lend = nil
        lend.ended = why
        local active = lend.active
        if active then
            lendDetach(active)
            lendReturn(active)
            Objects.release(active.root)
            -- The root was settled before the lend: the applied template attaches again
            -- at once, not after another attachDelay. That delay is settled by a timer the
            -- game's pause menu can hold back, and the wheels then sat without a layout at
            -- the canvas origin (seen in game, 2026-11-16).
            if category.attachDelay and active.token then
                local rootState = category.attachDelay.roots[active.token]
                if type(rootState) == 'table' then revealRoot(rootState, category) end
                category.attachDelay.roots[active.token] = 'settled'
            end
        end
        Objects.release(lend.destination)
        -- The canvas is back without any template's layout: every template still recorded
        -- as attached lays out again on the next reconcile (seen in game: an applied bar
        -- left recorded as attached, its wheels at the canvas origin after the preview
        -- closed).
        for _, record in pairs(category.templates) do
            if next(record.attached) then record.revision = record.revision + 1 end
        end
        if log then log.debug(category.id, ': preview lend ended: ', tostring(why)) end
        redrawWhenPlaying(category)
    end
    -- Attaches the requested template to the lent objects, with params.preview, the
    -- request's screen and the preview's own state.
    local function lendAttach(category, lend)
        local active, request = lend.active, lend.request
        local record = category.templates[request.template]
        local root = Objects.get(active.root)
        if not root then return false, 'not_ready: lent root' end
        local _, _, bundles = Selectors.resolve(record.graph, candidates, host)
        local bundle
        for token, candidate in pairs(bundles) do
            if token == active.token then bundle = candidate end
        end
        if not bundle then return false, 'not_ready: lent targets' end
        local exposed = category.shared.exposed[active.token]
        for _, name in ipairs(record.sharedTargets) do bundle[name] = exposed and exposed[name] or nil end
        local settings = overlay(request.settings or category.settings,
            overlay(record.defaults, request.overrides or {}))
        -- The game's own screen unless the request names one: the lent widgets keep their
        -- HUD sizes, so the preview scales the whole screen down rather than laying them
        -- out on a smaller one (where they show too big).
        local screen = request.screen or active.gameScreen
        if not screen then return false, 'not_ready: screen' end
        local params = {settings=copy(settings), screen=copy(screen), state=copy(active.state), preview=true}
        local named = TemplateTargets.arrange(record.targetTree, bundle, host.unwrap, host.valid)
        local dependencies = {}
        for _, name in ipairs(record.graph.order) do
            local value = bundle[name]
            if value and host.valid(value) then dependencies[name] = raw(value) end
        end
        local manager = managedRecord(record.definition, record.graph, record.definition.objects, category.sharedNames)
        active.template, active.settings, active.screen = request.template, settings, copy(screen)
        local ok, attached, why = pcall(function() return mutate(function()
            return manager:attach(active.key, named, params, dependencies)
        end) end)
        if not (ok and attached) then
            pcall(manager.forget, manager, active.key)
            return false, ok and why or attached
        end
        active.manager, active.targets = manager, named
        return true
    end
    -- Fills a panel slot: a canvas slot anchored to every edge, else padding 0 and Fill.
    local function fillSlot(slot)
        local canvas = pcall(function()
            slot:SetLayout({Offsets={Left=0,Top=0,Right=0,Bottom=0},
                Anchors={Minimum={X=0,Y=0},Maximum={X=1,Y=1}}, Alignment={X=0,Y=0}})
            slot:SetAutoSize(false)
        end)
        if canvas then return end
        slot:SetPadding({Left=0,Top=0,Right=0,Bottom=0})
        slot:SetHorizontalAlignment(0)
        slot:SetVerticalAlignment(0)
    end
    -- Moves the shared attachment's created canvas at token, with the objects it adopted
    -- still inside, from its HUD parent into the request's destination, filling it, then
    -- attaches. Its parent, index and slot are kept to return it exactly.
    local function lendMove(category, lend, token)
        local destination = Objects.get(lend.destination)
        if not destination then return false, 'preview panel gone' end
        local shared = category.shared
        local attached = shared.attached[token]
        if not (attached and host.valid(attached.object) and shared.manager:live(attached.root)) then
            return false, 'not_ready: '..category.id
        end
        local exposed = shared.exposed[token]
        local canvas = exposed and exposed[category.lendName]
        canvas = canvas and raw(canvas)
        if not Objects.valid(canvas) then return false, 'not_ready: '..category.lendName end
        local home = Objects.parent(canvas)
        if not home then return false, 'not_ready: '..category.lendName..' parent' end
        local order
        for index = 0, home:GetChildrenCount() - 1 do
            if Objects.same(home:GetChildAt(index), canvas) then order = index end
        end
        if not order then return false, category.lendName..' is not a child of its parent' end
        local root = attached.object
        local active = {token=token, root=Objects.hold(raw(root)), canvas=Objects.hold(canvas),
            home=Objects.hold(home), order=order, slot=Widget.snapshotSlot(canvas), key={},
            state=copy(state), template=lend.request.template, gameScreen=host.screen(root)}
        lend.active = active
        if not (active.root and active.canvas and active.home) then return false, 'lent canvas cannot be kept' end
        local ok, why = pcall(function() return mutate(function()
            assert(home:RemoveChild(canvas) ~= false, category.lendName .. ' could not be detached')
            local slot = destination:AddChild(canvas)
            assert(Objects.valid(slot), category.lendName .. ' could not be lent')
            Widget.rememberSlot(canvas, slot)
            fillSlot(slot)
        end) end)
        if not ok then return false, why end
        return lendAttach(category, lend)
    end
    -- A template that is not ready on the canvas just lent (its widgets not measured in
    -- their new parent until the next frame: seen in game, 2026-11-16, as 'not_ready: key
    -- layout') attaches again a tenth of a second later, one pending timer, at most
    -- LEND_RETRIES times, the canvas staying lent meanwhile. Returns whether one is pending.
    local LEND_RETRIES = 20
    local function attachLater(category, lend)
        if not defer or not lend.active then return false end
        if lend.retryPending then return true end
        lend.tries = (lend.tries or 0) + 1
        if lend.tries > LEND_RETRIES then return false end
        lend.retryPending = true
        local ok = pcall(defer, 100, function()
            serialize(function()
                lend.retryPending = nil
                if category.lend ~= lend or not lend.active or self.phase ~= 'running' then return end
                if not lendAlive(lend) then
                    endLend(category, 'lent objects gone'); reconcile({category.id}); return
                end
                lendDetach(lend.active)
                local done, attached, why = pcall(lendAttach, category, lend)
                if done and attached then lend.tries = nil; return end
                why = tostring(done and why or attached)
                if why:match('^not_ready') and attachLater(category, lend) then return end
                if not why:match('^not_ready') then report('preview', lend.request.template, why) end
                if log then log.debug(category.id, ': preview attach gave up: ', why) end
                endLend(category, why); reconcile({category.id})
            end)
        end)
        if not ok then lend.retryPending = nil end
        return ok
    end
    -- Restores a root hidden while its attachDelay ran; a dead root is not touched.
    function revealRoot(rootState, category)
        if type(rootState)~='table' or not rootState.hidden then return end
        touch(category)
        local live=Objects.get(rootState.hidden)
        if live then pcall(function() live:SetRenderOpacity(rootState.opacity) end) end
        Objects.release(rootState.hidden)
        rootState.hidden=nil
    end
    local function include(object)
        if not host.valid(object) then return end
        for _, selector in ipairs(activeRoots) do
            if host.matches(object, selector) then
                local id = host.identity(object)
                assert(type(id) == 'string', 'host identity must be a generation-safe string')
                candidates[id] = object
                return
            end
        end
    end
    local function discover()
        for _, selector in ipairs(activeRoots) do
            -- Host enumeration returns live candidates, including those not yet ready.
            for _, object in ipairs(host.find(selector)) do include(object) end
        end
    end
    local function hasEnabledTemplate(category)
        for _,record in pairs(category.templates) do
            if record.enabled then return true end
        end
        return false
    end
    -- An enabled template attaches unless its category is lent to a preview; the
    -- category's shared objects stay attached while either holds.
    local function attachable(record)
        return record.enabled and not record.category.lend
    end
    local function sharedWanted(category)
        return category.lend ~= nil or hasEnabledTemplate(category)
    end
    local function refreshDiscovery()
        local roots,seen,identities={},{},{}
        for _,categoryName in ipairs(categoryOrder) do
            local category=categories[categoryName]
            local function add(graph)
                for _,name in ipairs(graph.order) do
                    local selector=graph.byName[name]
                    if not selector.from then
                        local key=(selector.object and 'object:' or 'class:')
                            ..(selector.object or selector.class)
                        if not seen[key] then
                            seen[key]=true
                            roots[#roots+1]=selector
                            identities[#identities+1]=key
                        end
                    end
                end
            end
            add(category.requiredGraph)
            if category.shared and sharedWanted(category) then add(category.shared.graph) end
            for _,id in ipairs(category.order) do
                local record=category.templates[id]
                if record.enabled or category.lend and category.lend.request.template==id then add(record.graph) end
            end
        end
        table.sort(identities)
        local signature=table.concat(identities,'\0')
        if signature==searchSignature then return end
        searchSignature,activeRoots,candidates=signature,roots,{}
        host.watch(roots)
        discover()
    end
    -- names limits the pass to those categories, in order; all of them when nil.
    function reconcile(names)
        for id, object in pairs(candidates) do
            if not host.valid(object) then candidates[id] = nil end
        end
        for _, name in ipairs(names or categoryOrder) do
            local category = categories[name]
            local resolved,allObjects={},{}
            -- A lend whose objects died (a save load, a HUD rebuild) or whose preview
            -- went ends here, before anything reads them.
            if category.lend and category.lend.active and not lendAlive(category.lend) then
                endLend(category,'lent objects gone')
            end
            local function exposeSharedTargets(record,bundles,sharedAttached)
                for token,bundle in pairs(bundles or {}) do
                    local attached=sharedAttached and sharedAttached[token]
                    for _,targetName in ipairs(record.sharedTargets) do
                        bundle[targetName]=attached and attached[targetName] or nil
                    end
                end
            end
            -- Whether a root's attachDelay has passed. A root waits until no reconcile
            -- has reached it for delay.ms; each one restarts its timer, up to a deadline of
            -- DEADLINE times the delay from first sighting. Once settled, a root attaches
            -- without waiting, so a later menu selection does not wait.
            -- While it waits the root is hidden, so its unfinished native content never
            -- shows; it is revealed in the same game-thread call that attaches it.
            local settledThisTurn={}
            local function settledFor(token,object)
                local delay=category.attachDelay
                if not delay or not defer then return true end
                local rootState=delay.roots[token]
                if rootState=='settled' then return true end
                if settledThisTurn[token]~=nil then return settledThisTurn[token] end
                settledThisTurn[token]=false
                if not rootState then
                    rootState={generation=0}
                    local live=host.unwrap and host.unwrap(object) or object
                    local ok,opacity=pcall(function() return live:GetRenderOpacity() end)
                    local handle=ok and tonumber(opacity) and Objects.hold(live)
                    if handle and pcall(function() live:SetRenderOpacity(0) end) then
                        rootState.hidden,rootState.opacity=handle,tonumber(opacity)
                    elseif handle then Objects.release(handle) end
                end
                -- Settles the root when it fires, unless the root is gone or settled, or
                -- a later reconcile restarted its timer (generation; nil for the deadline).
                local function settleAfter(ms,generation)
                    return pcall(defer,ms,function()
                        -- Reveal inside a turn, so the reveal publishes the layout event.
                        serialize(function()
                            if delay.roots[token]~=rootState
                                or generation and rootState.generation~=generation then return end
                            delay.roots[token]='settled'
                            if tracing() then trace(category.id..' '..tostring(token),'attachDelay settled') end
                            revealRoot(rootState,category)
                            if self.phase=='running' then reconcile() end
                        end)
                    end)
                end
                local ok,why=true,nil
                if rootState.generation==0 then ok,why=settleAfter(delay.ms*M.ATTACH_DEADLINE) end
                rootState.generation=rootState.generation+1
                delay.roots[token]=rootState
                if ok then ok,why=settleAfter(delay.ms,rootState.generation) end
                if not ok then
                    delay.roots[token],settledThisTurn[token]='settled',true
                    revealRoot(rootState,category)
                    report('attach delay',nil,why)
                    return true
                end
                return false
            end
            local _,requiredObjects=Selectors.resolve(category.requiredGraph,candidates,host)
            for token,object in pairs(requiredObjects) do allObjects[token]=object end
            if category.attachDelay then
                -- Forget roots that are gone; a pending delay for one then does nothing.
                for token,rootState in pairs(category.attachDelay.roots) do
                    if not candidates[token] then
                        category.attachDelay.roots[token]=nil
                        revealRoot(rootState,category)
                    end
                end
            end
            local shared,sharedObjects,sharedBundles=category.shared,{},{ }
            local sharedActive=shared and sharedWanted(category)
            if sharedActive then
                local _,objects,bundles=Selectors.resolve(shared.graph,candidates,host)
                sharedObjects,sharedBundles=objects,bundles
                for token,object in pairs(objects) do allObjects[token]=object end
            end
            for _,id in ipairs(category.order) do
                local record=category.templates[id]
                if attachable(record) then
                    local _,objects,bundles=Selectors.resolve(record.graph,candidates,host)
                    -- A managed template may reparent its own targets. Keep those valid
                    -- targets in the resolved bundle until the manager detaches
                    -- them, including reconciliations without a settings change.
                    for token,attached in pairs(record.attached) do
                        if record.manager and record.manager:hasState(attached.root)
                            and objects[token] and host.identity(objects[token]) == host.identity(attached.object)
                            and targetsValid(attached.targets,host) then
                            for targetName,target in pairs(attached.targets) do
                                if bundles[token][targetName] == nil then
                                    bundles[token][targetName] = target
                                end
                            end
                        end
                    end
                    resolved[id]={objects=objects,bundles=bundles}
                    if tracing() then
                        local found,known=0,0
                        for _ in pairs(objects) do found=found+1 end
                        for _ in pairs(candidates) do known=known+1 end
                        trace(id,'enabled, ',found,' root(s) resolved from ',known,' candidate(s)')
                    end
                    for token,object in pairs(objects) do allObjects[token]=object end
                else
                    trace(id,'not enabled')
                end
            end
            category.objects = allObjects
            if shared then
                for id,record in pairs(category.templates) do
                    if resolved[id] then
                        exposeSharedTargets(record,resolved[id].bundles,shared.exposed)
                    end
                end
            end
            -- Detach all outgoing templates before any incoming template attaches.
            for _, id in ipairs(category.order) do
                local record = category.templates[id]
                local objects=resolved[id] and resolved[id].objects or {}
                local bundles=resolved[id] and resolved[id].bundles or {}
                for _, token in ipairs(keys(record.pending)) do
                    local pending=record.pending[token]
                    touch(category)
                    local ok,why=pcall(function() return mutate(function()
                        if host.valid(pending.object) and targetsValid(pending.targets,host) then
                            assert(record.manager:detach(pending.root))
                        else
                            record.manager:forget(pending.root)
                        end
                    end) end)
                    if ok then record.pending[token]=nil
                    else
                        failedInTurn[record]=failedInTurn[record] or {}
                        failedInTurn[record][token]=true
                        report('rollback',record.definition.id,why)
                    end
                end
                for _, token in ipairs(keys(record.attached)) do
                    local attached = record.attached[token]
                    if not host.valid(attached.object) or not targetsValid(attached.targets,host) then
                        if attachable(record) and host.valid(attached.object)
                            and objects[token] and host.ready(attached.object)
                            and not retainsTargets(attached.targets,bundles[token],host) then
                            record.waiting[token]=targetNames(attached.targets)
                        end
                        if record.manager then
                            local ok,why=pcall(record.manager.forget,record.manager,attached.root)
                            if not ok then report('forget',record.definition.id,why)
                            else record.attached[token]=nil end
                        else record.attached[token]=nil end
                    elseif not attachable(record) or not objects[token] or not host.ready(attached.object)
                        or not sameTargets(attached.targets,bundles[token],host) then
                        if attachable(record) and objects[token] and host.ready(attached.object)
                            and not retainsTargets(attached.targets,bundles[token],host) then
                            record.waiting[token]=targetNames(attached.targets)
                        end
                        local failures = failedInTurn[record] or {}
                        failedInTurn[record] = failures
                        if not failures[token] then
                            if invoke(record, 'detach', attached.object, attached.settings,
                                attached.targets,attached.screen) then
                                record.attached[token] = nil
                            else failures[token] = true end
                        end
                    end
                end
            end
            -- Shared category objects are restored only after every template has
            -- detached, and prepared before any incoming template can attach.
            if shared then
                for _,token in ipairs(keys(shared.attached)) do
                    local attached=shared.attached[token]
                    local current=sharedObjects[token]
                    if not sharedActive or not host.valid(attached.object)
                        or not current or not host.ready(current)
                        or not sameTargets(attached.targets,sharedBundles[token],host) then
                        -- Nothing above reads the created canvas's parent, so a lent canvas
                        -- (in the preview) keeps the shared attachment standing; when it does
                        -- go, the canvas goes home before the shared objects release it.
                        if category.lend and category.lend.active and category.lend.active.token==token then
                            endLend(category,'shared objects detached')
                        end
                        if host.valid(attached.object) and targetsValid(attached.targets,host) then
                            if invoke(shared,'detach',attached.object,nil,attached.targets,attached.screen) then
                                shared.attached[token]=nil
                                shared.exposed[token]=nil
                            end
                        else
                            local ok,why=pcall(shared.manager.forget,shared.manager,attached.root)
                            if not ok then report('forget',shared.definition.id,why)
                            else shared.attached[token]=nil;shared.exposed[token]=nil end
                        end
                    end
                end
                if sharedActive then
                    for _,token in ipairs(keys(sharedObjects)) do
                        local object=sharedObjects[token]
                        if not shared.attached[token] and host.valid(object) and host.ready(object)
                            and attachOpen(category) and settledFor(token,object) then
                            local targets=sharedBundles[token]
                            local applied,screen,exposed=invoke(shared,'attach',object,nil,targets)
                            if applied and host.valid(object) then
                                shared.attached[token]={object=object,targets=targets,
                                    root=host.unwrap and host.unwrap(object) or object,screen=screen}
                                shared.exposed[token]=exposed
                            end
                        end
                    end
                end
            end
            if shared then
                for id,record in pairs(category.templates) do
                    if resolved[id] then
                        exposeSharedTargets(record,resolved[id].bundles,shared.exposed)
                    end
                end
            end
            -- A requested lend takes the shared objects once they are attached. If it
            -- cannot, it ends, and the applied templates attach again below.
            local lend=category.lend
            if lend and not lend.active then
                local token=keys(shared.attached)[1]
                local ok,lent,why=true,false,'nothing to lend: '..category.id..' is not in the game'
                if token then ok,lent,why=pcall(lendMove,category,lend,token) end
                local failed=not (ok and lent) and tostring(ok and why or lent)
                -- Lent but not ready: the canvas stays in the preview and attaches again.
                if failed and lend.active and failed:match('^not_ready') and attachLater(category,lend) then
                    if log then log.debug(category.id,': preview waits: ',failed) end
                    failed=false
                end
                if failed then
                    lend.failed=failed
                    if token and not lend.failed:match('^not_ready') then
                        report('preview',lend.request.template,lend.failed)
                    end
                    endLend(category,lend.failed)
                end
            end
            -- Outgoing templates sleep after they detach; incoming ones wake
            -- before they attach.
            syncAwake(category)
            for _, id in ipairs(category.order) do
                local record = category.templates[id]
                if attachable(record) then
                    -- Not resolved above while a lend was pending.
                    if not resolved[id] then
                        local _,objects,bundles=Selectors.resolve(record.graph,candidates,host)
                        resolved[id]={objects=objects,bundles=bundles}
                        if shared then exposeSharedTargets(record,bundles,shared.exposed) end
                    end
                    local objects,bundles=resolved[id].objects,resolved[id].bundles
                    for _, token in ipairs(keys(objects)) do
                        local object, blocked = objects[token], false
                        -- A unique template attaches only after every other template with its
                        -- key has detached; a failed detach blocks the replacement.
                        if record.unique then
                            for otherId, other in pairs(category.templates) do
                                if otherId ~= id and other.unique == record.unique
                                    and (other.attached[token] or other.pending[token]) then
                                    blocked = true
                                end
                            end
                        end
                        local old = record.attached[token]
                        if old and tracing() then
                            trace(id..' '..tostring(token),'recorded attached at revision ',tostring(old.revision),
                                ' (now ',tostring(record.revision),')',record.pending[token] and ', detach pending' or '',
                                blocked and ', blocked' or '',shared and not shared.attached[token] and ', shared objects not attached' or '',
                                not retainsTargets(record.waiting[token],bundles[token],host) and ', waiting for targets' or '',
                                failedInTurn[record] and failedInTurn[record][token] and ', failed this turn' or '')
                        end
                        if not old and tracing() then
                            local why={}
                            if blocked then why[#why+1]='blocked by another template' end
                            if record.pending[token] then why[#why+1]='detach pending' end
                            if not attachOpen(category) then
                                why[#why+1]='waiting for '..category.hooks.attach
                            end
                            if not host.valid(object) then why[#why+1]='root invalid'
                            elseif not host.ready(object) then why[#why+1]='root not ready' end
                            if shared and not shared.attached[token] then why[#why+1]='shared objects not attached' end
                            if not retainsTargets(record.waiting[token],bundles[token],host) then
                                why[#why+1]='waiting for targets'
                            end
                            if failedInTurn[record] and failedInTurn[record][token] then why[#why+1]='failed this turn' end
                            local delayed=category.attachDelay and defer and category.attachDelay.roots[token]
                            if category.attachDelay and defer and delayed~='settled' then
                                why[#why+1]='waiting for attachDelay'
                            end
                            trace(id..' '..tostring(token),#why>0 and table.concat(why,', ') or 'attaching')
                        end
                        if not blocked and not record.pending[token]
                            and host.valid(object) and host.ready(object)
                            and (not shared or shared.attached[token])
                            and retainsTargets(record.waiting[token],bundles[token],host)
                            and (not old or old.revision ~= record.revision or old.resized)
                            and not (failedInTurn[record] and failedInTurn[record][token])
                            and (old or (attachOpen(category) and settledFor(token,object))) then
                            local operation = old and 'update' or 'attach'
                            local targets = bundles[token]
                            local applied,screen=invoke(record, operation, object, nil, targets)
                            if applied and host.valid(object) then
                                record.waiting[token]=nil
                                record.attached[token] = {object=object, revision=record.revision,
                                    settings=copy(record.settings), targets=targets,
                                    root=host.unwrap and host.unwrap(object) or object,screen=screen}
                            else
                                if not old and record.manager then
                                    local root=host.unwrap and host.unwrap(object) or object
                                    if root and record.manager:hasState(root) then
                                        record.pending[token]={object=object,root=root,targets=targets}
                                    end
                                end
                                local failures = failedInTurn[record] or {}
                                failedInTurn[record] = failures
                                failures[token] = record.revision
                            end
                        end
                    end
                end
            end
        end
    end
    -- Validates, then applies, each named category's template selections and, when
    -- given, its values; one reconcile follows. refused: the error outside new/running.
    local function applySelections(changes, refused)
        assert(self.phase == 'new' or self.phase == 'running', refused)
        local pending = {}
        for name, change in pairs(changes) do
            local category = assert(categories[name], 'unknown category')
            assert((change.settings == nil or type(change.settings) == 'table')
                and type(change.selections) == 'table', 'invalid category commit')
            local unique = {}
            for id, settings in pairs(change.selections) do
                assert(category.templates[id] and type(settings) == 'table', 'invalid template selection')
                local key = category.templates[id].unique
                assert(not key or not unique[key], 'a category accepts at most one template per uniqueBy group')
                if key then unique[key] = true end
            end
            pending[name] = copy(change)
        end
        serialize(function()
            for name, change in pairs(pending) do
                local category = categories[name]
                if change.settings then category.settings = change.settings end
                for id, record in pairs(category.templates) do
                    record.enabled = change.selections[id] ~= nil
                    if not record.enabled then record.waiting={} end
                    if record.enabled then
                        record.overrides = change.selections[id]
                        refreshSettings(category, record)
                    end
                end
            end
            if next(pending) and self.phase == 'running' then
                refreshDiscovery(); reconcile()
            end
        end)
    end
    -- Selects one category's templates, keeping its values.
    function self:select(categoryName, selections)
        if log and type(selections) == 'table' then
            local count = 0
            for _ in pairs(selections) do count = count + 1 end
            log.debug(categoryName, ': ', count, ' template(s) selected')
        end
        applySelections({[categoryName]={selections=selections}}, 'runtime is not accepting selections')
    end
    function self:setCategorySettings(categoryName, settings)
        assert(self.phase == 'new' or self.phase == 'running', 'runtime is not accepting settings')
        local category = assert(categories[categoryName], 'unknown category')
        assert(type(settings) == 'table', 'category settings must be a table')
        local committed = copy(settings)
        serialize(function()
            category.settings = committed
            for _, record in pairs(category.templates) do
                if record.enabled then refreshSettings(category, record) end
            end
            if self.phase == 'running' then reconcile() end
        end)
    end
    -- State changes never rebuild templates. Event callbacks run once per live
    -- attachment as callback(params, event, objects) and adjust it in place;
    -- params matches attach's, and later attaches read params.state.
    function self:stateChanged(event)
        assert(self.phase=='new' or self.phase=='running','runtime is not accepting state changes')
        assert(event==nil or type(event)=='table' and type(event.name)=='string',
            'invalid template event')
        serialize(function()
            for _,id in ipairs(templateOrder) do
                local record=byId[id]
                local callback=record.awake and event and not M.TEMPLATE_EVENTS[event.name]
                    and record.definition.events
                    and record.definition.events[event.name]
                if callback then
                    for _,token in ipairs(keys(record.attached)) do
                        local attached=record.attached[token]
                        local ok,why=pcall(function() return mutate(function()
                            if not (host.valid(attached.object) and targetsValid(attached.targets,host)) then
                                return
                            end
                            -- A callback answering MCT's own layout event must not
                            -- publish another, or the two would feed each other.
                            if event.name~=M.LAYOUT_EVENT then touch(record.category) end
                            local params={settings=copy(attached.settings),screen=attached.screen,
                                state=copy(state)}
                            return callback(params,copy(event),TemplateTargets.arrange(record.targetTree,
                                attached.targets,host.unwrap,host.valid))
                        end) end)
                        if not ok then report('event',id,why) end
                    end
                end
            end
        end)
    end
    -- Records an MCT signal (M.SIGNALS) and reconciles the categories whose hooks
    -- name it or its opposite, so they attach, wake or sleep their templates. The
    -- others cannot change on it and are left alone: a full pass costs a frame.
    function self:signal(name)
        assert(M.SIGNALS[name] ~= nil, 'unknown signal: '..tostring(name))
        if unavailable[name] then return end
        serialize(function()
            firings = firings + 1
            fired[name] = firings
            if log then log.debug('signal ', name) end
            if self.phase ~= 'running' then return end
            local resized = M.SCREEN_CHECKS[name] and screenMoved() or {}
            local affected = {}
            for _, categoryName in ipairs(categoryOrder) do
                local hooks = categories[categoryName].hooks
                if resized[categoryName] then
                    affected[#affected + 1] = categoryName
                elseif hooks then
                    for _, hook in ipairs({hooks.attach or false, hooks.wake or false, hooks.sleep or false}) do
                        if hook == name or hook == M.SIGNALS[name] then
                            affected[#affected + 1] = categoryName
                            break
                        end
                    end
                end
            end
            if #affected == 0 then return end
            currentSignal = name
            local ok, why = pcall(reconcile, affected)
            currentSignal = nil
            if not ok then error(why, 0) end
        end)
    end
    -- Ends every pending attachDelay at once, e.g. when the loading screen has lifted.
    function self:settle()
        serialize(function()
            local pending=false
            for _,category in pairs(categories) do
                if category.attachDelay then
                    for token,rootState in pairs(category.attachDelay.roots) do
                        if type(rootState)=='table' then
                            category.attachDelay.roots[token]='settled'
                            revealRoot(rootState,category)
                            pending=true
                        end
                    end
                end
            end
            if pending and self.phase=='running' then
                reconcile()
            end
        end)
    end
    -- Menu commits category values and template selections together, then reconciles once.
    function self:commit(changes)
        for _, change in pairs(changes) do
            assert(type(change) == 'table' and type(change.settings) == 'table', 'invalid category commit')
        end
        applySelections(changes, 'runtime is not accepting commits')
    end
    -- The object source reports only changes; a destroyed object fails validity and
    -- is dropped at the next reconcile.
    function self:event(event)
        assert(type(event) == 'table', 'lifecycle event required')
        local kind, object, objects, epoch = event.kind, event.object, event.objects, event.epoch
        assert(kind == 'changed', 'unknown lifecycle event')
        assert(type(epoch) == 'number', 'event must carry the epoch captured before queuing')
        assert(objects == nil or type(objects) == 'table', 'event objects must be a list')
        serialize(function()
            if self.phase ~= 'running' or epoch ~= self.epoch then return end
            -- A batched event (objects) costs one reconcile for all of its objects.
            include(object)
            for _, other in ipairs(objects or {}) do include(other) end
            reconcile()
        end)
    end
    function self:start()
        assert(self.phase == 'new', 'runtime already started')
        -- Subscription precedes the snapshot. Events during subscription are queued.
        serialize(function()
            self.phase = 'running'
            local ok, why = pcall(function()
                unsubscribe = host.subscribe(function(event) self:event(event) end,
                    function() return self.epoch end)
                assert(type(unsubscribe) == 'function', 'host.subscribe must return unsubscribe')
                refreshDiscovery()
                -- Drain notifications captured during subscription/snapshot before attaching.
                queue[#queue + 1] = function()
                    if self.phase == 'running' then reconcile() end
                end
            end)
            if not ok then
                self.phase = 'failed'
                if type(unsubscribe) == 'function' then
                    local removed,result,detail=pcall(unsubscribe)
                    if removed and result~=false then unsubscribe=nil
                    else report('unsubscribe',nil,removed and detail or result) end
                end
                candidates = {}
                error(why)
            end
        end)
    end
    function self:stop()
        local failures={}
        local function failed(stage,why)
            failures[#failures+1]=stage..': '..tostring(why)
            report(stage,nil,why)
        end
        serialize(function()
            self.phase = 'stopped'
            if unsubscribe then
                local ok,result,detail = pcall(unsubscribe)
                if ok and result~=false then unsubscribe=nil
                else failed('unsubscribe',ok and detail or result) end
            end
            for _, record in pairs(byId) do record.enabled = false; record.waiting={} end
            for _, category in pairs(categories) do
                if category.lend then endLend(category,'runtime stopped') end
            end
            local reconciled,why=pcall(reconcile)
            if not reconciled then failed('reconcile',why) end
            local watched,result,detail=pcall(host.watch,{})
            if not watched or result==false then failed('watch',watched and detail or result) end
            candidates,activeRoots,searchSignature = {},{},nil
            for _,category in pairs(categories) do
                if category.attachDelay then
                    for _,rootState in pairs(category.attachDelay.roots) do revealRoot(rootState,category) end
                    category.attachDelay.roots={}
                end
            end
        end)
        if #failures>0 then return false,table.concat(failures,'; ') end
        return true
    end
    function self:awake(id)
        return assert(byId[id], 'unknown template').awake
    end
    -- Whether any awake template's category takes an update event, so its
    -- source need only watch the game while one does.
    function self:listening(name)
        assert(M.UPDATES[name] ~= nil, 'unknown update event: '..tostring(name))
        for _, category in pairs(categories) do
            if category.hooks and category.hooks.update == name then
                for _, record in pairs(category.templates) do
                    if record.awake then return true end
                end
            end
        end
        return false
    end
    -- Delivers an update event to the awake templates whose category takes it,
    -- as update(params, event) with params.settings, at once and in the caller's
    -- frame: a source inside a game call keeps that call's timing. The event
    -- may carry live objects valid only during the call; settings are the
    -- template's own, not copies. A failing template is reported and the rest
    -- still receive it.
    function self:emit(name, event)
        assert(M.UPDATES[name] ~= nil, 'unknown update event: '..tostring(name))
        assert(type(event) == 'table', 'update event data must be a table')
        if self.phase ~= 'running' then return end
        event.name, event.signal = 'update', name
        for _, categoryName in ipairs(categoryOrder) do
            local category = categories[categoryName]
            if category.hooks and category.hooks.update == name then
                for _, id in ipairs(category.order) do
                    local record = category.templates[id]
                    local callback = record.awake and record.definition.events
                        and record.definition.events.update
                    if callback then
                        local ok, why = pcall(callback, {settings=record.settings, state=state}, event)
                        if not ok then report('update', id, why) end
                    end
                end
            end
        end
    end
    -- Lends a category declaring preview.lend to a module page's preview. request:
    --   destination  a panel in the preview, the game's screen in size, that takes the
    --                lent canvas (a SizeBox; the canvas fills it)
    --   template     the id of the template to show, which declares preview={...}
    --   settings     the category's effective settings at the page's values (optional)
    --   overrides    the template's own values at the page's values (optional)
    --   screen       the preview's screen, as host.screen describes the game's; the
    --                game's own screen when omitted
    -- The category's applied templates detach through their normal path, its shared
    -- objects attach if they were not, the shared created canvas moves whole from its HUD
    -- parent into destination, the objects it adopted untouched inside, and the template
    -- attaches to them with params.preview, the screen and a copy of the state. Again
    -- with the same destination, only the preview attachment is replaced. A nil request
    -- ends the lend: the preview attachment detaches, the canvas returns to its HUD
    -- parent, index and slot, and the applied templates attach again. A lend that cannot
    -- be made or fails, or whose objects die (see reconcile), ends the same way; with its
    -- HUD gone the canvas only leaves the preview. Returns true, or false and why.
    function self:lend(categoryName, request)
        local category = assert(categories[categoryName], 'unknown category')
        assert(category.lendName, categoryName .. ' does not lend to previews')
        if request ~= nil then
            assert(type(request) == 'table' and (request.screen == nil or type(request.screen) == 'table'),
                'invalid lend request')
            local record = category.templates[request.template]
            assert(record and record.manager and type(record.definition.preview) == 'table',
                'template does not preview: ' .. tostring(request.template))
        end
        local done, why = false, 'queued behind a running turn'
        serialize(function()
            local lend = category.lend
            if request == nil then
                if lend then
                    endLend(category, 'closed')
                    if self.phase == 'running' then reconcile({categoryName}) end
                end
                done, why = true, nil
                return
            end
            if lend and lend.active and lendAlive(lend)
                and Objects.same(Objects.get(lend.destination), request.destination) then
                lendDetach(lend.active)
                lend.request = request
                local ok, attached, reason = pcall(lendAttach, category, lend)
                if ok and attached then done, why = true, nil; return end
                why = tostring(ok and reason or attached)
                lend.tries = nil
                if why:match('^not_ready') and attachLater(category, lend) then done, why = true, nil; return end
                if not why:match('^not_ready') then report('preview', request.template, why) end
                endLend(category, why)
                reconcile({categoryName})
                return
            end
            if lend then endLend(category, 'replaced') end
            if self.phase ~= 'running' then
                if lend then reconcile({categoryName}) end
                why = 'runtime is not running'
                return
            end
            local destination, reason = Objects.hold(request.destination)
            if not destination then why = 'preview panel cannot be kept: ' .. tostring(reason); return end
            lend = {request=request, destination=destination}
            category.lend = lend
            refreshDiscovery()
            reconcile({categoryName})
            if category.lend == lend and lend.active then done, why = true, nil
            else
                -- reconcile ended it; an error in reconcile itself must not leave it.
                if category.lend == lend then endLend(category, 'not lent'); reconcile({categoryName}) end
                why = lend.failed or lend.ended or 'not lent'
            end
        end)
        return done, why
    end
    -- The screen a lent category's preview is laid out on, or nil when it is not lent.
    function self:lentScreen(categoryName)
        local category = assert(categories[categoryName], 'unknown category')
        local active = category.lend and category.lend.active
        local screen = active and (active.screen or active.gameScreen)
        return screen and copy(screen) or nil
    end
    -- Whether a category is lent to a preview now.
    function self:lending(categoryName)
        local category = assert(categories[categoryName], 'unknown category')
        return category.lend ~= nil and category.lend.active ~= nil
    end
    -- A preview's scripted event (event.preview) for a lent category: it reaches only
    -- the preview attachment, as callback(params, event, objects) with params.preview,
    -- and a group focus or Global keys event updates the preview's own state as ModCore
    -- Controls' would the runtime's. Returns whether the lend still stands; one whose
    -- objects died ends here.
    function self:previewEvent(categoryName, event)
        local category = assert(categories[categoryName], 'unknown category')
        assert(type(event) == 'table' and type(event.name) == 'string', 'invalid preview event')
        local standing = false
        serialize(function()
            local lend = category.lend
            if not (lend and lend.active) then return end
            if not lendAlive(lend) then
                endLend(category, 'lent objects gone')
                if self.phase == 'running' then reconcile({categoryName}) end
                return
            end
            standing = true
            local active = lend.active
            active.state.controls = active.state.controls or {}
            if type(event.group) == 'table' then
                active.state.controls.group = {from=event.group.from, to=event.group.to}
            end
            if type(event.global) == 'table' then active.state.controls.global = copy(event.global) end
            local record = category.templates[active.template]
            local callback = active.manager and record.definition.events and record.definition.events[event.name]
            if not callback or M.TEMPLATE_EVENTS[event.name] then return end
            local params = {settings=copy(active.settings), screen=copy(active.screen), state=copy(active.state),
                preview=true}
            local ok, why = pcall(function() return mutate(function()
                return callback(params, copy(event), active.targets)
            end) end)
            if not ok then report('preview event', active.template, why) end
        end)
        return standing
    end
    function self:attachments(id)
        local result = {}
        for token, record in pairs(assert(byId[id], 'unknown template').attached) do result[token] = record.object end
        return result
    end
    return self
end

return M
