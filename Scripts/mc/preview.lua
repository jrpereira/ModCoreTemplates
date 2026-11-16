-- A module page's live preview (ModCoreSettings' preview_panel): while the page is open,
-- its selected templates are attached to the preview host with the page's current values,
-- applied or not, and a category's scripted events play in a loop, so the preview shows
-- the templates' own drawing, animation and sounds. Nothing touches the game's HUD.
--
-- A category opts in with preview={length=<ms>, events={{at=<ms>, event={...}}, ...}}. Each
-- event reaches the preview attachments' update callback with preview=true, the preview's
-- widget as its indicator, a fresh path per loop and a sequence number. Attachments get
-- params.preview=true. Only templates declaring preview={...} take part; such a template
-- keeps preview events to its preview attachment and real ones away from it.
local Objects=require('mc.objects')
local U=require('mc.util')
local M={}

M.COMMAND='MCS_Preview_v1'
M.HOST,M.STATE,M.VALUES='MCS.Preview.v1.host','MCS.Preview.v1.state','MCS.Preview.v1.values'
M.SOUND,M.FOCUS='MCS.Preview.v1.sound','MCS.Preview.v1.focus'
M.SCREEN={width=1920,height=1080}

-- 'id=value' lines into {id=value}; numbers where the committed value is a number.
function M.parse(text,committed)
    local values={}
    for line in (text or ''):gmatch('[^\n]+') do
        local id,value=line:match('^([^=]+)=(.*)$')
        if id then
            if type(committed and committed[id])=='number' then value=tonumber(value) or value end
            values[id]=value
        end
    end
    return values
end

