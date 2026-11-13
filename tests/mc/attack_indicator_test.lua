-- MC_NPCAttackIndicator's source: the indicator's icon changes, hooked through
-- UE4SSLuaEventBridge only between start and stop, become update events.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local Attacks=require('mc.attack_indicator')

local objects={}
-- Fake UObjects: visible, opaque, with parents.
local function object(name,fields)
    local value=fields or {}
    value.name=name
    if value.visible==nil then value.visible=true end
    local methods={}
    function methods:IsValid() return not self.gone end
    function methods:GetFullName() return 'Class '..self.name end
    function methods:IsVisible() return self.visible end
    function methods:GetRenderOpacity() return 1 end
    function methods:GetParent() return self.parent end
    return setmetatable(value,{__index=methods})
end
local MAIN,TWIN='/Game/HUD.WBP_CombatTargetIndicator_C_1','/Game/HUD.WBP_CombatTargetIndicator_C_2'
local main,twin=object(MAIN),object(TWIN)
objects[MAIN],objects[TWIN]=main,twin

-- A fake hook bridge: one hook per path, delivered by hand like the engine tick.
local hooked,unhooked,caps={},0,{hooks=true,hooks_bp=true}
local bridge={
    GetCapabilities=function() return caps end,
    Hooks={Hook=function(path,options)
        assert(options.pre and options.object_paths)
        if path==Attacks.ICON then assert(options.params[1]=='IconType')
        else assert(path==Attacks.ATTACK_TASK and options.params==nil,'the attack task has no params') end
        local handle={}
        function handle:Unhook() hooked[path]=nil; unhooked=unhooked+1; return true end
        hooked[path]=options
        return handle
    end},
}
local api={UE4SSLuaEventBridge=bridge,StaticFindObject=function(path) return objects[path] end}
local events,logged={},{}
local log=setmetatable({},{__index=function(_,level)
    return function(...) logged[#logged+1]=level..' '..table.concat({...}) end
end})
local source=Attacks.new(api,function(event) events[#events+1]=event end,log)
local function take()
    local parts={}
    for _,event in ipairs(events) do
        local text=event.kind
        if event.direction then text=text..' '..event.direction end
        if event.reason then text=text..' '..event.reason end
        if event.active~=nil then text=text..' '..tostring(event.active) end
        if event.path then text=text..' '..(event.path==MAIN and 'main' or event.path==TWIN and 'twin' or event.path) end
        parts[#parts+1]=text
    end
    events={}
    return table.concat(parts,', ')
end
-- The bridge delivering one icon change, as it copies it: an enum as value and name.
local frame=100
local function icon(path,value,at)
    hooked[Attacks.ICON].pre({phase='pre',object={address=1,path=path},params={IconType={value=value,name='x'}},
        frame=at or frame})
end
local STUB_A='/Game/Map.ActorStubSystemImpl_0.Guard_A'
local STUB_B='/Game/Map.ActorStubSystemImpl_0.Guard_B'
local function task(stub,at,n)
    hooked[Attacks.ATTACK_TASK].pre({phase='pre',object={address=2,path=stub..'.LTT_Attack_C_'..(n or 0)},frame=at or frame})
end

assert(next(hooked)==nil,'nothing is hooked before start')
assert(source:start() and hooked[Attacks.ICON] and hooked[Attacks.ATTACK_TASK],'start hooks the icon change and the attack task')
assert(source:start(),'a second start keeps the hook')

-- An attack from the left: shown, then its parry window, then resolved.
icon(MAIN,1)
assert(events[1].indicator==main,'the event carries the live indicator')
assert(take()=='arrow 3 main','icon 1 is an attack on the left arrow')
icon(MAIN,1)
assert(take()=='','a repeated state changes nothing')
icon(MAIN,5)
assert(take()=='critical 3 main','icon 5 opens its parry window')
icon(MAIN,5)
assert(take()=='','a critical attack stays critical')
icon(MAIN,0)
assert(take()=='resolve sword main','defending ends the attack')
icon(MAIN,0)
assert(take()=='','defending with no attack resolves nothing')
-- Directions follow ARROWS; a parry window seen first also shows its attack.
icon(MAIN,3) icon(MAIN,4)
assert(take()=='arrow 1 main, arrow 2 main','top is 1, bottom 2; a new direction is a new attack')
icon(TWIN,6)
assert(take()=='arrow 4 twin, critical 4 twin','another indicator is its own; a window alone shows its arrow')
-- A weak spot means nothing is coming.
icon(TWIN,12)
assert(take()=='resolve sword twin')

-- A hidden indicator's attack is over, and its states are not on screen.
icon(TWIN,2)
take()
twin.visible=false
icon(TWIN,6)
assert(take()=='resolve hidden twin')
icon(TWIN,2)
assert(take()=='','a hidden attack is not shown')

-- The unblockable skull: shown by a visible indicator, taken away by it.
icon(TWIN,9)
assert(take()=='','a hidden skull is not shown')
icon(MAIN,9)
assert(events[1].indicator==main and take()=='unblockable true main')
icon(MAIN,9)
assert(take()=='','a skull shows once')
icon(MAIN,0)
assert(take()=='unblockable false main, resolve sword main',
    'defending takes the skull away and resolves the attack')

-- A skull followed straight by an attack is taken away before the arrow.
icon(MAIN,9)
take()
icon(MAIN,2)
assert(take()=='unblockable false main, arrow 4 main','any other state ends the skull')
icon(MAIN,0)
take()

-- An indicator that is gone forgets its attack quietly.
icon(MAIN,1)
take()
objects[MAIN]=nil
icon(MAIN,0)
assert(take()=='','a missing indicator emits nothing')
objects[MAIN]=main

-- stub: the attack task begun in the icon's frame or the one before.
assert(Attacks.stubOf(STUB_A..'.LTT_Attack_C_12')==STUB_A and Attacks.stubOf(STUB_A)==nil)
icon(MAIN,0) take()
frame=200
task(STUB_A,200)
icon(MAIN,1,200)
assert(events[1].stub==STUB_A and take()=='arrow 3 main','an arrow in the task\'s frame carries its stub')
icon(MAIN,5,260)
assert(events[1].stub==STUB_A and take()=='critical 3 main','a later critical reuses its arrow\'s stub')
icon(MAIN,0,261) take()
task(STUB_A,300)
icon(MAIN,2,301)
assert(events[1].stub==STUB_A,'the next frame still pairs') take()
icon(MAIN,0,302) take()
task(STUB_A,400)
icon(MAIN,3,402)
assert(events[1].kind=='arrow' and events[1].stub==nil,'two frames later nothing pairs') take()
icon(MAIN,0,403) take()
-- Two enemies' tasks in the window: no guess. The same enemy twice is fine.
task(STUB_A,500) task(STUB_B,501)
icon(MAIN,4,501)
assert(events[1].stub==nil,'two stubs in the window give none') take()
icon(MAIN,0,502) take()
task(STUB_A,600) task(STUB_A,600,1)
icon(MAIN,1,600)
assert(events[1].stub==STUB_A,'one stub twice still pairs') take()
icon(MAIN,0,601) take()
-- The latest task wins over one long before it.
task(STUB_B,700) task(STUB_A,742)
icon(MAIN,9,742)
assert(events[1].kind=='unblockable' and events[1].stub==STUB_A,'the skull carries the latest stub') take()
icon(MAIN,0,743) take()
-- A delivery without a frame pairs nothing.
task(STUB_A,800)
hooked[Attacks.ICON].pre({object={path=MAIN},params={IconType={value=1}}})
assert(events[1].kind=='arrow' and events[1].stub==nil) take()
icon(MAIN,0) take()
frame=100

-- Malformed deliveries and a failing receiver never escape; one error per kind.
hooked[Attacks.ICON].pre({object={path=MAIN},params={}})
assert(take()=='','a call without an icon is ignored')
local broken=Attacks.new(api,function() error('receiver failed') end,log)
source:stop()
assert(broken:start())
for _=1,3 do icon(MAIN,(_%2==1) and 1 or 0) end
local errors=0
for _,line in ipairs(logged) do if line:match('^error') then errors=errors+1 end end
assert(errors==1,'one error per kind, not one per call')
broken:stop()
local warned=0
for _,line in ipairs(logged) do if line:match('^warn') and line:match('2 more times') then warned=warned+1 end end
assert(warned==1,'repeated faults are counted at stop')

-- Stop unhooks and forgets: after a new start the same state is a new attack.
assert(next(hooked)==nil and unhooked==4,'stop removes both hooks')
source:stop()
assert(unhooked==4,'a second stop has nothing to remove')
events={}
source:start()
icon(MAIN,2)
assert(take()=='arrow 4 main','state does not survive a stop')
-- A delivery queued before stop arrives after it and is dropped.
local pending=hooked[Attacks.ICON].pre
source:stop()
pending({object={path=MAIN},params={IconType={value=1}}})
assert(take()=='','nothing is emitted after stop')

-- Without Blueprint hooks the source stays stopped and says why.
caps={hooks=false,hooks_reason='Hooks disabled'}
local refusing=Attacks.new(api,function() end,log)
assert(refusing:start()==false and not refusing.active,'no bridge hooks, no source')
assert(logged[#logged]:match('Hooks disabled'),'the bridge reason is logged')

-- An attack task hook the bridge refuses leaves the events without stub.
caps={hooks=true,hooks_bp=true}
local realHook=bridge.Hooks.Hook
bridge.Hooks.Hook=function(path,options)
    if path==Attacks.ATTACK_TASK then return nil,'no task' end
    return realHook(path,options)
end
local stubless=Attacks.new(api,function(event) events[#events+1]=event end,log)
assert(stubless:start() and hooked[Attacks.ICON] and not hooked[Attacks.ATTACK_TASK],'the icon hook stands alone')
local refused=false
for _,line in ipairs(logged) do refused=refused or (line:match('^warn') and line:match('no task')~=nil) end
assert(refused,'the refusal is logged')
icon(MAIN,1)
assert(take()=='arrow 3 main')
stubless:stop()
bridge.Hooks.Hook=realHook

print('PASS: attack indicator source emits arrow, critical, resolve and unblockable events from the icon, with the attacker\'s stub')
