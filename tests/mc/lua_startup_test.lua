package.path = './Scripts/?.lua;./Scripts/vendor/?.lua;' .. package.path
local Startup = require('mc.lua_startup')
local References = require('mc.lua_references')
local Lifetimes = dofile('tests/support/lifetimes.lua')
Lifetimes.install()

local function widget(id)
    return {valid=true, id=id, IsValid=function(self) return self.valid end}
end
local object = widget('1:100:Widget A')
local events, epoch
local source = {
    valid=function(value) return value.valid end,
    identity=function(value) return value.id end,
    ready=function(value) return value.valid end,
    matches=function() return true end,
    parent=function() end,
    find=function() return {object} end,
    child=function(value, class) return value==object and class=='Widget' and object or nil end,
    member=function(value, path) return value==object and path=='Bindings.Left' and object or nil end,
    watch=function() end,
    screen=function() return {width=1920,height=1080,left=0,center=960,right=1920,
        bottom=0,middle=540,top=1080} end,
    subscribe=function(callback, getEpoch)
        events, epoch = callback, getEpoch
        return function() events=nil end
    end,
    onError=function(error) error(error.message) end,
    stop=function() end,
}
local host=References.new(source)
local ref=assert(host.capture(object))
assert(host.capture(object)==ref and host.identity(ref)==object.id)
assert(host.valid(ref) and host.unwrap(ref)==object)
assert(host.child(ref,'Widget')==ref and host.member(ref,'Bindings.Left')==ref)
local seen
host.subscribe(function(event) seen=event end,function() return 1 end)
events({kind='changed',object=object,epoch=epoch()})
assert(seen.object==ref and seen.kind=='changed')
-- A reference to a dead object stays empty, even if the object reports
-- itself valid again; its successor gets a new reference.
object.valid=false
assert(not host.valid(ref) and host.unwrap(ref)==nil)
object.valid=true
assert(not host.valid(ref), 'a dead handle must not come back')
object=widget('2:100:Widget A')
local newer=assert(host.capture(object))
assert(newer~=ref and host.valid(newer))

local jobs={}
local category={id='player.quickslots',objects={root={source='lookup',class='/Script/UMG.UserWidget'}}}
local template={id='example.template',label='Template',category='player.quickslots',
    module='Example',managed=false,objects={'root'},
    attach=function() end,update=function() end,detach=function() end}
local opts={categoryFiles={'category'},
    execute=function(path) return path=='category' and category or template end,
    host={valid=function() return true end,identity=function() return 'object' end,
        ready=function() return true end,matches=function() return true end,
        parent=function() end,find=function() return {} end,
        watch=function() end,
        screen=function() return source.screen() end,
        subscribe=function() return function() end end,onError=function(error) error(error.message) end}}