-- options: shared (ModRef), register (RegisterConsoleCommandHandler), session() -> the
-- running session (menu, menuController, model) or nil, categories {[id]=definition},
-- delay(ms,fn) (ExecuteWithDelay into the game thread by default), construct(class,outer),
-- log (mc_log logger).
function M.new(options)
    local self={}
    local log=options.log or {debug=function() end,warn=function() end}
    local delay=options.delay or function(ms,fn)
        ExecuteWithDelay(ms,function() ExecuteInGameThread(fn) end)
    end
    local construct=options.construct or function(class,outer)
        return StaticConstructObject(StaticFindObject(class),outer)
    end
    local stateRevision,valuesRevision,valuesText=-1,-1,nil
    local running,generation=nil,0

    local function detach()
        if not running then return end
        for index=#running.cleanups,1,-1 do pcall(running.cleanups[index]) end
        for _,layer in ipairs(running.layers) do pcall(function() if layer:IsValid() then layer:RemoveFromParent() end end) end
        running.cleanups,running.layers,running.attached={},{},{}
    end
    local function stop()
        if not running then return end
        generation=generation+1
        detach()
        log.debug('preview closed: ',running.page.id)
        running=nil
    end
    -- The page's templates at the current values.
    local function attach()
        local session=options.session()
        local page=running.page
        local committed=session.menuController and session.menuController:values() or {}
        local values=U.copy(committed)
        for id,value in pairs(M.parse(valuesText,committed)) do values[id]=value end
        local ok,state=pcall(session.menu.decodeState,values)
        if not ok then log.warn('preview values not usable: ',tostring(state));return end
        local byId={}
        -- The templates themselves (the registry holds their menu metadata only).
        for _,template in ipairs(session.model and session.model.templates or {}) do byId[template.id]=template end
        local hud=Objects.call(Objects.call(running.host,'GetOuter'),'GetOuter')
        assert(Objects.valid(hud),'preview host has no owning widget')
        local screen={width=M.SCREEN.width,height=M.SCREEN.height,left=0,center=M.SCREEN.width/2,right=M.SCREEN.width,
            bottom=0,middle=M.SCREEN.height/2,top=M.SCREEN.height,scale=1}
        for category in pairs(page.categories or {}) do
            local script=options.categories[category] and options.categories[category].preview
            local decoded=state[category]
            if script and decoded then
                for id,own in pairs(decoded.selections or {}) do
                    local template=byId[id]
                    -- Only templates that declare preview take part: they keep preview
                    -- events to their preview attachment.
                    if template and type(template.preview)=='table' and (not page.owned or page.owned[id])
                        and type(template.attach)=='function' then
                        local layer=construct('/Script/UMG.Overlay',Objects.call(running.host,'GetOuter'))
                        local slot=running.host:AddChildToOverlay(layer)
                        slot:SetHorizontalAlignment(0);slot:SetVerticalAlignment(0)
                        running.layers[#running.layers+1]=layer
                        local settings=U.copy(decoded.settings or {})
                        for name,value in pairs(own) do settings[name]=value end
                        local params={settings=settings,screen=U.copy(screen),preview=true,state={},
                            onCleanup=function(callback) running.cleanups[#running.cleanups+1]=callback end}
                        local attached,why=pcall(template.attach,{hud=hud,cue=layer},params,nil)
                        -- Its sound settings: those whose names start with preview.sound (a
                        -- menu group's id). With the sound button on auto, events sound only
                        -- while one of them is selected; without preview.sound, always.
                        local soundIds
                        if type(template.preview.sound)=='string' then
                            soundIds={}
                            for _,definition in ipairs(session.menu.definitions and session.menu.definitions[category] or {}) do
                                if definition.id==id then
                                    for name,settingId in pairs(definition.settings or {}) do
                                        if name:sub(1,#template.preview.sound)==template.preview.sound then soundIds[settingId]=true end
                                    end
                                end
                            end
                        end
                        if attached then
                            running.attached[#running.attached+1]={template=template,params=params,script=script,soundIds=soundIds}
                        else log.warn('preview attach failed: ',id,': ',tostring(why)) end
                    end
                end
            end
        end
    end
    -- One loop of each attached category's events, again and again while open.
    local function loop(mine)
        if mine~=generation or not running then return end
        if not Objects.valid(running.host) then stop();return end
        running.loops=running.loops+1
        local length=0
        for _,entry in ipairs(running.attached) do length=math.max(length,entry.script.length or 0) end
        local scripts={}
        for _,entry in ipairs(running.attached) do scripts[entry.script]=true end
        local count=0
        for script in pairs(scripts) do
            for _,step in ipairs(script.events or {}) do
                count=count+1
                local sequence=count
                delay(step.at,function()
                    if mine~=generation or not running or not Objects.valid(running.host) then return end
                    local hud=Objects.call(Objects.call(running.host,'GetOuter'),'GetOuter')
                    local mode=options.shared and options.shared:GetSharedVariable(M.SOUND) or 'auto'
                    local focus=options.shared and options.shared:GetSharedVariable(M.FOCUS) or ''
                    for _,entry in ipairs(running.attached) do
                        if entry.script==script then
                            local event=U.copy(step.event)
                            event.preview,event.indicator,event.sequence=true,hud,sequence
                            -- silent: the sound button is off, or on auto with no sound setting selected.
                            event.silent=mode=='off' or (mode~='on' and entry.soundIds~=nil and not entry.soundIds[focus])
                            event.path='preview:'..running.loops..':'..(step.attack or sequence)
                            local update=entry.template.events and entry.template.events.update
                            if update then
                                local ok,why=pcall(update,entry.params,event)
                                if not ok then log.warn('preview event failed: ',tostring(why)) end
                            end
                        end
                    end
                end)
            end
        end
        delay(math.max(length,1000),function() loop(mine) end)
    end
    local function start(page,host)
        stop()
        running={page=page,host=host,cleanups={},layers={},attached={},loops=0}
        generation=generation+1
        attach()
        log.debug('preview open: ',page.id,', ',#running.attached,' attached')
        loop(generation)
    end
    function self:notify()
        local shared=options.shared
        local session=options.session()
        if not (shared and session and session.menu) then return end
        local values=shared:GetSharedVariable(M.VALUES)
        if type(values)=='string' then
            local revision,text=values:match('^(%d+)\n?(.*)$')
            revision=tonumber(revision)
            if revision and revision~=valuesRevision then
                valuesRevision,valuesText=revision,text
                if running then detach();attach() end
            end
        end
        local state=shared:GetSharedVariable(M.STATE)
        if type(state)~='string' then return end
        local revision,kind,id=state:match('^(%d+) (%a+) (.+)$')
        revision=tonumber(revision)
        if not revision or revision==stateRevision then return end
        stateRevision=revision
        if kind=='open' then
            local page=session.menu.providers and session.menu.providers[id]
            local host=shared:GetSharedVariable(M.HOST)
            if page and page.preview and Objects.valid(host) then start(page,host)
            elseif running then stop() end
        elseif running and running.page.id==id then stop() end
    end
    function self:stop() stop() end
    if options.register then
        local ok,why=pcall(options.register,M.COMMAND,function()
            local handled,failure=pcall(self.notify,self)
            if not handled then log.warn('preview failed: ',tostring(failure)) end
            return true
        end)
        if not ok then log.warn('preview unavailable: ',tostring(why)) end
    end
    return self
end

return M
