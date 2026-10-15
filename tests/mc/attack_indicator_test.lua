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
        assert(options.pre and options.params[1]=='IconType' and options.object_paths)
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
local function icon(path,value)
    hooked[Attacks.ICON].pre({phase='pre',object={address=1,path=path},params={IconType={value=value,name='x'}}})
end

assert(next(hooked)==nil,'nothing is hooked before start')
assert(source:start() and hooked[Attacks.ICON],'start hooks the icon change')
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
assert(next(hooked)==nil and unhooked==2,'stop removes the hook')
source:stop()
assert(unhooked==2,'a second stop has nothing to remove')
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

print('PASS: attack indicator source emits arrow, critical, resolve and unblockable events from the icon')
