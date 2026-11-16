package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
-- A lending category's preview (player.quickslots, preview.lend): the runtime detaches the
-- applied template, moves its shared actions canvas whole, with the wheels it adopted
-- untouched inside, into the preview's panel, attaches the page's template to the wheels
-- with params.preview, and on close returns the canvas to its exact parent, index and slot
-- and attaches the applied template again. A HUD that dies while lent ends the lend without
-- touching it.
dofile('tests/support/lifetimes.lua').install()
local Runtime=require('mc.runtime')
local Preview=require('mc.preview')
local category=dofile('Scripts/categories/player_quickslots.lua')
assert(category.preview.lend==true,'player.quickslots lends its wheels to previews')

-- A widget double; a dead one fails every call but IsValid, so any touch shows.
local objects={}
local touchedDead={}
FText=function(text) return text end
local function object(id,class)
    local value={id=id,class=class,children={},members={},opacity=1,alive=true,Font={Size=12},
        RenderTransform={Translation={X=0,Y=0},Scale={X=1,Y=1}}}
    local methods={}
    function methods:IsValid() return self.alive end
    function methods:SetText(text) self.text=text end
    function methods:SetFont(font) self.Font=font end
    function methods:SetColorAndOpacity(color) self.color=color end
    function methods:SetShadowOffset() end
    function methods:SetShadowColorAndOpacity() end
    function methods:SetJustification(justification) self.justification=justification end
    function methods:GetFullName() return self.id end
    function methods:GetOuter() return self.outer or self end
    function methods:GetParent() return self.parent end
    function methods:GetChildrenCount() return #self.children end
    function methods:GetChildAt(index) return self.children[index+1] end
    function methods:GetRenderOpacity() return self.opacity end
    function methods:SetRenderOpacity(opacity) self.opacity=opacity end
    function methods:SetRenderTranslation(position) self.RenderTransform.Translation=position end
    function methods:ForceLayoutPrepass() self.prepassed=(self.prepassed or 0)+1 end
    function methods:AddChild(child)
        -- A widget whose panel died has lost its slot with it, as GC clears it in UE.
        if child.parent and child.parent.alive then child.parent:RemoveChild(child) end
        self.children[#self.children+1]=child; child.parent=self
        local slot={Padding={Left=0,Top=0,Right=0,Bottom=0},HorizontalAlignment=0,VerticalAlignment=0}
        function slot:IsValid() return true end
        function slot:SetLayout(layout) self.layout=layout end
        function slot:SetAutoSize(autoSize) self.autoSize=autoSize end
        function slot:SetPadding(padding) self.Padding=padding end
        function slot:SetHorizontalAlignment(alignment) self.HorizontalAlignment=alignment end
        function slot:SetVerticalAlignment(alignment) self.VerticalAlignment=alignment end
        child.Slot=slot
        return slot
    end
    function methods:AddChildToOverlay(child) return self:AddChild(child) end
    function methods:AddChildToCanvas(child)
        local slot=self:AddChild(child)
        function slot:SetSize(size) self.size=size end
        function slot:SetPosition(position) self.position=position end
        return slot
    end
    function methods:SetRenderTransformPivot(pivot) self.pivot=pivot end
    function methods:SetRenderScale(scale) self.RenderTransform.Scale=scale end
    function methods:SetContent(child) return self:AddChild(child) end
    function methods:SetStretch(stretch) self.stretch=stretch end
    function methods:SetWidthOverride(width) self.WidthOverride=width end
    function methods:SetHeightOverride(height) self.HeightOverride=height end
    function methods:RemoveChild(child)
        for index,item in ipairs(self.children) do
            if item==child then table.remove(self.children,index); child.parent=nil; return true end
        end
        return false
    end
    function methods:RemoveFromParent() if self.parent then self.parent:RemoveChild(self) end end
    setmetatable(value,{__index=function(self,key)
        local method=methods[key]
        if not method then return nil end
        if key=='IsValid' then return method end
        return function(target,...)
            if not target.alive then touchedDead[#touchedDead+1]=target.id..':'..key;error('freed object touched') end
            return method(target,...)
        end
    end})
    objects[#objects+1]=value
    return value
end

-- A game HUD with both quickslot wheels in its switcher, a native sibling between them.
local function buildHud(tag)
    local hud={}
    hud.switcher=object('switcher'..tag,'WidgetSwitcher')
    hud.ability=object('ability'..tag,'WBP_AA_Quickslots_C')
    hud.consumable=object('consumable'..tag,'WBP_HUD_Quickslots_C')
    hud.hud=object('hud'..tag,'WBP_GameHUD_C')
    hud.switcher.owner=hud.hud
    hud.tree=object('hudTree'..tag,'WidgetTree')
    hud.root=object('hudRoot'..tag,'Overlay')
    hud.hud.members.WidgetTree=hud.tree
    hud.tree.members.RootWidget=hud.root
    hud.hud.members.WBP_AA_Quickslots=hud.ability
    hud.hud.members.WBP_HUD_Quickslots=hud.consumable
    hud.switcher:AddChild(hud.consumable)
    hud.sibling=object('sibling'..tag,'Overlay')
    hud.switcher:AddChild(hud.sibling)
    hud.switcher:AddChild(hud.ability)
    hud.ability.Slot:SetPadding({Left=11,Top=12,Right=13,Bottom=14})
    hud.switcher.outer=object('switcherOuter'..tag,'WidgetTree')
    hud.root:AddChild(object('nativeContent'..tag,'Overlay'))
    function hud.kill()
        for _,value in ipairs(objects) do
            if value.id:sub(-#tag)==tag then value.alive=false end
        end
    end
    return hud
end
local current=buildHud('#1')
StaticFindObject=function(path) return {path=path} end
StaticConstructObject=function(class,outer)
    return object(class.path..'#'..#objects,class.path:match('([^%.]+)$'))
end

local host={}
local searching=true
host.valid=function(value) return value~=nil and value.alive==true end
host.identity=function(value) return value.id end
host.ready=function(value) return value.alive==true end
host.matches=function(value,selector)
    return selector.object~=nil and value.class=='WidgetSwitcher'
        or selector.class~=nil and value.class==selector.class:match('([^%.]+)$')
end
host.parent=function() return nil end
host.watch=function() end
host.screen=function() return {width=2560,height=1440,left=0,center=1280,right=2560,bottom=0,middle=720,top=1440} end
host.child=function(parent,class)
    for _,candidate in ipairs(parent.children) do if candidate.class==class then return candidate end end
end
host.member=function(parent,path)
    local value=parent
    for key in path:gmatch('[^.]+') do value=value and (key=='@owner' and value.owner or value.members[key]) end
    return value
end
host.find=function(selector)
    local result={}
    if not searching then return result end
    for _,value in ipairs(objects) do
        if value.alive and host.matches(value,selector) then result[#result+1]=value end
    end
    return result
end
host.subscribe=function() return function() end end
local errors={}
host.onError=function(error) errors[#errors+1]=error.stage..': '..tostring(error.message) end

-- The applied template moves the wheels; the previewed one records each attach and event.
local applied={attaches=0,detaches=0}
local appliedTemplate={id='Applied',category=category.id,uniqueBy='category',
    objects={wheels={abilities={},consumables={},properties={'position'}}},
    attach=function(targets,params,original)
        if applied.notReady then applied.notReady=nil;error('not_ready: key layout',0) end
        applied.attaches=applied.attaches+1
        applied.screen=params.screen
        targets.wheels.abilities:SetRenderTranslation({X=500,Y=500})
        params.onCleanup(function() applied.detaches=applied.detaches+1 end)
        return original
    end,
    events={['controls.group.focus']=function() applied.events=(applied.events or 0)+1 end}}
local shown={attaches={},cleanups=0,events={}}
local previewTemplate={id='Shown',category=category.id,uniqueBy='category',preview={},
    settings={focus={tint={A=0.5}}},
    objects={wheels={abilities={},consumables={},properties={'position','opacity'}}},
    attach=function(targets,params,original)
        if (shown.notReady or 0)>0 then shown.notReady=shown.notReady-1;error('not_ready: key layout',0) end
        shown.attaches[#shown.attaches+1]={params=params,ability=targets.wheels.abilities,
            parent=targets.wheels.abilities:GetParent(),
            before=targets.wheels.abilities.RenderTransform.Translation.X}
        targets.wheels.abilities:SetRenderTranslation({X=7,Y=8})
        params.onCleanup(function() shown.cleanups=shown.cleanups+1 end)
        return original
    end,
    events={['controls.group.focus']=function(params,event,targets)
        shown.events[#shown.events+1]={params=params,event=event,targets=targets}
    end,['controls.slots.global']=function(params,event)
        shown.events[#shown.events+1]={params=params,event=event}
    end}}
local other={attaches={},cleanups=0}
local otherTemplate={id='Other',category=category.id,uniqueBy='category',preview={},
    objects={wheels={abilities={},consumables={},properties={'position'}}},
    attach=function(targets,params,original)
        other.attaches[#other.attaches+1]={params=params,parent=targets.wheels.abilities:GetParent()}
        targets.wheels.consumables:SetRenderTranslation({X=3,Y=4})
        params.onCleanup(function() other.cleanups=other.cleanups+1 end)
        return original
    end}
local brokenTemplate={id='Broken',category=category.id,uniqueBy='category',preview={},
    objects={wheels={abilities={},consumables={}}},
    attach=function() error('preview attach failed on purpose') end}
local plainTemplate={id='Plain',category=category.id,uniqueBy='category',
    objects={wheels={abilities={},consumables={}}},attach=function(_,_,original) return original end}

local runtime=Runtime.new(host,{category},{appliedTemplate,previewTemplate,otherTemplate,brokenTemplate,plainTemplate},
    {revision=0,controls={group={from=2,to=2},global={{false,false,false,false},{false,false,false,false}}}})
runtime:select(category.id,{Applied={}})
runtime:start()
local function actions() return current.ability:GetParent() end
assert(applied.attaches==1 and actions()~=current.switcher and actions()==current.consumable:GetParent(),
    'the applied template attaches with both wheels in the actions canvas')
local canvas=actions()
assert(canvas.parent==current.root,'the actions canvas sits in the HUD root')
-- A native sibling after the canvas, and a slot of its own, to see both restored exactly.
local later=object('later#1','Overlay')
current.root:AddChild(later)
canvas.Slot:SetPadding({Left=1,Top=2,Right=3,Bottom=4})
canvas.Slot:SetHorizontalAlignment(2)
local homeChildren={current.root.children[1],current.root.children[2],current.root.children[3]}
assert(homeChildren[2]==canvas and homeChildren[3]==later)
local wheelOrder={canvas.children[1],canvas.children[2]}
local wheelSlots={canvas.children[1].Slot,canvas.children[2].Slot}
-- The canvas is home: at its index, its slot as it was, the wheels in it untouched.
local function home(label)
    local root=current.root
    assert(canvas.parent==root and #root.children==3 and root.children[1]==homeChildren[1]
        and root.children[2]==canvas and root.children[3]==later,label..': the canvas is back at its index')
    assert(canvas.Slot.Padding.Left==1 and canvas.Slot.Padding.Bottom==4 and canvas.Slot.HorizontalAlignment==2,
        label..': with its slot')
    assert(current.ability.parent==canvas and current.consumable.parent==canvas
        and canvas.children[1]==wheelOrder[1] and canvas.children[2]==wheelOrder[2]
        and canvas.children[1].Slot==wheelSlots[1] and canvas.children[2].Slot==wheelSlots[2],
        label..': the wheels never left their canvas slots')
end

-- Open: the applied template detaches, the canvas moves whole into the preview's panel
-- and the page's template attaches to the wheels with the request's screen and values.
local stage=object('stage','SizeBox')
local screen={width=1920,height=1080,left=0,center=960,right=1920,bottom=0,middle=540,top=1080,scale=1}
local ok,why=runtime:lend(category.id,{destination=stage,template='Shown',settings={Shared=1},
    overrides={WheelsS='large'},screen=screen})
assert(ok,why)
assert(runtime:lending(category.id),'lent')
assert(applied.detaches==1 and shown.attaches[1].before==0,
    'the applied template detached through its normal path, natives restored')
assert(canvas.parent==stage and #stage.children==1 and #current.root.children==2,
    'the actions canvas moved whole from the HUD root into the preview panel')
assert(canvas.Slot.layout and canvas.Slot.layout.Anchors.Maximum.X==1 and canvas.Slot.layout.Anchors.Maximum.Y==1,
    'filling it')
assert(current.ability.parent==canvas and current.consumable.parent==canvas
    and current.ability.Slot==wheelSlots[1] and current.consumable.Slot==wheelSlots[2],
    'the wheels stay in their canvas slots, untouched')
local first=shown.attaches[1]
assert(#shown.attaches==1 and first.parent==canvas and first.params.preview==true
    and first.params.screen.width==1920 and first.params.screen.height==1080,
    'the page template attaches on the lent wheels with params.preview and the request\'s screen')
assert(first.params.settings.WheelsS=='large' and first.params.settings.Shared==1
    and first.params.settings.focus.tint.A==0.5,'its settings: category, template defaults, page values')
assert(first.params.state.controls.group.to==2,'and a copy of the state')
assert(current.ability.RenderTransform.Translation.X==7,'the preview template placed the lent wheel')
assert(applied.attaches==1,'the applied template stays detached while lent')
-- The canvas counts as lent, not lost: a reconcile neither detaches the shared objects nor
-- builds another canvas.
runtime:event({kind='changed',object=current.switcher,epoch=runtime.epoch})
assert(runtime:lending(category.id) and canvas.parent==stage and current.ability.parent==canvas
    and #current.root.children==2 and #shown.attaches==1 and applied.attaches==1,
    'a reconcile while lent leaves the lend and the shared canvas alone')

-- Real events reach applied attachments only; there are none while lent.
runtime:stateChanged({name='controls.group.focus',group={from=2,to=1}})
assert(#shown.events==0 and applied.events==nil,'real events do not reach the preview attachment')
-- Preview events reach the preview attachment, with the preview's own state.
assert(runtime:previewEvent(category.id,{name='controls.group.focus',group={from=2,to=1},preview=true}))
local event=shown.events[1]
assert(event and event.event.preview and event.params.preview and event.params.state.controls.group.to==1
    and event.targets.wheels.abilities==current.ability,'a preview event reaches the lent attachment')
assert(runtime:previewEvent(category.id,{name='controls.slots.global',
    global={{false,false,false,false},{false,true,false,false}},preview=true}))
assert(runtime.state.controls.global[2][2]==false,'preview Global keys leave the real state alone')
assert(runtime:previewEvent(category.id,{name='controls.group.focus',group={from=1,to=2},preview=true}))
assert(shown.events[3].params.state.controls.global[2][2]==true,'and stay in the preview\'s state')
-- An Apply while lent changes what attaches after, not the preview.
runtime:select(category.id,{Applied={Style=1}})
assert(applied.attaches==1 and canvas.parent==stage,'an Apply while lent waits for the close')

-- A value change replaces only the preview attachment: the canvas stays lent.
ok,why=runtime:lend(category.id,{destination=stage,template='Shown',overrides={WheelsS='small'},screen=screen})
assert(ok,why)
assert(#shown.attaches==2 and shown.cleanups==1 and shown.attaches[2].params.settings.WheelsS=='small'
    and canvas.parent==stage and current.ability.parent==canvas and applied.attaches==1,
    'a value change reattaches in place')

-- Close: the preview detaches, the canvas returns to its exact place, the applied
-- template attaches again.
ok,why=runtime:lend(category.id,nil)
assert(ok,why)
assert(not runtime:lending(category.id) and shown.cleanups==2,'closing detaches the preview')
assert(#stage.children==0,'the preview panel is empty')
home('close')
assert(applied.attaches==2 and current.ability.RenderTransform.Translation.X==500
    and applied.screen.width==2560,'the applied template attaches again, on the game screen')
assert(#errors==0,table.concat(errors,'; '))

-- Another template while open, then close (the case that crashed in game): the first
-- preview attachment detaches, the second attaches on the same lent wheels, and the close
-- restores cleanly.
local before=applied.attaches
ok,why=runtime:lend(category.id,{destination=stage,template='Shown',screen=screen})
assert(ok,why)
local shownCleanups=shown.cleanups
ok,why=runtime:lend(category.id,{destination=stage,template='Other',screen=screen})
assert(ok,why)
assert(shown.cleanups==shownCleanups+1 and #other.attaches==1 and other.attaches[1].parent==canvas
    and other.attaches[1].params.preview==true and canvas.parent==stage,
    'a template switch while open replaces the preview attachment on the lent canvas')
assert(current.ability.RenderTransform.Translation.X==0 and current.consumable.RenderTransform.Translation.X==3,
    'the first template\'s placement went with its detach')
ok,why=runtime:lend(category.id,nil)
assert(ok,why)
assert(other.cleanups==1 and not runtime:lending(category.id) and #stage.children==0,'closing detaches it')
home('switch then close')
assert(applied.attaches==before+1 and current.ability.RenderTransform.Translation.X==500
    and current.consumable.RenderTransform.Translation.X==0,'the applied template attaches again')
assert(#errors==0,table.concat(errors,'; '))

-- A failing preview attach ends the lend: the canvas returns and the applied template
-- attaches again.
before=applied.attaches
ok,why=runtime:lend(category.id,{destination=stage,template='Broken',screen=screen})
assert(not ok and tostring(why):find('on purpose',1,true),tostring(why))
assert(not runtime:lending(category.id) and #stage.children==0 and applied.attaches==before+1,
    'a failure mid-lend restores the canvas and reapplies')
home('failure')
assert(errors[#errors]:find('on purpose',1,true),'and is reported')
-- So does a failing replacement.
ok=runtime:lend(category.id,{destination=stage,template='Shown',screen=screen})
assert(ok and canvas.parent==stage)
before=applied.attaches
ok=runtime:lend(category.id,{destination=stage,template='Broken',screen=screen})
assert(not ok and not runtime:lending(category.id) and applied.attaches==before+1,'a failing value change ends the lend too')
home('failing replacement')
-- A lend that is not ready (here: no screen to lay out on) ends too, and the applied
-- template attaches again (seen in game: the bars stayed top left).
local screenOf=host.screen
local refused=false
-- The lend's read of the screen fails once; later reads (the applied template's) work.
host.screen=function(...) if not refused then refused=true;return nil end return screenOf(...) end
before=applied.attaches
ok,why=runtime:lend(category.id,{destination=stage,template='Shown'})
host.screen=screenOf
assert(not ok and tostring(why):find('not_ready',1,true) and not runtime:lending(category.id)
    and applied.attaches==before+1,
    'a lend that is not ready restores the canvas and reapplies: '..tostring(why)..' '..applied.attaches..'/'..before)
home('not ready')
-- Only templates that declare preview can be lent to.
assert(not pcall(runtime.lend,runtime,category.id,{destination=stage,template='Plain',screen=screen}),
    'a template without preview is refused')
-- A move refused by the game (the HUD root keeps the canvas) ends the lend at home.
local refuse=current.root
local original=refuse.RemoveChild
rawset(refuse,'RemoveChild',function(self,child) if child==canvas then return false end return original(self,child) end)
before=applied.attaches
ok,why=runtime:lend(category.id,{destination=stage,template='Shown',screen=screen})
rawset(refuse,'RemoveChild',nil)
assert(not ok and tostring(why):find('could not be detached',1,true) and #stage.children==0
    and applied.attaches==before+1,'a refused move ends the lend: '..tostring(why))
home('refused move')
errors={}

-- The HUD dies while lent (a save load): the lend ends without touching it, the canvas
-- leaves the preview, and the new HUD gets a fresh canvas and the applied template.
ok=runtime:lend(category.id,{destination=stage,template='Shown',screen=screen})
assert(ok and canvas.parent==stage)
local cleanups=shown.cleanups
local old=current
old.kill()
current=buildHud('#2')
touchedDead={}
assert(runtime:previewEvent(category.id,{name='controls.group.focus',group={from=2,to=1},preview=true})==false,
    'a preview event finds the lend gone')
assert(not runtime:lending(category.id) and #touchedDead==0,'no freed object touched: '..table.concat(touchedDead,', '))
assert(shown.cleanups==cleanups+1,'the preview attachment\'s cleanups ran')
assert(canvas.parent==nil and #stage.children==0,'the old canvas left the preview')
before=applied.attaches
runtime:event({kind='changed',object=current.switcher,epoch=runtime.epoch})
assert(#touchedDead==0,'no freed object touched: '..table.concat(touchedDead,', '))
assert(applied.attaches==before+1 and actions()~=current.switcher and actions()~=canvas
    and actions().parent==current.root,'the new HUD gets a fresh canvas and the applied template')
canvas=actions()
-- The same through a reconcile: a HUD that dies is found there first.
ok=runtime:lend(category.id,{destination=stage,template='Shown',screen=screen})
assert(ok and canvas.parent==stage)
current.kill()
runtime:event({kind='changed',object=stage,epoch=runtime.epoch})
assert(not runtime:lending(category.id) and #touchedDead==0 and #stage.children==0,
    'a reconcile ends a dead lend untouched')
-- A preview panel that goes away ends the lend and returns the live canvas.
current=buildHud('#3')
runtime:event({kind='changed',object=current.switcher,epoch=runtime.epoch})
canvas=actions()
local gone=object('gone','SizeBox')
ok=runtime:lend(category.id,{destination=gone,template='Shown',screen=screen})
assert(ok and canvas.parent==gone)
gone.alive=false
before=applied.attaches
runtime:event({kind='changed',object=current.switcher,epoch=runtime.epoch})
assert(not runtime:lending(category.id) and canvas.parent==current.root and current.ability.parent==canvas
    and current.consumable.parent==canvas and applied.attaches==before+1,
    'a gone preview panel ends the lend; the canvas goes home')

-- Stopping the runtime ends a lend first.
ok=runtime:lend(category.id,{destination=stage,template='Shown',screen=screen})
assert(ok)
runtime:stop()
assert(current.ability.parent==current.switcher and current.consumable.parent==current.switcher
    and canvas.parent==nil and #stage.children==0,
    'stopping returns the lent canvas, then the native switcher gets the wheels back')

-- The main menu: no HUD, nothing to lend, nothing shown and nothing reported.
searching=false
local menuErrors=#errors
local empty=Runtime.new(host,{category},{appliedTemplate,previewTemplate})
empty:select(category.id,{Applied={}})
empty:start()
local menuStage=object('menuStage','SizeBox')
ok,why=empty:lend(category.id,{destination=menuStage,template='Shown',screen=screen})
assert(not ok and tostring(why):find('not in the game',1,true) and not empty:lending(category.id),tostring(why))
assert(#errors==menuErrors and #menuStage.children==0,'no HUD: the preview shows nothing')
empty:stop()
searching=true

-- Through mc.preview: a page of a lending category lends while it is open, runs one
-- pending timer for its loop, sends the script's events to the lend, and gives the
-- canvas back on close.
-- One HUD in the game, as there.
current.kill()
current=buildHud('#4')
local live=Runtime.new(host,{category},{appliedTemplate,previewTemplate,otherTemplate})
live:select(category.id,{Applied={}})
live:start()
local vars,handlers,queue={},{},{}
local shared={GetSharedVariable=function(_,k) return vars[k] end,SetSharedVariable=function(_,k,v) vars[k]=v end}
local owner=object('Menu','UserWidget')
local tree=object('MenuTree','WidgetTree');tree.outer=owner
local panel=object('PreviewHost','Overlay');panel.outer=tree
local session={runtime=live,
    menu={definitions={},providers={['Page.F']={id='Page.F',preview=true,categories={[category.id]=true},
        owned={Shown=true,Other=true}}},
        decodeState=function(values) return {[category.id]={settings={},
            selections={[values.MCT_Template or 'Shown']={WheelsS=values.MCT_Size}}}} end},
    menuController={values=function() return {MCT_Size='standard'} end},
    model={templates={appliedTemplate,previewTemplate,otherTemplate}}}
local preview=Preview.new({shared=shared,register=function(c,fn) handlers[c]=fn;return true end,
    session=function() return session end,categories={[category.id]=category},
    queue=function(fn) fn() end,
    delay=function(ms,fn) queue[#queue+1]={ms=ms,fn=fn} end})
local events=#shown.events
canvas=actions()
vars[Preview.HOST]=panel
vars[Preview.VALUES]='1\nMCT_Size=large'
vars[Preview.STATE]='2 open Page.F'
handlers[Preview.COMMAND]()
assert(live:lending(category.id),'opening the page lends the canvas')
-- The lent wheels keep their HUD sizes: the preview lays them out on the game's screen
-- (2560 by 1440 here) in a size box that size, scaled to fit, which takes the canvas.
local fit=panel.children[1]
local sized=fit and fit.children[1]
assert(fit.class=='CanvasPanel' and sized.class=='SizeBox'
    and sized.WidthOverride==2560 and sized.HeightOverride==1440
    and sized.Slot.size.X==2560 and sized.Slot.size.Y==1440 and sized.Slot.autoSize==false
    and sized.pivot.X==0 and sized.RenderTransform.Scale.X==0.75 and sized.RenderTransform.Scale.Y==0.75
    and sized.Slot.position.X==0 and sized.Slot.position.Y==0,
    'a size box the game\'s screen in size, scaled to fit by its render transform, no ScaleBox')
assert(#sized.children==1 and sized.children[1]==canvas and canvas.parent==sized
    and current.ability.parent==canvas,'the actions canvas, whole, in the size box')
assert(shown.attaches[#shown.attaches].params.screen.width==2560,'laid out on the game\'s screen')
assert(shown.attaches[#shown.attaches].params.settings.WheelsS=='large','at the page\'s values')
assert(#queue==1,'one pending timer')
local function run(count)
    for _=1,count do
        table.sort(queue,function(a,b) return a.ms<b.ms end)
        local item=table.remove(queue,1)
        item.fn()
        assert(#queue<=1,'never more than one pending timer')
    end
end
run(#category.preview.events+1)
assert(#shown.events-events==#category.preview.events,'one loop of the script reaches the lend')
assert(shown.events[#shown.events].event.preview==true,'as preview events')
vars[Preview.VALUES]='3\nMCT_Size=small'
handlers[Preview.COMMAND]()
assert(shown.attaches[#shown.attaches].params.settings.WheelsS=='small' and canvas.parent==sized,
    'a value change reattaches on the same lent canvas')
-- The page's template switched while open, then the page closes (the case that crashed in
-- game): the canvas goes home and the applied template attaches again.
local otherAttaches=#other.attaches
vars[Preview.VALUES]='4\nMCT_Size=small\nMCT_Template=Other'
handlers[Preview.COMMAND]()
assert(#other.attaches==otherAttaches+1 and other.attaches[#other.attaches].parent==canvas and canvas.parent==sized,
    'a template switch reattaches on the same lent canvas')
before=applied.attaches
vars[Preview.STATE]='5 closed Page.F'
handlers[Preview.COMMAND]()
assert(not live:lending(category.id) and canvas.parent==current.root and current.ability.parent==canvas
    and #panel.children==0 and applied.attaches==before+1,
    'closing gives the canvas back, removes the size box and reapplies')
vars[Preview.VALUES]='6\nMCT_Size=small'
handlers[Preview.COMMAND]()
-- The HUD dies while the page is open: the next event finds the lend gone, the canvas goes.
vars[Preview.STATE]='7 open Page.F'
handlers[Preview.COMMAND]()
assert(live:lending(category.id) and canvas.parent==panel.children[1].children[1])
current.kill()
touchedDead={}
run(2)
assert(not live:lending(category.id) and #panel.children==0 and canvas.parent==nil and #touchedDead==0,
    'a HUD gone mid-preview stops the lend cleanly')
vars[Preview.STATE]='8 closed Page.F'
handlers[Preview.COMMAND]()
-- No game to lend from (the main menu): the category's text shows over the background.
vars[Preview.STATE]='9 open Page.F'
handlers[Preview.COMMAND]()
local note=panel.children[1]
assert(not live:lending(category.id) and note and note.class=='TextBlock' and #panel.children==1
    and note.text=='Load a game to preview your Quickslots','the main menu shows why there is nothing to see')
vars[Preview.STATE]='10 closed Page.F'
handlers[Preview.COMMAND]()
assert(#panel.children==0,'and it goes with the preview')
live:stop()
-- With the category's attachDelay (2 s, settled by a timer the game's pause menu can hold
-- back): the applied template waits for it once, at the start; after a lend it attaches
-- again at once, without waiting for another delay (seen in game: the wheels stayed at the
-- canvas origin after the preview closed).
current=buildHud('#5')
local deferred={}
local delayed=Runtime.new(host,{category},{appliedTemplate,previewTemplate},nil,
    {defer=function(ms,fn) deferred[#deferred+1]=fn;return true end})
delayed:select(category.id,{Applied={}})
local start=applied.attaches
delayed:start()
assert(applied.attaches==start,'the applied template waits for the attachDelay')
local pending=deferred;deferred={}
for _,fn in ipairs(pending) do fn() end
assert(applied.attaches==start+1,'and attaches once it settles')
canvas=actions()
local delayedStage=object('delayedStage','SizeBox')
assert(delayed:lend(category.id,{destination=delayedStage,template='Shown',screen=screen}))
-- While the menu is open the HUD may drop out of the candidates for a reconcile, which
-- forgets its settled state.
searching=false
delayed:select(category.id,{Applied={}})
searching=true
assert(delayed:lend(category.id,nil))
assert(applied.attaches==start+2 and canvas.parent==current.root and current.ability.parent==canvas,
    'after the lend it attaches again at once, timers held back: '..applied.attaches-start)
delayed:stop()
-- After a preview the applied template lays out again at once; if its widgets are not
-- measured yet (not_ready), it tries again every quarter second, one pending timer,
-- whether or not the game is paused (its pause menu shows the HUD).
local retry=Runtime.new(host,{category},{appliedTemplate,previewTemplate},nil,
    {defer=function(ms,fn) deferred[#deferred+1]={ms=ms,fn=fn};return true end})
retry:select(category.id,{Applied={}})
deferred={}
retry:start()
for _,item in ipairs(deferred) do item.fn() end
deferred={}
local retryStage=object('retryStage','SizeBox')
assert(retry:lend(category.id,{destination=retryStage,template='Shown',screen=screen}))
local laid=applied.attaches
applied.notReady=1
assert(retry:lend(category.id,nil))
assert(applied.attaches==laid and #deferred==1 and deferred[1].ms==250,'not measured yet: one retry pending')
local tick=table.remove(deferred,1);tick.fn()
assert(applied.attaches==laid+1 and current.ability.RenderTransform.Translation.X==500,
    'the retry lays it out, paused or not')
tick=table.remove(deferred,1)
if tick then tick.fn() end
assert(#deferred==0 and applied.attaches==laid+1,'and then stops')
retry:stop()
-- The page template on a canvas just lent may not be measured yet (not_ready: key layout,
-- seen in game): the canvas stays lent and the template attaches again a tenth of a second
-- later; after 20 tries the lend ends and the applied template comes back.
local waiting=Runtime.new(host,{category},{appliedTemplate,previewTemplate},nil,
    {defer=function(ms,fn) deferred[#deferred+1]={ms=ms,fn=fn};return true end})
waiting:select(category.id,{Applied={}})
deferred={}
waiting:start()
for _,item in ipairs(deferred) do item.fn() end
deferred={}
canvas=actions()
local waitStage=object('waitStage','SizeBox')
local seen=#shown.attaches
shown.notReady=1
assert(waiting:lend(category.id,{destination=waitStage,template='Shown',screen=screen}),'a lend waiting for layout stands')
assert(canvas.parent==waitStage and #shown.attaches==seen and #deferred==1 and deferred[1].ms==100,
    'the canvas stays lent, one attach pending')
tick=table.remove(deferred,1);tick.fn()
assert(#shown.attaches==seen+1 and shown.attaches[#shown.attaches].parent==canvas and #deferred==0,
    'and the template attaches on it')
-- A switch while it waits keeps one timer, then attaches the new template.
seen=#shown.attaches
shown.notReady=1
assert(waiting:lend(category.id,{destination=waitStage,template='Shown',screen=screen}))
assert(#deferred==1 and canvas.parent==waitStage,'a not-ready switch waits too')
tick=table.remove(deferred,1);tick.fn()
assert(#shown.attaches==seen+1,'and attaches')
-- Never ready: it gives up and the canvas goes home.
local before=applied.attaches
shown.notReady=1000
assert(waiting:lend(category.id,{destination=waitStage,template='Shown',screen=screen}))
local tries=0
while #deferred>0 and tries<100 do
    tick=table.remove(deferred,1)
    if tick.ms==100 then tries=tries+1 end
    tick.fn()
end
assert(tries==20 and not waiting:lending(category.id) and canvas.parent==current.root
    and applied.attaches>before,'after 20 tries the lend ends: '..tries)
shown.notReady=nil
waiting:stop()
print('PASS: a lending category\'s preview borrows the actions canvas whole, attaches the page template there and returns it')
