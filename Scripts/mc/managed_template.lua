local State = require('mc.target_state')
local Objects = require('mc.objects')
local Widget = require('mc.widget')
local copy = require('mc.util').copy
local TemplateTargets = require('mc.template_targets')
local M = {}

function M.new(template,specs,order,createdSpecs)
    assert(type(template.attach)=='function', 'managed template requires attach')
    assert(template.requiredTargets==nil, 'use template.objects instead of requiredTargets')
    local tree=specs.children and specs or nil
    createdSpecs=createdSpecs or {}
    assert(#createdSpecs==0 or tree, 'created objects require an object declaration tree')
    local states=setmetatable({}, {__mode='k'})
    local manager={}
    local function release(created)
        local failure
        for name,object in pairs(created and created.objects or {}) do
            if Objects.valid(object) then
                local parent=Objects.parent(object)
                if parent then
                    local ok,why=pcall(function()
                        assert(parent:RemoveChild(object)~=false,
                            'could not detach created object')
                    end)
                    if not ok then failure=failure or why end
                end
            end
        end
        if failure then error(failure,0) end
        -- Remove placeholders before restoring native sibling order and slots.
        local targets,specs,saved,order={},{},{},{}
        for index,move in ipairs(created and created.moves or {}) do
            if Objects.valid(move.object) and Objects.valid(move.saved.parent) then
                local name='move'..index
                targets[name],specs[name],saved[name]=move.object,move.properties,move.saved
                order[#order+1]=name
            end
        end
        State.restore(targets,specs,order,saved)
        for _,object in pairs(targets) do Widget.rememberSlot(object,Widget.property(object,'Slot')) end
        if created then created.moves={} end
    end
    local function target(name,targets,dependencies)
        return TemplateTargets.find(tree,targets,name) or dependencies[name]
    end
    local function readyObject(object,name)
        if not Objects.valid(object) then error('not_ready: '..name,0) end
        return object
    end
    local function attachCreated(spec,object,targets,dependencies)
        if not spec.parent then return end
        local parent=readyObject(target(spec.parent,targets,dependencies),spec.parent)
        local slot=parent:AddChild(object)
        assert(Objects.valid(slot),spec.name..' could not be attached to '..spec.parent)
        Widget.rememberSlot(object,slot)
        return slot
    end
    local function configureSlot(object,layout,slot)
        if not layout then return end
        slot=slot or Widget.slot(object)
        if not slot then error('not_ready: widget slot',0) end
        if layout=='canvas' then
            slot:SetLayout({
                Offsets={Left=0,Top=0,Right=0,Bottom=0},
                Anchors={Minimum={X=0,Y=0},Maximum={X=0,Y=0}},
                Alignment={X=0,Y=0},
            })
            slot:SetAutoSize(true)
            return
        end
        local canvas=pcall(function()
            slot:SetLayout({
                Offsets={Left=0,Top=0,Right=0,Bottom=0},
                Anchors={Minimum={X=0,Y=0},Maximum={X=1,Y=1}},
                Alignment={X=0,Y=0},
            })
            slot:SetAutoSize(false)
        end)
        if canvas then return end
        slot:SetPadding({Left=0,Top=0,Right=0,Bottom=0})
        slot:SetHorizontalAlignment(0)
        slot:SetVerticalAlignment(0)
    end
    local function configureCreated(spec,object,slot)
        configureSlot(object,spec.layout,slot)
        if spec.layout=='fill' then Widget.setTranslation(object,0,0) end
        if spec.opacity~=nil then Widget.setOpacity(object,spec.opacity) end
        if spec.brushColor then object:SetBrushColor(spec.brushColor) end
    end
    local function reparentCreated(created,targets,dependencies)
        local moves={}
        -- Capture every source before moving any sibling; otherwise later
        -- sources would save indices already shifted by earlier removals.
        for _,spec in ipairs(createdSpecs) do
            local sourceName=spec.reparent
            if sourceName then
                local object=readyObject(target(sourceName,targets,dependencies),sourceName)
                local destination=readyObject(target(spec.destination,targets,dependencies),
                    spec.destination)
                local parent=readyObject(Objects.parent(object),sourceName..' parent')
                local properties={'parent','order','slot'}
                if spec.reparentOpacity~=nil then properties[#properties+1]='opacity' end
                local saved=State.capture({source=object},{source=properties},{'source'}).source
                moves[#moves+1]={object=object,parent=parent,destination=destination,
                    spec=spec,sourceName=sourceName,properties=properties,saved=saved}
            end
        end
        for _,move in ipairs(moves) do
            local object,parent,spec=move.object,move.parent,move.spec
            assert(parent:RemoveChild(object)~=false,
                move.sourceName..' could not be detached')
            created.moves[#created.moves+1]=move
            local slot=move.destination:AddChild(object)
            assert(Objects.valid(slot),move.sourceName..' could not be attached to '
                ..(spec.destination or spec.name))
            Widget.rememberSlot(object,slot)
            configureSlot(object,spec.reparentLayout,slot)
            if spec.reparentOpacity~=nil then
                Widget.setOpacity(object,spec.reparentOpacity)
            end
        end
    end
    local function create(targets,dependencies)
        local created={objects={},moves={}}
        local ok,why=pcall(function()
            for _,spec in ipairs(createdSpecs) do
                local anchor=readyObject(target(spec.from,targets,dependencies),spec.from)
                local outer=readyObject(Objects.call(anchor,'GetOuter'),spec.from..' outer')
                local classPath=spec.class:find('/',1,true) and spec.class
                    or '/Script/UMG.'..spec.class
                local class=assert(StaticFindObject(classPath),
                    spec.name..' class unavailable')
                local object=assert(StaticConstructObject(class,outer),
                    spec.name..' construction failed')
                assert(Objects.valid(object), spec.name..' constructed object invalid')
                created.objects[spec.name]=object
                dependencies[spec.name]=object
                TemplateTargets.assign(tree,targets,spec.name,object)
                local slot=attachCreated(spec,object,targets,dependencies)
                configureCreated(spec,object,slot)
            end
            reparentCreated(created,targets,dependencies)
            for _,spec in ipairs(createdSpecs) do
                if spec.prepass then
                    Widget.prepareLayout(created.objects[spec.name])
                end
            end
        end)
        if not ok then
            local cleaned,reason=pcall(release,created)
            error(tostring(why)..(cleaned and '' or '; cleanup failed: '..tostring(reason)),0)
        end
        return created
    end
    local function cleanup(state)
        local callbacks=state.cleanups or {}
        local failure
        for index=#callbacks,1,-1 do
            local ok,why=pcall(callbacks[index])
            if ok then table.remove(callbacks,index)
            else failure=failure or why end
        end
        if failure then error(failure,0) end
    end
    local function restore(state)
        cleanup(state)
        State.restore(state.targets,specs,order,state.saved)
        release(state.created)
        return true
    end
    local function apply(root,targets,params,previous,dependencies)
        dependencies=dependencies or {}
        if tree then
            local missing=TemplateTargets.missing(tree,targets,Objects.valid,true)
            if missing then
                return false,'not_ready: '..missing
            end
        else
            for _,name in ipairs(order) do
                if specs[name] and not Objects.valid(targets[name]) then return false,'not_ready: '..name end
            end
        end
        if previous then
            local ok,why=pcall(restore,previous)
            if not ok then previous.incomplete=true; return false,why end
        end
        local created=previous and previous.created
        if created then
            for name,object in pairs(created.objects) do
                dependencies[name]=object
                TemplateTargets.assign(tree,targets,name,object)
            end
            local attached,reason=pcall(function()
                for _,spec in ipairs(createdSpecs) do
                    local object=assert(created.objects[spec.name])
                    local slot=attachCreated(spec,object,targets,dependencies)
                    configureCreated(spec,object,slot)
                end
                reparentCreated(created,targets,dependencies)
                for _,spec in ipairs(createdSpecs) do
                    if spec.prepass then Widget.prepareLayout(created.objects[spec.name]) end
                end
            end)
            if not attached then
                local cleaned,why=pcall(release,created)
                return false,tostring(reason)..(cleaned and '' or '; cleanup failed: '..tostring(why))
            end
        elseif #createdSpecs>0 then
            local ok,value=pcall(create,targets,dependencies)
            if not ok then return false,value end
            created=value
        end
        local ok,saved=pcall(State.capture,targets,specs,order)
        if not ok then
            if not previous and created then release(created) end
            return false,saved
        end
        local state={targets=targets,saved=saved,params=copy(params),incomplete=true,
            created=created}
        states[root]=state
        local scoped=copy(params)
        state.cleanups={}
        scoped.onCleanup=function(callback)
            assert(type(callback)=='function','cleanup callback required')
            state.cleanups[#state.cleanups+1]=callback
        end
        local applied,originals,why=pcall(template.attach,targets,scoped,saved)
        if not applied or type(originals)~='table' then
            local restored,reason=pcall(restore,state)
            if restored then states[root]=previous end
            return false,tostring(applied and (why or 'attach must return original property values') or originals)
                ..(restored and '' or '; restoration failed: '..tostring(reason))
        end
        state.saved=originals
        state.incomplete=false
        return true
    end
    function manager:attach(root,targets,params,dependencies)
        return apply(root,targets,params,states[root],dependencies)
    end
    function manager:update(root,targets,params,dependencies)
        local previous=states[root]
        local ok,why=apply(root,targets,params,previous,dependencies)
        if ok then return true end
        -- A failed replacement can retain its own unfinished cleanup. Do not
        -- overwrite that state while recovering the previous attachment.
        if previous and not previous.incomplete and states[root]==previous then
            local recovered,reason=apply(root,previous.targets,previous.params,previous,dependencies)
            if not recovered then why=tostring(why)..'; rollback failed: '..tostring(reason) end
        end
        return false,why
    end
    function manager:detach(root)
        local state=states[root]
        if not state then return true end
        local ok,why=pcall(restore,state)
        if not ok then return false,why end
        states[root]=nil
        return true
    end
    function manager:forget(root)
        if states[root] then
            cleanup(states[root])
            release(states[root].created)
        end
        states[root]=nil
    end
    function manager:hasState(root)
        return states[root]~=nil
    end
    return manager
end

return M
