local State = require('mc.target_state')
local Objects = require('mc.objects')
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
        for _,object in pairs(created or {}) do
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
    end
    local function attachCreated(spec,object,targets)
        if not spec.parent then return end
        local parent=assert(TemplateTargets.find(tree,targets,spec.parent),
            'not_ready: '..spec.parent)
        assert(Objects.valid(parent), 'not_ready: '..spec.parent)
        assert(Objects.valid(parent:AddChild(object)),
            spec.name..' could not be attached to '..spec.parent)
    end
    local function create(targets)
        local created={}
        local ok,why=pcall(function()
            for _,spec in ipairs(createdSpecs) do
                local anchor=assert(TemplateTargets.find(tree,targets,spec.from),
                    'not_ready: '..spec.from)
                local outer=assert(Objects.call(anchor,'GetOuter'),
                    'not_ready: '..spec.from..' outer')
                assert(Objects.valid(outer), 'not_ready: '..spec.from..' outer')
                local classPath=spec.class:find('/',1,true) and spec.class
                    or '/Script/UMG.'..spec.class
                local class=assert(StaticFindObject(classPath),
                    spec.name..' class unavailable')
                local object=assert(StaticConstructObject(class,outer),
                    spec.name..' construction failed')
                assert(Objects.valid(object), spec.name..' constructed object invalid')
                created[spec.name]=object
                TemplateTargets.assign(tree,targets,spec.name,object)
                attachCreated(spec,object,targets)
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
    local function apply(root,targets,params,previous)
        if tree then
            local missing=TemplateTargets.missing(tree,targets,Objects.valid,true)
            if missing then return false,'not_ready: '..missing end
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
            for name,object in pairs(created) do
                TemplateTargets.assign(tree,targets,name,object)
            end
            local attached,reason=pcall(function()
                for _,spec in ipairs(createdSpecs) do
                    attachCreated(spec,assert(created[spec.name]),targets)
                end
            end)
            if not attached then
                local cleaned,why=pcall(release,created)
                return false,tostring(reason)..(cleaned and '' or '; cleanup failed: '..tostring(why))
            end
        elseif #createdSpecs>0 then
            local ok,value=pcall(create,targets)
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
    function manager:attach(root,targets,params)
        return apply(root,targets,params,states[root])
    end
    function manager:update(root,targets,params)
        local previous=states[root]
        local ok,why=apply(root,targets,params,previous)
        if ok then return true end
        -- A failed replacement can retain its own unfinished cleanup. Do not
        -- overwrite that state while recovering the previous attachment.
        if previous and not previous.incomplete and states[root]==previous then
            local recovered,reason=apply(root,previous.targets,previous.params,previous)
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
    function manager:reset()
        local failure
        for root,state in pairs(states) do
            local ok,why=pcall(function()
                cleanup(state)
                release(state.created)
            end)
            if ok then states[root]=nil
            else failure=failure or why end
        end
        if failure then error(failure,0) end
    end
    return manager
end

return M