local bridge=Lifetimes.bridge()
local boot=Startup.start(opts,{ExecuteInGameThread=function(callback) jobs[#jobs+1]=callback end,
    UE4SSLuaEventBridge=bridge})
-- Game-thread ticks during mod startup must not close registration.
assert(boot.phase=='registering' and #jobs==0, 'barrier waits for the bridge loop start')
boot:registerTemplate('template')
bridge.loopStart()
assert(boot.phase=='registering' and #jobs==1, 'loop start hands off to the game thread')
jobs[1]()
assert(boot.phase=='running')
boot:stop()
assert(boot.phase=='stopped')
print('PASS: Lua-only startup and map-scoped references')

do
    -- The object source watches only categories that have templates.
    local notified,queued={}, {}
    local api={
        FindAllOf=function() return {} end,
        NotifyOnNewObject=function(class) notified[#notified+1]=class end,
        RegisterHook=function() return 1,2 end,
        UnregisterHook=function() end,
        IsInGameThread=function() return true end,
        ExecuteInGameThread=function(callback) queued[#queued+1]=callback end,
        UE4SSLuaEventBridge=Lifetimes.bridge(),
    }
    local used={id='player.quickslots',objects={root={source='lookup',class='/Game/HUD/Used.Used_C'}}}
    local unused={id='player.radial',objects={root={source='lookup',class='/Game/HUD/Unused.Unused_C'}}}
    local files={used=used,unused=unused,template=template}
    local live=Startup.start({categoryFiles={'used','unused'},
        execute=function(path) return files[path] end},api)
    assert(#notified==0, 'no object notifications before templates are known')
    live:registerTemplate('template')
    api.UE4SSLuaEventBridge.loopStart()
    table.remove(queued,1)()
    assert(live.phase=='running')
    assert(#notified==1 and notified[1]=='/Game/HUD/Used.Used_C',
        'a category without templates registers no object notification')
    live:stop()
end
print('PASS: object source skips categories without templates')

do
    -- A signal hook only queues: settle and signals run after the hooked call returns.
    local hooks,queued={}, {}
    local api={
        FindAllOf=function() return {} end,
        NotifyOnNewObject=function() end,
        RegisterHook=function(path,callback) hooks[path]=hooks[path] or callback;return 1,2 end,
        UnregisterHook=function() end,
        IsInGameThread=function() return true end,
        ExecuteInGameThread=function(callback) queued[#queued+1]=callback end,
        UE4SSLuaEventBridge=Lifetimes.bridge(),
    }
    local used={id='player.quickslots',objects={root={source='lookup',class='/Game/HUD/Used.Used_C'}}}
    local live=Startup.start({categoryFiles={'used'},execute=function(path)
        return ({used=used,template=template})[path] end},api)
    live:registerTemplate('template')
    api.UE4SSLuaEventBridge.loopStart()
    table.remove(queued,1)()
    assert(live.phase=='running')
    while #queued>0 do table.remove(queued,1)() end
    local calls={}
    live.runtime.settle=function() calls[#calls+1]='settle' end
    live.runtime.signal=function(_,name) calls[#calls+1]=name end
    hooks['/Script/DogwoodUI.DWLoadingScreenWidget:OnFadeOutFinished']()
    assert(#calls==0,'the hook does no runtime work inline')
    while #queued>0 do table.remove(queued,1)() end
    assert(calls[1]=='settle' and calls[2]=='MC_PlayerReady','settle, then the signal, on the game thread')
    live:stop()
end
print('PASS: signal hooks queue settle and signals outside the hooked call')

do
    -- MC_NPCAttackIndicator's source hooks the game only while a template that
    -- takes it is awake, and MCT's stop unhooks it.
    local hooks,queued,removed={}, {}, {}
    local api={
        FindAllOf=function() return {} end,
        NotifyOnNewObject=function() end,
        RegisterHook=function(path,callback) hooks[path]=callback;return 1,2 end,
        UnregisterHook=function(path) removed[#removed+1]=path; hooks[path]=nil end,
        IsInGameThread=function() return true end,
        ExecuteInGameThread=function(callback) queued[#queued+1]=callback end,
        UE4SSLuaEventBridge=Lifetimes.bridge(),
    }
    -- The bridge's Blueprint hooks, as the attack source uses them.
    local bridgeHooks={}
    api.UE4SSLuaEventBridge.GetCapabilities=function() return {hooks=true,hooks_bp=true} end
    api.UE4SSLuaEventBridge.Hooks={Hook=function(path,options)
        bridgeHooks[path]=options
        return {Unhook=function() bridgeHooks[path]=nil; return true end}
    end}
    local function drain() while #queued>0 do table.remove(queued,1)() end end
    local attacks={id='npc.attacks',hooks={wake='MC_CombatStart',sleep='MC_CombatEnd',update='MC_NPCAttackIndicator'},
        objects={root={source='lookup',class='/Game/HUD/Used.Used_C'}}}
    local listener={id='example.listener',label='Listener',category='npc.attacks',module='Example',managed=false,
        objects={'root'},attach=function() end,update=function() end,detach=function() end,
        events={update=function() end}}
    local live=Startup.start({categoryFiles={'attacks'},execute=function(path)
        return ({attacks=attacks,listener=listener})[path] end},api)
    live:registerTemplate('listener')
    api.UE4SSLuaEventBridge.loopStart()
    drain()
    live.runtime:select('npc.attacks',{['example.listener']={}})
    local ICON=require('mc.attack_indicator').ICON
    assert(not bridgeHooks[ICON],'nothing listens outside combat')
    hooks['/Script/DogwoodCombat.PlayerCombatComponent:OnCombatStarted']()
    drain()
    assert(bridgeHooks[ICON],'combat wakes the listener and hooks the icon change')
    hooks['/Script/DogwoodCombat.PlayerCombatComponent:OnCombatEnded']()
    drain()
    assert(not bridgeHooks[ICON],'the listener sleeping unhooks it')
    hooks['/Script/DogwoodCombat.PlayerCombatComponent:OnCombatStarted']()
    drain()
    assert(bridgeHooks[ICON])
    live:stop()
    assert(not bridgeHooks[ICON],'stopping MCT unhooks it')
end
print('PASS: the attack indicator source listens only while a template does')

do
    -- Stopping before loop start cancels the barrier.
    local queued,bridge={},Lifetimes.bridge()
    local early=Startup.start(opts,{ExecuteInGameThread=function(callback) queued[#queued+1]=callback end,
        UE4SSLuaEventBridge=bridge})
    early:stop()
    bridge.loopStart()
    for _,job in ipairs(queued) do job() end
    assert(early.phase=='stopped', 'a stopped session does not start at loop start')
    local ok=pcall(Startup.start,opts,{ExecuteInGameThread=function() end})
    assert(not ok, 'startup without the bridge loop start fails')
end
print('PASS: startup barrier follows the bridge loop start')

local original=package.loaded['mc.lua_startup']
local originalRegistration=package.loaded['mc.registration']
local originalModRef=_G.ModRef
local registered={}
package.loaded['mc.lua_startup']={start=function(options)
    return {registerTemplate=function(_,path)
        registered[#registered+1]={path=path}
        return true
    end}
end}
package.loaded['mc.registration']={
    install=function() return true end,
    publisher=function()
        return {begin=function() end,collect=function() return {} end}
    end,
}
_G.ModRef={}
local root=debug.getinfo(1,'S').source:match('^@(.+)/tests/mc/lua_startup_test%.lua$') or assert(os.getenv('PWD'))
local active=dofile(root..'/Scripts/main.lua')
package.loaded['mc.lua_startup']=original
package.loaded['mc.registration']=originalRegistration
_G.ModRef=originalModRef
assert(type(active)=='table')
assert(#registered==0)
print('PASS: active MCT entry point installs direct template registration')
