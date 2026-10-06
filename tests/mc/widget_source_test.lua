package.path='./Scripts/?.lua;'..package.path
local Source=require('mc.widget_source')
local References=require('mc.lua_references')
local Runtime=require('mc.runtime')
local objectPath='WidgetSwitcher /Game/HUD/WBP_GameHUD.WBP_GameHUD_C:WidgetTree.QuickslotsSwitcher'
local classPath='/Game/HUD/WBP_GameHUD.WBP_GameHUD_C'
local all,created,hooks,finds={}, {}, {}, 0
local nextSerial,serialByAddress=0,{}
local function obj(address,full,classes,outer)
    nextSerial=nextSerial+1
    serialByAddress[address]=nextSerial
    local o={address=address,full=full,classes=classes or {},outer=outer,alive=true}
    function o:GetAddress() return self.address end
    function o:IsValid() return self.alive end
    function o:GetFullName() return self.full end
    function o:GetOuter() return self.outer end
    function o:GetClass() return self.class end
    function o:GetParent() return self.parent end
    function o:GetWorld() return self.world end
    function o:IsInViewport() return self.inViewport==true end
    function o:IsA(class) return self.classes[class:gsub('^Class ','')] == true end
    all[#all+1]=o
    return o
end
local world=obj(1,'World /Game/Map.Map')
local ownerClass=obj(2,'WidgetBlueprintGeneratedClass '..classPath)
local widgetClass=obj(3,'Class /Script/UMG.WidgetSwitcher')
local slotClass=obj(4,'Class /Script/UMG.SlotWidget')
local owner=obj(10,'WBP_GameHUD_C /Engine/Transient.GameEngine_0.WBP_GameHUD_C_1',
    {['/Script/UMG.UserWidget']=true,['/Script/UMG.Widget']=true})
owner.class=ownerClass; owner.world=world
local tree=obj(11,'WidgetTree /Engine/Transient.GameEngine_0.WBP_GameHUD_C_1.WidgetTree',{},owner)
local root=obj(12,'WidgetSwitcher /Engine/Transient.GameEngine_0.WBP_GameHUD_C_1.WidgetTree.QuickslotsSwitcher',
    {['/Script/UMG.Widget']=true,['/Script/UMG.WidgetSwitcher']=true},tree)
root.class=widgetClass; owner.WidgetTree=tree; tree.RootWidget=root
local child=obj(13,'SlotWidget /Engine/Transient.GameEngine_0.WBP_GameHUD_C_1.WidgetTree.Slot_0',
    {['/Script/UMG.Widget']=true,['/Script/UMG.SlotWidget']=true},tree)
child.class=slotClass
local api={}
local sourceErrors={}
api.MCTOnError=function(error) sourceErrors[#sourceErrors+1]=error end
api.UE4SSLuaEventBridge={API_VERSION=5,
    GetCapabilities=function() return {api=5,object_lifetimes=true} end,
    lifetimes={captureObject=function(value)
        local serial=serialByAddress[value.address]
        return serial and tostring(serial) or nil,'native lifetime unavailable'
    end,
        valid=function() return true end}}
function api.StaticFindObject(path)
    if path~='/Script/UMG.Default__WidgetLayoutLibrary' then return nil end
    return {IsValid=function() return true end,
        GetViewportSize=function(_,context)
            assert(context==owner or context.full:find('WBP_GameHUD_C_2',1,true),
                'viewport lookup must use the owning HUD')
            return {X=1920,Y=1080}
        end,
        GetViewportScale=function(_,context)
            assert(context==owner or context.full:find('WBP_GameHUD_C_2',1,true))
            return 0.5
        end}
end
function api.IsInGameThread() return true end
function api.ExecuteInGameThread(callback) callback() end
function api.FindAllOf(class)
    finds=finds+1
    if class=='Missing_C' then return nil end
    local result={}
    for _,value in ipairs(all) do if value.classes['/Script/UMG.'..class] then result[#result+1]=value end end
    return result
end
function api.NotifyOnNewObject(class,callback) created[class]=callback end
function api.RegisterHook(path,pre,post) hooks[path]={pre=pre,post=post}; return 1,2 end
function api.UnregisterHook(path) hooks[path]=nil end
local category={name='quickslots',objects={switcher={source='lookup',object=objectPath},slots={source='lookup',class='/Script/UMG.SlotWidget',within='switcher'}}}
local source=Source.new({category},api)
do
    local unavailable={}
    for key,value in pairs(api) do unavailable[key]=value end
    unavailable.UE4SSLuaEventBridge=nil
    assert(not pcall(Source.new,{category},unavailable),
        'identity source must fail closed without serial-backed lifetimes')
    unavailable.UE4SSLuaEventBridge={API_VERSION=5,
        GetCapabilities=function()return {api=5,object_lifetimes=false}end,
        lifetimes={captureObject=function() return nil,'object lifetime service is unavailable' end}}
    unavailable.RegisterHook=function() return 1,2 end
    unavailable.UnregisterHook=function() end
    unavailable.NotifyOnNewObject=function() end
    local warnings={}
    unavailable.MCTOnError=function(error) warnings[#warnings+1]=error end
    local degraded=Source.new({},unavailable)
    local before=degraded.identity(root)
    assert(type(before)=='string' and before:find(tostring(root.address),1,true),
        'failed native ABI probe must use the address identity')
    assert(degraded.identity(root)==before and #warnings==1 and warnings[1].stage=='identity')
    local fallbackHost=References.new(degraded)
    local reference=assert(fallbackHost.capture(root))
    assert(fallbackHost.valid(reference), 'fallback identity must permit attachment references')
    root.alive=false
    assert(not fallbackHost.valid(reference), 'a destroyed object must expire its fallback reference')
    root.alive=true
    degraded.stop()
end
-- The address-identity fallback works, so its notice is TRACE: silent at the default WARN.
do
    local Log=require('mc_log')
    for _,case in ipairs({{level='trace',lines=1},{level=nil,lines=0}}) do
        local quiet={}
        for key,value in pairs(api) do quiet[key]=value end
        quiet.MCTOnError=nil
        quiet.RegisterHook=function() return 1,2 end
        quiet.UnregisterHook=function() end
        quiet.NotifyOnNewObject=function() end
        quiet.UE4SSLuaEventBridge={API_VERSION=5,
            GetCapabilities=function() return {api=5,object_lifetimes=false} end,
            lifetimes={captureObject=function() return nil,'object lifetime service is unavailable' end}}
        local lines={}
        local log=Log.new({name='ModCoreTemplates',level=case.level,write=function(line) lines[#lines+1]=line end})
        local fallback=Source.new({},quiet,log)
        assert(fallback.identity(root))
        assert(#lines==case.lines,'identity fallback notice at level '..tostring(case.level))
        if case.lines>0 then
            assert(lines[1]:find('[ModCoreTemplates] TRACE identity: native object lifetimes unavailable',1,true))
        end
        fallback.stop()
    end
end
local function acceptsVersion(capabilityVersion, facadeVersion)
    local candidate={}
    for key,value in pairs(api) do candidate[key]=value end
    candidate.RegisterHook=function() return 1,2 end
    candidate.UnregisterHook=function() end
    candidate.NotifyOnNewObject=function() end
    candidate.UE4SSLuaEventBridge={API_VERSION=facadeVersion,
        GetCapabilities=function()
            return {api=capabilityVersion,object_lifetimes=true}
        end,
        lifetimes=api.UE4SSLuaEventBridge.lifetimes}
    local ok,createdSource=pcall(Source.new,{},candidate)
    if ok then createdSource.stop() end
    return ok
end
assert(acceptsVersion(5,nil) and acceptsVersion(nil,5),
    'either API 5 version field must allow the probed lifetime service')
assert(not acceptsVersion(4,4), 'older API versions must be rejected')
assert(created[classPath] and created['/Script/UMG.WidgetSwitcher'] and created['/Script/UMG.SlotWidget'])
local host=References.new(source)
local lifecycleEvents=0
local subscribe=host.subscribe
host.subscribe=function(callback,epoch)
    return subscribe(function(event)
        lifecycleEvents=lifecycleEvents+1
        callback(event)
    end,epoch)
end
local calls={}
local template={id='visual',category='quickslots',objects={'switcher','slots'},managed=false}
for _,name in ipairs({'attach','update','detach'}) do
    template[name]=function(o,params) calls[#calls+1]={name,o,params} end
end
local runtime=Runtime.new(host,{category},{template})
runtime:select('quickslots',{visual={size=2}})
runtime:start()
assert(finds==2 and #calls==0)
assert(host.screen(host.capture(root)).center==1920)
local wrap=function(o) return {get=function() return o end} end
hooks['/Script/UMG.UserWidget:AddToViewport'].post(wrap(owner))
assert(#calls==1 and calls[1][1]=='attach' and calls[1][2]==root
    and calls[1][3].settings.size==2 and calls[1][3].screen.top==2160
    and calls[1][3].screen.scale==0.5)
source.mutate(function()
    hooks['/Script/UMG.PanelWidget:AddChild'].post(wrap(root),wrap(child))
    hooks['/Script/UMG.PanelWidget:RemoveChild'].post(wrap(root),wrap(child))
    hooks['/Script/UMG.PanelWidget:ClearChildren'].post(wrap(root))
end)
assert(#calls==1, 'template-owned panel mutations must not repeat template callbacks')
assert(lifecycleEvents==2, 'one template mutation must produce one follow-up lifecycle event')
local previousMatches,selectorChecks=source.matches,0
source.matches=function(...)
    selectorChecks=selectorChecks+1
    return previousMatches(...)
end
local unrelatedParent=obj(40,'VerticalBox /Engine/Transient.Other.Panel',
    {['/Script/UMG.Widget']=true})
local unrelatedChild=obj(41,'Border /Engine/Transient.Other.Button',
    {['/Script/UMG.Widget']=true})
unrelatedChild.parent=unrelatedParent
hooks['/Script/UMG.PanelWidget:AddChild'].post(wrap(unrelatedParent),wrap(unrelatedChild))
hooks['/Script/UMG.PanelWidget:RemoveChild'].post(wrap(unrelatedParent),wrap(unrelatedChild))
hooks['/Script/UMG.Widget:RemoveFromParent'].pre(wrap(unrelatedChild))
hooks['/Script/UMG.Widget:RemoveFromParent'].post(wrap(unrelatedChild))
local unrelatedOwner=obj(42,'WBP_Menu_C /Engine/Transient.Other.WBP_Menu_C_1',
    {['/Script/UMG.UserWidget']=true,['/Script/UMG.Widget']=true})
hooks['/Script/UMG.UserWidget:AddToViewport'].post(wrap(unrelatedOwner))
assert(selectorChecks==0, 'unrelated menu widgets must not run quickslot selectors')
assert(#calls==1, 'unrelated menu lifecycle must not reconcile quickslots')
source.matches=previousMatches
assert(not source.ready(child)) -- a parentless non-root child is not ready
child.parent=root
hooks['/Script/UMG.PanelWidget:AddChild'].post(wrap(root),wrap(child))
assert(#calls==2 and calls[2][1]=='attach' and calls[2][2]==child)
child.parent=nil
hooks['/Script/UMG.PanelWidget:RemoveChild'].post(wrap(root),wrap(child))
assert(#calls==3 and calls[3][1]=='detach' and calls[3][2]==child)
hooks['/Script/UMG.Widget:RemoveFromParent'].pre(wrap(owner))
assert(#calls==4 and calls[4][1]=='detach' and calls[4][2]==root)
assert(finds==2) -- transitions rechecked cached objects; no recurring enumeration
-- A map change destroys the old HUD; the new one is announced by object creation.
owner.alive,root.alive,child.alive=false,false,false
local nextWorld=obj(21,'World /Game/NewMap.NewMap')
local nextOwner=obj(30,'WBP_GameHUD_C /Engine/Transient.GameEngine_0.WBP_GameHUD_C_2',
    {['/Script/UMG.UserWidget']=true,['/Script/UMG.Widget']=true})
nextOwner.class=ownerClass; nextOwner.world=nextWorld
local nextTree=obj(31,'WidgetTree /Engine/Transient.GameEngine_0.WBP_GameHUD_C_2.WidgetTree',{},nextOwner)
local nextRoot=obj(32,'WidgetSwitcher /Engine/Transient.GameEngine_0.WBP_GameHUD_C_2.WidgetTree.QuickslotsSwitcher',
    {['/Script/UMG.Widget']=true,['/Script/UMG.WidgetSwitcher']=true},nextTree)
nextRoot.class=widgetClass; nextOwner.WidgetTree=nextTree; nextTree.RootWidget=nextRoot
created[classPath](nextOwner)
assert(finds>2) -- the creation event looks up the new HUD's switcher
assert(#calls==4) -- not ready until the new HUD is shown
nextRoot.parent=nextOwner -- model a WidgetTree child joining a live panel
assert(source.ready(nextRoot)) -- readiness does not require IsInViewport on its owner
nextRoot.parent=nil
local nested=obj(33,'WBP_HUD_Quickslots_C /Engine/Transient.GameEngine_0.WBP_GameHUD_C_2.WidgetTree.WBP_HUD_Quickslots',
    {['/Script/UMG.UserWidget']=true,['/Script/UMG.Widget']=true})
nested.world=nextWorld; nested.parent=nextRoot
assert(source.ready(nested)) -- nested UserWidgets have no viewport flag
hooks['/Script/UMG.Widget:RemoveFromParent'].pre(wrap(nested))
assert(not source.ready(nested)) -- detach before parent is cleared
nested.parent=nil
hooks['/Script/UMG.Widget:RemoveFromParent'].post(wrap(nested))
assert(not source.ready(nested))
nested.parent=nextRoot
hooks['/Script/UMG.PanelWidget:AddChild'].post(wrap(nextRoot),wrap(nested))
assert(source.ready(nested)) -- reparenting clears the removal marker
hooks['/Script/UMG.UserWidget:AddToViewport'].post(wrap(owner))
assert(#calls==4) -- the destroyed HUD is ignored
hooks['/Script/UMG.UserWidget:AddToViewport'].post(wrap(nextOwner))
assert(#calls==5 and calls[5][2]==nextRoot)
runtime:stop(); source.stop()
assert(next(hooks)==nil)
do
    local old=assert(host.capture(nextRoot))
    local oldId=host.identity(old)
    local replacement=obj(nextRoot.address,nextRoot.full,nextRoot.classes,nextTree)
    replacement.class=widgetClass
    nextOwner.WidgetTree.RootWidget=replacement
    local newer=assert(host.capture(replacement))
    assert(host.identity(newer)~=oldId,
        'same-map address and full-name reuse must receive a new identity')
    assert(not host.valid(old) and newer~=old)
    local currentSerial=serialByAddress[replacement.address]
    serialByAddress[replacement.address]=nil
    assert(not host.valid(newer),'native lifetime failure must invalidate the reference')
    assert(#sourceErrors==1 and sourceErrors[1].stage=='identity')
    serialByAddress[replacement.address]=currentSerial
end
local singleton=Source.new({{name='singleton',objects={switcher={source='lookup',object=objectPath}}}},api)
assert(hooks['/Script/UMG.PanelWidget:AddChild']) -- leaf can join after creation
singleton.stop()
assert(next(hooks)==nil)
local unloaded=Source.new({{name='unloaded',objects={widget={source='lookup',class='/Game/HUD/Missing.Missing_C'}}}},api)
assert(#unloaded.find({class='/Game/HUD/Missing.Missing_C'})==0)
unloaded.stop()
do
    -- The HUD owner may be announced before its WidgetTree switcher exists.
    -- A deferred owner event must discover the child without a menu Apply.
    owner.alive,root.alive,nextOwner.alive,nextRoot.alive=false,false,false,false
    local lateOwner=obj(60,'WBP_GameHUD_C /Engine/Transient.GameEngine_0.WBP_GameHUD_C_3',
        {['/Script/UMG.UserWidget']=true,['/Script/UMG.Widget']=true})
    lateOwner.class=ownerClass; lateOwner.world=nextWorld
    local lateTree=obj(61,'WidgetTree /Engine/Transient.GameEngine_0.WBP_GameHUD_C_3.WidgetTree',{},lateOwner)
    local lateRoot=obj(62,'WidgetSwitcher /Engine/Transient.GameEngine_0.WBP_GameHUD_C_3.WidgetTree.QuickslotsSwitcher',
        {['/Script/UMG.Widget']=true,['/Script/UMG.WidgetSwitcher']=true},lateTree)
    lateRoot.class=widgetClass; lateRoot.alive=false
    lateOwner.WidgetTree=lateTree; lateTree.RootWidget=lateRoot
    local pending={}
    function api.ExecuteInGameThread(callback) pending[#pending+1]=callback end
    local delayed=Source.new({category},api)
    delayed.watch({category.objects.switcher})
    local observed={}
    delayed.subscribe(function(event) observed[#observed+1]=event end,function() return 1 end)
    created[classPath](lateOwner)
    assert(#observed==0 and #pending==1)
    pending[1]()
    assert(#observed==0 and #pending==2,
        'owner discovery must retry while the WidgetTree child is unavailable')
    lateRoot.alive=true; lateRoot.parent=lateOwner
    pending[2]()
    assert(#observed==1 and observed[1].kind=='changed' and observed[1].object==lateRoot)
    delayed.stop()
end
print('PASS: widget construction, group parenting, valid detach and hook cleanup')
