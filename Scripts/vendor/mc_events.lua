-- Vendored from ModCoreControls (owner). Do not edit copies; change the source and re-vendor.
-- Cross-Lua ModCore event transport. Add event codecs here, independent of categories.
-- Mods copy this file unchanged into their Scripts/vendor folder.
--
-- Failures are written through api.log, the caller's mc_log logger (or a plain
-- function(message)), so they follow its log_level.txt. Without one, a WARN-level
-- mc_log logger is used.
local M={focus='controls.group.focus'}
local definitions={
    [M.focus]={command='MCC_Controls_GroupFocus_v1',data='MCC.Controls.GroupFocus.v1.data',
        initial={group={from=1,to=1}}},
}

local function logger(api)
    local ok,Log=pcall(require,'mc_log')
    if api and api.log~=nil then
        if ok then return Log.wrap(api.log) end
        if type(api.log)=='table' then return api.log end
        local write=api.log
        return {warn=function(...) pcall(write,table.concat({...})) end}
    end
    if ok then return Log.new({name='ModCore Events'}) end
    return {warn=function() end}
end

local function copy(value)
    if type(value)~='table' then return value end
    local result={}
    for key,item in pairs(value) do result[key]=copy(item) end
    return result
end
-- The first activation has no previous group: from is nil, encoded as '-'.
local function transition(payload)
    local group=assert(payload and payload.group,'control group event payload required')
    local from,to=group.from,assert(tonumber(group.to),'target group required')
    if from~=nil then from=assert(tonumber(from),'invalid source group') end
    assert((from==nil or from==1 or from==2) and (to==1 or to==2) and from~=to,
        'invalid control group transition')
    return from,to
end
local function decode(payload)
    assert(type(payload)=='string' and #payload<=64,'invalid event payload')
    local revision,from,to=payload:match('^(%d+) ([12%-]) ([12])$')
    revision,from,to=tonumber(revision),tonumber(from),tonumber(to)
    assert(revision and revision>=1 and revision<=9007199254740991,'invalid event revision')
    transition({group={from=from,to=to}})
    return revision,{group={from=from,to=to}}
end
local function revision(payload)
    return type(payload)=='string' and tonumber(payload:match('^(%d+) ')) or 0
end

function M.format(name,payload)
    assert(definitions[name],'unsupported event')
    local from,to=transition(payload)
    if from==nil then return string.format('%s {"group":{"to":%d}}',name,to) end
    return string.format('%s {"group":{"from":%d,"to":%d}}',name,from,to)
end

function M.publisher(shared)
    return function(name,payload,owner)
        if not shared then return true end
        local definition=assert(definitions[name],'unsupported event')
        local from,to=transition(payload)
        local previous=revision(shared:GetSharedVariable(definition.data))
        assert(previous>=0 and previous<9007199254740991,'event revision exhausted')
        shared:SetSharedVariable(definition.data,
            string.format('%.0f %s %d',previous+1,from and tostring(from) or '-',to))
        local controller=owner and owner.controller
        local player=owner and owner.player
        local viewport=player and player.ViewportClient
        if controller and viewport then
            pcall(function() viewport:ProcessConsoleExec(definition.command,nil,controller) end)
        end
        return true
    end
end

function M.subscribe(api,name,onChange)
    local definition=assert(definitions[name],'unsupported event')
    assert(api and api.ModRef and type(api.RegisterConsoleCommandHandler)=='function',
        'event transport unavailable')
    assert(onChange==nil or type(onChange)=='function','event callback must be a function')
    local state={revision=0,payload=copy(definition.initial)}
    local active=true
    local log=logger(api)
    local function receive()
        if not active then return false end
        local nextRevision,payload=decode(api.ModRef:GetSharedVariable(definition.data))
        if nextRevision<=state.revision then return false end
        state.revision,state.payload=nextRevision,payload
        if onChange then onChange({name=name,revision=nextRevision,group=copy(payload.group)},state) end
        return true
    end
    -- An unreadable event is reported and skipped; the next valid one still arrives.
    local function deliver()
        local delivered,why=pcall(receive)
        if not delivered then log.warn('event delivery failed: ',name,': ',tostring(why)) end
    end
    if api.ModRef:GetSharedVariable(definition.data)~=nil then deliver() end
    local ok,result=pcall(api.RegisterConsoleCommandHandler,definition.command,function()
        deliver()
        return true
    end)
    if not ok or result==false then error(tostring(ok and 'event registration rejected' or result),0) end
    return state,function() active=false;onChange=nil;return true end
end

function M.hub(api,state,onEvent)
    assert(type(state)=='table','event state required')
    assert(onEvent==nil or type(onEvent)=='function','event sink must be a function')
    state.events=state.events or {}
    state.controls=state.controls or {group={from=1,to=1}}
    local subscriptions,interest,active={},{},true
    local hub={}
    local function receive(event,current)
        if not active or (interest[event.name] or 0)==0 then return end
        state.events[event.name]={revision=current.revision,payload=copy(current.payload)}
        if event.name==M.focus then
            state.revision=event.revision
            state.controls.group.from=event.group.from
            state.controls.group.to=event.group.to
        end
        if onEvent then onEvent(event,state) end
    end
    function hub:register(template)
        assert(type(template)=='table','event owner required')
        if template.events==nil then return function() return true end end
        assert(type(template.events)=='table','template.events must be a table')
        local names={}
        for name,callback in pairs(template.events) do
            assert(type(name)=='string' and definitions[name],'unsupported template event: '..tostring(name))
            assert(type(callback)=='function','template event callback must be a function: '..name)
            names[#names+1]=name
        end
        table.sort(names)
        local added={}
        local ok,why=pcall(function()
            for _,name in ipairs(names) do
                interest[name]=(interest[name] or 0)+1
                added[#added+1]=name
                if not subscriptions[name] then
                    subscriptions[name]=select(2,M.subscribe(api,name,receive))
                end
            end
        end)
        if not ok then
            for _,name in ipairs(added) do interest[name]=math.max(0,(interest[name] or 1)-1) end
            error(why,0)
        end
        local registered=true
        return function()
            if not registered then return true end
            registered=false
            for _,name in ipairs(names) do interest[name]=math.max(0,(interest[name] or 1)-1) end
            return true
        end
    end
    function hub:stop()
        if not active then return true end
        active=false
        local ok=true
        for name,stop in pairs(subscriptions) do
            local called,result=pcall(stop)
            if not called or result==false then ok=false end
            subscriptions[name]=nil
        end
        return ok
    end
    return hub
end

return M
