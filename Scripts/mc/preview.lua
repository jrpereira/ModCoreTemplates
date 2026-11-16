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
--
-- A category may instead lend the game's own widgets: preview={lend=true, length=..,
-- events=..}. The page's selected template of that category then attaches, through the
-- runtime (mc.runtime's lend), to those widgets, inside the category's shared canvas,
-- which moves whole from the HUD into the preview while it is open; its applied template
-- detaches meanwhile and attaches again when the canvas returns on close. Its events go
-- to that attachment only. Without the widgets in the game (the main menu), the preview
-- shows the category's unavailable text instead.
--
-- The host and every layer are kept as weak handles, never as wrappers.
local Objects=require('mc.objects')
local U=require('mc.util')
local M={}
-- The priority of a template that declares none, as mc.runtime's.
local DEFAULT_PRIORITY=100

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
-- delay(ms,fn) (on the game thread; UE4SS's game-thread timer by default), queue(fn) (runs fn on
-- the game thread later, ExecuteInGameThread by default), construct(class,outer),
-- log (mc_log logger).
function M.new(options)
    local self={}
    local log=options.log or {debug=function() end,warn=function() end}
    local delay=options.delay or function(ms,fn)
        ExecuteInGameThreadWithDelay(math.max(1,math.floor(ms)),fn)
    end
    local construct=options.construct or function(class,outer)
        return StaticConstructObject(StaticFindObject(class),outer)
    end
    local stateRevision,valuesRevision,valuesText=-1,-1,nil
    local running,generation=nil,0

    local function runtime()
        local session=options.session()
        return session and session.runtime
    end
    local function removeLayer(handle)
        local layer=Objects.get(handle)
        if layer then pcall(function() layer:RemoveFromParent() end) end
        Objects.release(handle)
    end
    -- Ends a category's lend: the runtime returns its canvas and reapplies its template.
    local function unlend(category)
        local lent=running.lends[category]
        if not lent then return end
        running.lends[category]=nil
        local current=runtime()
        if current then
            local ok,why=pcall(current.lend,current,category,nil)
            if not ok then log.warn('preview lend not ended: ',category,': ',tostring(why)) end
        end
        removeLayer(lent.fit)
        Objects.release(lent.sized)
    end
    -- The attachments and their layers; lends stay, so a value change only reattaches.
    local function detach()
        if not running then return end
        for index=#running.cleanups,1,-1 do pcall(running.cleanups[index]) end
        for _,layer in ipairs(running.layers) do removeLayer(layer) end
        running.cleanups,running.layers,running.attached={},{},{}
    end
    local function stop()
        if not running then return end
        generation=generation+1
        detach()
        local lent={}
        for category in pairs(running.lends) do lent[#lent+1]=category end
        table.sort(lent)
        for _,category in ipairs(lent) do unlend(category) end
        Objects.release(running.host)
        log.debug('preview closed: ',running.page.id)
        running=nil
    end
    local function host() return Objects.get(running.host) end
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
        local panel=assert(host(),'preview host gone')
        local outer=Objects.call(panel,'GetOuter')
        local hud=Objects.call(outer,'GetOuter')
        assert(Objects.valid(hud),'preview host has no owning widget')
        local screen={width=M.SCREEN.width,height=M.SCREEN.height,left=0,center=M.SCREEN.width/2,right=M.SCREEN.width,
            bottom=0,middle=M.SCREEN.height/2,top=M.SCREEN.height,scale=1}
        -- Only templates that declare preview take part: they keep preview events to
        -- their preview attachment. They attach in the runtime's order, by priority,
        -- lowest first, then by id, so each one's layer stacks over those before it as
        -- on the HUD.
        local selected={}
        local lending={}
        for category in pairs(page.categories or {}) do
            local script=options.categories[category] and options.categories[category].preview
            local decoded=state[category]
            if script and script.lend then lending[#lending+1]=category
            elseif script and decoded then
                for id,own in pairs(decoded.selections or {}) do
                    local template=byId[id]
                    if template and type(template.preview)=='table' and (not page.owned or page.owned[id])
                        and type(template.attach)=='function' then
                        selected[#selected+1]={category=category,id=id,own=own,template=template,
                            script=script,decoded=decoded,priority=template.priority or DEFAULT_PRIORITY}
                    end
                end
            end
        end
        table.sort(selected,function(a,b)
            if a.priority~=b.priority then return a.priority<b.priority end
            return a.id<b.id
        end)
        for _,choice in ipairs(selected) do
            local category,id,own,template,script,decoded=choice.category,choice.id,choice.own,choice.template,
                choice.script,choice.decoded
            local layer=construct('/Script/UMG.Overlay',outer)
            local slot=panel:AddChildToOverlay(layer)
            slot:SetHorizontalAlignment(0);slot:SetVerticalAlignment(0)
            running.layers[#running.layers+1]=Objects.hold(layer)
            local settings=U.copy(decoded.settings or {})
            for name,value in pairs(own) do settings[name]=value end
            local params={settings=settings,screen=U.copy(screen),preview=true,state={},
                onCleanup=function(callback) running.cleanups[#running.cleanups+1]=callback end}
            local attached,why=pcall(template.attach,{hud=hud,cue=layer},params,nil)
            -- Its sound settings: those whose names start with preview.sound, a
            -- menu group's id or a list of them. With the sound button on auto,
            -- events sound only while one of them is selected; without
            -- preview.sound, always.
            local soundIds
            local prefixes=template.preview.sound
            if type(prefixes)=='string' then prefixes={prefixes} end
            -- true: every setting of the template, its Enabled switch included.
            if prefixes==true then prefixes={''} end
            if type(prefixes)=='table' then
                soundIds={}
                -- Keyed by the selector's value, not a list.
                for _,definition in pairs(session.menu.definitions and session.menu.definitions[category] or {}) do
                    if definition.id==id then
                        for name,settingId in pairs(definition.settings or {}) do
                            for _,prefix in ipairs(prefixes) do
                                if type(prefix)=='string' and name:sub(1,#prefix)==prefix then soundIds[settingId]=true end
                            end
                        end
                        if template.preview.sound==true and definition.enabledId then soundIds[definition.enabledId]=true end
                    end
                end
            end
            if attached then
                running.attached[#running.attached+1]={template=template,params=params,script=script,soundIds=soundIds}
            else log.warn('preview attach failed: ',id,': ',tostring(why)) end
        end
        -- Lending categories: the page's selected template there, if the page owns it and
        -- it declares preview, shows on the game's widgets in the category's own canvas,
        -- lent whole; with none, the lend ends.
        table.sort(lending)
        for _,category in ipairs(lending) do
            local script,decoded=options.categories[category].preview,state[category]
            local chosen
            for id,own in pairs(decoded and decoded.selections or {}) do
                local template=byId[id]
                if template and type(template.preview)=='table' and (not page.owned or page.owned[id]) then
                    chosen={id=id,own=own,template=template}
                end
            end
            local current=runtime()
            if not (chosen and current) then unlend(category)
            else
                local lent=running.lends[category]
                if not (lent and Objects.get(lent.sized)) then
                    if lent then unlend(category) end
                    -- The game's screen, scaled to fit the preview: a size box, set to the
                    -- screen the lent widgets are laid out on once the lend reports it,
                    -- that takes the lent canvas. It sits in a canvas layer at that size and
                    -- is scaled by its render transform, not a ScaleBox: inside ModCore
                    -- Settings' own ScaleBox, a second one relaid out on every change of the
                    -- lent widgets, and preview changes crashed the game (2026-11-16).
                    local fit=construct('/Script/UMG.CanvasPanel',outer)
                    local sized=construct('/Script/UMG.SizeBox',outer)
                    local inner=fit:AddChildToCanvas(sized)
                    inner:SetAutoSize(false)
                    sized:SetRenderTransformPivot({X=0,Y=0})
                    local slot=panel:AddChildToOverlay(fit)
                    slot:SetHorizontalAlignment(0);slot:SetVerticalAlignment(0)
                    lent={sized=Objects.hold(sized),fit=Objects.hold(fit)}
                    running.lends[category]=lent
                end
                local ok,done,why=pcall(current.lend,current,category,{destination=Objects.get(lent.sized),
                    template=chosen.id,settings=decoded.settings,overrides=chosen.own})
                if ok and done then
                    local game=current.lentScreen and current:lentScreen(category)
                    local sized=lent.sized and Objects.get(lent.sized)
                    if game and sized then
                        sized:SetWidthOverride(game.width);sized:SetHeightOverride(game.height)
                        local scale=math.min(M.SCREEN.width/game.width,M.SCREEN.height/game.height)
                        local inner=sized.Slot
                        inner:SetSize({X=game.width,Y=game.height})
                        inner:SetPosition({X=(M.SCREEN.width-game.width*scale)/2,
                            Y=(M.SCREEN.height-game.height*scale)/2})
                        sized:SetRenderScale({X=scale,Y=scale})
                    end
                    running.attached[#running.attached+1]={lend=category,template=chosen.template,script=script}
                else
                    local reason=tostring(ok and why or done)
                    log.debug('preview shows no ',category,': ',reason)
                    unlend(category)
                    -- Nothing in the game to lend (the main menu): the category's
                    -- unavailable text shows over the background instead.
                    if type(script.unavailable)=='string' and reason:find('not in the game',1,true) then
                        local shown,why=pcall(function()
                            local text=construct('/Script/UMG.TextBlock',outer)
                            text:SetText(FText(script.unavailable))
                            local font=text.Font
                            font.Size=48
                            text:SetFont(font)
                            text:SetColorAndOpacity({SpecifiedColor={R=0.92,G=0.88,B=0.8,A=1},ColorUseRule=0})
                            text:SetShadowOffset({X=3,Y=3})
                            text:SetShadowColorAndOpacity({R=0,G=0,B=0,A=0.9})
                            text:SetJustification(1)
                            local slot=panel:AddChildToOverlay(text)
                            slot:SetHorizontalAlignment(2);slot:SetVerticalAlignment(2)
                            running.layers[#running.layers+1]=Objects.hold(text)
                        end)
                        if not shown then log.debug('preview text unavailable: ',tostring(why)) end
                    end
                end
            end
        end
    end
    -- One loop of each attached category's events, again and again while open. The events
    -- run in time order through a single pending timer: scheduling every event at once kept
    -- a dozen ExecuteWithDelay callbacks alive per loop, and minutes of that left UE4SS with
    -- dead callbacks and crashed the game (2026-11-16).
    local function fire(mine,item)
        if mine~=generation or not running then return false end
        if not host() then stop();return false end
        local hud=Objects.call(Objects.call(host(),'GetOuter'),'GetOuter')
        local mode=options.shared and options.shared:GetSharedVariable(M.SOUND) or 'auto'
        local focus=options.shared and options.shared:GetSharedVariable(M.FOCUS) or ''
        for _,entry in ipairs(running.attached) do
            if entry.script==item.script and entry.lend then
                -- A lend whose widgets died (a save load) has ended: drop it.
                local event=U.copy(item.step.event)
                event.preview=true
                local current=runtime()
                local ok,standing=false,false
                if current and running.lends[entry.lend] then ok,standing=pcall(current.previewEvent,current,entry.lend,event) end
                if not ok then log.warn('preview event failed: ',tostring(standing)) end
                if not standing and running.lends[entry.lend] then
                    log.debug('preview lend gone: ',entry.lend)
                    unlend(entry.lend)
                end
            elseif entry.script==item.script then
                local event=U.copy(item.step.event)
                event.preview,event.indicator,event.sequence=true,hud,item.sequence
                -- silent: the sound button is off, or on auto with no sound setting selected.
                event.silent=mode=='off' or (mode~='on' and entry.soundIds~=nil and not entry.soundIds[focus])
                event.path='preview:'..running.loops..':'..(item.step.attack or item.sequence)
                local update=entry.template.events and entry.template.events.update
                if update then
                    local ok,why=pcall(update,entry.params,event)
                    if not ok then log.warn('preview event failed: ',tostring(why)) end
                end
            end
        end
        return true
    end
    local loop
    -- Waits ms, then runs fn, unless the preview moved on; a refused timer stops it.
    local function after(mine,ms,fn)
        local ok,why=pcall(delay,math.max(0,math.floor(ms+0.5)),function()
            if mine==generation and running then fn() end
        end)
        if not ok then log.warn('preview stopped: ',tostring(why));stop() end
    end
    function loop(mine)
        if mine~=generation or not running then return end
        if not host() then stop();return end
        running.loops=running.loops+1
        local length=0
        for _,entry in ipairs(running.attached) do length=math.max(length,entry.script.length or 0) end
        local seen,items={},{}
        for _,entry in ipairs(running.attached) do
            if not seen[entry.script] then
                seen[entry.script]=true
                for _,step in ipairs(entry.script.events or {}) do
                    items[#items+1]={at=step.at or 0,script=entry.script,step=step}
                end
            end
        end
        for index,item in ipairs(items) do item.order=index end
        table.sort(items,function(a,b) if a.at~=b.at then return a.at<b.at end return a.order<b.order end)
        for index,item in ipairs(items) do item.sequence=index end
        local total=math.max(length,1000)
        local function step(index,now)
            local item=items[index]
            if not item then
                after(mine,total-now,function() loop(mine) end)
                return
            end
            after(mine,item.at-now,function()
                if fire(mine,item) then step(index+1,item.at) end
            end)
        end
        step(1,0)
    end
    local function start(page,panel)
        stop()
        local handle,why=Objects.hold(panel)
        if not handle then log.warn('preview host cannot be kept: ',tostring(why));return end
        running={page=page,host=handle,cleanups={},layers={},attached={},lends={},loops=0}
        generation=generation+1
        local ok,failure=pcall(attach)
        if not ok then log.warn('preview failed: ',tostring(failure)) end
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
                if running then
                    detach()
                    local ok,failure=pcall(attach)
                    if not ok then log.warn('preview failed: ',tostring(failure)) end
                end
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
            local panel=shared:GetSharedVariable(M.HOST)
            if page and page.preview and Objects.valid(panel) then start(page,panel)
            elseif running then stop() end
        elseif running and running.page.id==id then stop() end
    end
    function self:stop() stop() end
    -- The command arrives inside ModCoreSettings' own call, from the menu's input
    -- handling; the work runs later on the game thread, as an Apply's does (run inline,
    -- moving a slider crashed the game after a few changes: seen 2026-11-16). One
    -- pending run reads the latest shared state, however many commands came first.
    local queue=options.queue or ExecuteInGameThread
    local pending=false
    local function notify()
        pending=false
        local handled,failure=pcall(self.notify,self)
        if not handled then log.warn('preview failed: ',tostring(failure)) end
    end
    if options.register then
        local ok,why=pcall(options.register,M.COMMAND,function()
            if pending then return true end
            pending=true
            local queued,failure=pcall(queue,notify)
            if not queued then pending=false;log.warn('preview failed: ',tostring(failure)) end
            return true
        end)
        if not ok then log.warn('preview unavailable: ',tostring(why)) end
    end
    return self
end

return M
