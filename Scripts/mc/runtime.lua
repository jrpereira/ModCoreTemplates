-- Event-driven lifecycle: no timers or periodic scans.
local Selectors = require('mc.selectors')
local ManagedTemplate = require('mc.managed_template')
local TargetState = require('mc.target_state')
local TemplateTargets = require('mc.template_targets')
local copy = require('mc.util').copy
local M = {}
-- Overlay complete setting values by key; nested values are copied, not merged.
local function overlay(base, overrides)
    local result = copy(base)
    for key, value in pairs(overrides) do result[key] = copy(value) end
    return result
end
local function keys(values)
    local result = {}
    for key in pairs(values) do result[#result + 1] = key end
    table.sort(result)
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

function M.new(host, definitions, templates)
    for _, name in ipairs({'valid','identity','ready','matches','parent','find','watch','screen','subscribe','onError'}) do
        assert(type(host[name]) == 'function', 'host requires ' .. name)
    end
    assert(host.unwrap == nil or type(host.unwrap) == 'function', 'host.unwrap must be a function')
    local self = {epoch=1, phase='new', errors={}}
    local categories, byId, candidates, queue = {}, {}, {}, {}
    local activeRoots, searchSignature = {}, nil
    local busy, unsubscribe, suspended = false, nil, false
    local failedInTurn = nil
    for _, definition in ipairs(definitions) do
        assert(type(definition.name) == 'string' and not categories[definition.name], 'duplicate/invalid category')
        assert(definition.settings == nil or type(definition.settings) == 'table', 'category settings must be a table')
        local graph=Selectors.compile(definition.objects or {})
        local mandatory={}
        for _,name in ipairs(graph.order) do
            if graph.byName[name].required then mandatory[#mandatory+1]=name end
        end
        categories[definition.name] = {settings=copy(definition.settings or {}), graph=graph,
            requiredGraph=Selectors.project(graph,mandatory),
            single=definition.single == true, templates={}, objects={}}
    end
    for _, template in ipairs(templates) do
        assert(type(template.id) == 'string' and template.id ~= '' and not byId[template.id], 'duplicate/invalid template id')
        local category = assert(categories[template.category], 'unknown template category')
        assert(template.settings == nil or type(template.settings) == 'table', 'template settings must be a table')
        local graph=Selectors.project(category.graph,template.objects)
        local targetTree=TemplateTargets.compile(category.graph,template.objects)
        assert(#graph.order>0, 'template must declare objects: '..template.id)
        assert(template.managed == nil or type(template.managed) == 'boolean',
            'template.managed must be boolean')
        local managed=template.managed~=false
        local manager
        if managed then
            local specs=TargetState.specs(graph,template.objects)
            local created={}
            for _,name in ipairs(graph.order) do
                local selector=graph.byName[name]
                if selector.create then
                    created[#created+1]={name=name,class=selector.class,from=selector.from,
                        parent=selector.parent}
                end
            end
            manager=ManagedTemplate.new(template,specs,graph.order,created)
        else
            for _,name in ipairs(graph.order) do
                assert(not graph.byName[name].create,
                    'created objects require managed template: '..template.id)
            end
            assert(type(template.attach) == 'function' and type(template.update) == 'function'
                and type(template.detach) == 'function', 'template requires attach, update and detach')
        end
        local record = {definition=template, enabled=false, defaults=copy(template.settings or {}),
            overrides={}, settings={}, revision=0, attached={}, pending={}, waiting={},
            manager=manager, graph=graph,
            targetTree=targetTree}
        byId[template.id], category.templates[template.id] = record, record
    end
    local function report(stage, id, message)
        local error = {stage=stage, template=id, message=tostring(message)}
        self.errors[#self.errors + 1] = error
        -- A diagnostic failure must not break another template's lifecycle.
        pcall(host.onError, error)
    end
    local function serialize(operation)
        queue[#queue + 1] = operation
        if busy then return end
        busy = true
        failedInTurn = {}
        local index = 1
        while index <= #queue do
            local ok, why = pcall(queue[index])
            if not ok then report('runtime', nil, why) end
            index = index + 1
        end
        queue, busy, failedInTurn = {}, false, nil
    end
    local function refreshSettings(category, record)
        record.settings = overlay(category.settings, overlay(record.defaults, record.overrides))
        record.definition.settings = copy(record.settings)
        record.revision = record.revision + 1
    end
    local function invoke(record, operation, object, settings, targets, oldScreen)
        settings = settings or record.settings
        -- Publish the same effective values for callbacks using template.settings.
        record.definition.settings = copy(settings)
        local screen
        local ok, value, why = pcall(function()
            -- Templates receive the underlying UObject only after a final validity check.
            if not host.valid(object) then return false, 'not_ready' end
            if operation == 'detach' then screen=oldScreen end
            if operation ~= 'detach' then
                screen = host.screen(object)
                if not screen then return false, 'not_ready' end
            end
            local target = object
            if host.unwrap then target = host.unwrap(object) end
            if target == nil then return false, 'not_ready' end
            local params = {settings=copy(settings),screen=screen}
            local named=TemplateTargets.arrange(record.targetTree,targets,host.unwrap,host.valid)
            if record.manager then
                return record.manager[operation](record.manager,target,named,params)
            end
            return record.definition[operation](target, params, named)
        end)
        record.definition.settings = copy(record.settings)
        if ok and value ~= false then return true, screen end
        if not (ok and type(why)=='string' and
            (why == 'not_ready' or why:match('^not_ready:'))) then
            report(operation, record.definition.id, ok and (why or 'callback returned false') or value)
        end
        return false
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
    local function refreshDiscovery()
        local roots,seen,identities={},{},{}
        for _,categoryName in ipairs(keys(categories)) do
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
            for _,id in ipairs(keys(category.templates)) do
                local record=category.templates[id]
                if record.enabled then add(record.graph) end
            end
        end
        table.sort(identities)
        local signature=table.concat(identities,'\0')
        if signature==searchSignature then return end
        searchSignature,activeRoots,candidates=signature,roots,{}
        host.watch(roots)
        discover()
    end
    local function reconcile()
        for id, object in pairs(candidates) do
            if not host.valid(object) then candidates[id] = nil end
        end
        for _, name in ipairs(keys(categories)) do
            local category = categories[name]
            local resolved,allObjects={},{}
            local _,requiredObjects=Selectors.resolve(category.requiredGraph,candidates,host)
            for token,object in pairs(requiredObjects) do allObjects[token]=object end
            for _,id in ipairs(keys(category.templates)) do
                local record=category.templates[id]
                if record.enabled then
                    local _,objects,bundles=Selectors.resolve(record.graph,candidates,host)
                    -- A managed template may reparent its own targets (for
                    -- example Fangdango's Distant wheel). Keep those valid
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
                    for token,object in pairs(objects) do allObjects[token]=object end
                end
            end
            category.objects = allObjects
            -- Detach all outgoing templates before any incoming template attaches.
            for _, id in ipairs(keys(category.templates)) do
                local record = category.templates[id]
                local objects=resolved[id] and resolved[id].objects or {}
                local bundles=resolved[id] and resolved[id].bundles or {}
                for _, token in ipairs(keys(record.pending)) do
                    local pending=record.pending[token]
                    local ok,why=pcall(function()
                        if host.valid(pending.object) and targetsValid(pending.targets,host) then
                            assert(record.manager:detach(pending.root))
                        else
                            record.manager:forget(pending.root)
                        end
                    end)
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
                        if record.enabled and host.valid(attached.object)
                            and objects[token] and host.ready(attached.object)
                            and not retainsTargets(attached.targets,bundles[token],host) then
                            record.waiting[token]=targetNames(attached.targets)
                        end
                        if record.manager then
                            local ok,why=pcall(record.manager.forget,record.manager,attached.root)
                            if not ok then report('forget',record.definition.id,why)
                            else record.attached[token]=nil end
                        else record.attached[token]=nil end
                    elseif not record.enabled or not objects[token] or not host.ready(attached.object)
                        or not sameTargets(attached.targets,bundles[token],host) then
                        if record.enabled and objects[token] and host.ready(attached.object)
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
            for _, id in ipairs(keys(category.templates)) do
                local record = category.templates[id]
                if record.enabled and not suspended then
                    local objects,bundles=resolved[id].objects,resolved[id].bundles
                    for _, token in ipairs(keys(objects)) do
                        local object, blocked = objects[token], false
                        -- A failed detach in a single category blocks the replacement.
                        if category.single then
                            for otherId, other in pairs(category.templates) do
                                if otherId ~= id and (other.attached[token] or other.pending[token]) then
                                    blocked = true
                                end
                            end
                        end
                        local old = record.attached[token]
                        if not blocked and not record.pending[token]
                            and host.valid(object) and host.ready(object)
                            and retainsTargets(record.waiting[token],bundles[token],host)
                            and (not old or old.revision ~= record.revision)
                            and not (failedInTurn[record] and failedInTurn[record][token]) then
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
    function self:select(categoryName, selections)
        assert(self.phase == 'new' or self.phase == 'running', 'runtime is not accepting selections')
        local category = assert(categories[categoryName], 'unknown category')
        local desired, count = {}, 0
        for id, settings in pairs(selections) do
            assert(category.templates[id], 'template does not belong to category')
            assert(type(settings) == 'table', 'settings must be a table')
            desired[id], count = copy(settings), count + 1
        end
        assert(not category.single or count <= 1, 'single category accepts at most one template')
        serialize(function()
            for id, record in pairs(category.templates) do
                record.enabled = desired[id] ~= nil
                if not record.enabled then record.waiting={} end
                if record.enabled then
                    record.overrides = desired[id]
                    refreshSettings(category, record)
                end
            end
            if self.phase == 'running' and not suspended then refreshDiscovery(); reconcile() end
        end)
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
            if self.phase == 'running' and not suspended then reconcile() end
        end)
    end
    -- Menu commits category values and template selections together, then reconciles once.
    function self:commit(changes)
        assert(self.phase == 'new' or self.phase == 'running', 'runtime is not accepting commits')
        local pending = {}
        for name, change in pairs(changes) do
            local category = assert(categories[name], 'unknown category')
            assert(type(change.settings) == 'table' and type(change.selections) == 'table', 'invalid category commit')
            local count = 0
            for id, settings in pairs(change.selections) do
                assert(category.templates[id] and type(settings) == 'table', 'invalid template selection')
                count = count + 1
            end
            assert(not category.single or count <= 1, 'single category accepts at most one template')
            pending[name] = copy(change)
        end
        serialize(function()
            for name, change in pairs(pending) do
                local category = categories[name]
                category.settings = change.settings
                for id, record in pairs(category.templates) do
                    record.enabled = change.selections[id] ~= nil
                    if not record.enabled then record.waiting={} end
                    if record.enabled then
                        record.overrides = change.selections[id]
                        refreshSettings(category, record)
                    end
                end
            end
            if next(pending) and self.phase == 'running' and not suspended then
                refreshDiscovery(); reconcile()
            end
        end)
    end
    function self:event(event)
        assert(type(event) == 'table', 'lifecycle event required')
        local kind, object, epoch = event.kind, event.object, event.epoch
        assert(kind == 'changed' or kind == 'lost' or kind == 'world_invalidated' or kind == 'world_ready', 'unknown lifecycle event')
        assert(type(epoch) == 'number', 'event must carry the epoch captured before queuing')
        -- lost carries the identity captured while the object was valid.
        local id = event.id
        assert(kind ~= 'lost' or type(id) == 'string', 'lost event requires captured identity')
        serialize(function()
            if self.phase ~= 'running' or epoch ~= self.epoch then return end
            if kind == 'world_invalidated' then
                self.epoch, suspended, candidates = self.epoch + 1, true, {}
                reconcile()
                for _, category in pairs(categories) do
                    category.objects = {}
                    for _, record in pairs(category.templates) do
                        if record.manager then
                            local ok,why=pcall(record.manager.reset,record.manager)
                            if not ok then report('reset',record.definition.id,why) end
                        end
                        for token,attached in pairs(record.attached) do
                            if not record.manager or not record.manager:hasState(attached.root) then
                                record.attached[token]=nil
                            end
                        end
                        for token,pending in pairs(record.pending) do
                            if not record.manager:hasState(pending.root) then record.pending[token]=nil end
                        end
                        record.waiting={}
                    end
                end
                return
            elseif kind == 'world_ready' then
                if not suspended then return end
                suspended = false
                discover()
            elseif suspended then return
            elseif kind == 'lost' then candidates[id] = nil
            else
                include(object)
            end
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
                    if self.phase == 'running' and not suspended then reconcile() end
                end
            end)
            if not ok then
                self.phase = 'failed'
                if type(unsubscribe) == 'function' then pcall(unsubscribe) end
                unsubscribe, candidates = nil, {}
                error(why)
            end
        end)
    end
    function self:stop()
        serialize(function()
            self.phase = 'stopped'
            if unsubscribe then
                local ok, why = pcall(unsubscribe)
                unsubscribe = nil
                if not ok then report('unsubscribe', nil, why) end
            end
            for _, record in pairs(byId) do record.enabled = false; record.waiting={} end
            reconcile()
            host.watch({})
            candidates,activeRoots,searchSignature = {},{},nil
        end)
    end
    function self:attachments(id)
        local result = {}
        for token, record in pairs(assert(byId[id], 'unknown template').attached) do result[token] = record.object end
        return result
    end
    return self
end

return M
