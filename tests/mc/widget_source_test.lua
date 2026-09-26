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
        end}
end
function api.IsInGameThread() return true end
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
function api.RegisterLoadMapPreHook(callback) api.mapPre=callback end
function api.RegisterLoadMapPostHook(callback) api.mapPost=callback end
local category={name='quickslots',targets={switcher={object=objectPath},slots={class='/Script/UMG.SlotWidget',within='switcher'}}}
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
    unavailable.RegisterLoadMapPreHook=function() end
    unavailable.RegisterLoadMapPostHook=function() end
    unavailable.MCTOnError=function() end
    local degraded=Source.new({},unavailable)
    assert(degraded.identity(root)==nil,
        'failed native ABI probe must leave object identity unavailable')
    degraded.stop()
end
local function acceptsVersion(capabilityVersion, facadeVersion)
    local candidate={}
    for key,value in pairs(api) do candidate[key]=value end
    candidate.RegisterHook=function() return 1,2 end
    candidate.UnregisterHook=function() end
    candidate.NotifyOnNewObject=function() end
    candidate.RegisterLoadMapPreHook=function() end
    candidate.RegisterLoadMapPostHook=function() end
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
local calls={}
local template={id='visual',category='quickslots',targets={'switcher','slots'}}
for _,name in ipairs({'attach','update','detach'}) do
    template[name]=function(o,params) calls[#calls+1]={name,o,params} end
end
local runtime=Runtime.new(host,{category},{template})
runtime:select('quickslots',{visual={size=2}})
runtime:start()
assert(finds==2 and #calls==0)
assert(host.screen(host.capture(root)).center==960)
local wrap=function(o) return {get=function() return o end} end
hooks['/Script/UMG.UserWidget:AddToViewport'].post(wrap(owner))
assert(#calls==1 and calls[1][1]=='attach' and calls[1][2]==root
    and calls[1][3].settings.size==2 and calls[1][3].screen.top==1080)
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
api.mapPre()
local nextWorld=obj(21,'World /Game/NewMap.NewMap')
local nextOwner=obj(30,'WBP_GameHUD_C /Engine/Transient.GameEngine_0.WBP_GameHUD_C_2',
    {['/Script/UMG.UserWidget']=true,['/Script/UMG.Widget']=true})
nextOwner.class=ownerClass; nextOwner.world=nextWorld
local nextTree=obj(31,'WidgetTree /Engine/Transient.GameEngine_0.WBP_GameHUD_C_2.WidgetTree',{},nextOwner)
local nextRoot=obj(32,'WidgetSwitcher /Engine/Transient.GameEngine_0.WBP_GameHUD_C_2.WidgetTree.QuickslotsSwitcher',
    {['/Script/UMG.Widget']=true,['/Script/UMG.WidgetSwitcher']=true},nextTree)
nextRoot.class=widgetClass; nextOwner.WidgetTree=nextTree; nextTree.RootWidget=nextRoot
api.mapPost(nil,wrap(nextWorld))
assert(finds==4) -- one event-driven snapshot after the world transition
assert(#calls==4)
nextRoot.parent=root -- model a WidgetTree child joining a panel
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
assert(#calls==4) -- old HUD remains valid but belongs to another world
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
local singleton=Source.new({{name='singleton',targets={switcher={object=objectPath}}}},api)
assert(hooks['/Script/UMG.PanelWidget:AddChild']) -- leaf can join after creation
singleton.stop()
assert(next(hooks)==nil)
local unloaded=Source.new({{name='unloaded',targets={widget={class='/Game/HUD/Missing.Missing_C'}}}},api)
assert(#unloaded.find({class='/Game/HUD/Missing.Missing_C'})==0)
unloaded.stop()
print('PASS: widget construction, group parenting, valid detach and hook cleanup')
