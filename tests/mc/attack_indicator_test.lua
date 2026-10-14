-- MC_NPCAttackIndicator's source: the game's indicator styling call and early
-- warning, hooked only between start and stop, become update events emitted
-- inside the call.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local Attacks=require('mc.attack_indicator')

FName=function(value)
    return {ToString=function() return value end,GetComparisonIndex=function() return 'index:'..value end}
end
local objects={}
StaticFindObject=function(path) return objects[path] end

-- Fake UObjects: visible, opaque, with parents and outers.
local function object(name,fields)
    local value=fields or {}
    value.name=name
    if value.visible==nil then value.visible=true end
    local methods={}
    function methods:IsValid() return true end
    function methods:GetFullName() return 'Class '..self.name end
    function methods:IsVisible() return self.visible end
    function methods:GetRenderOpacity() return 1 end
    function methods:GetParent() return self.parent end
    function methods:GetOuter() return self.outer end
    function methods:GetOwner() return self.owner end
    function methods:GetFName() return FName(self.fname or self.name:match('([^%.]+)$')) end
    return setmetatable(value,{__index=methods})
end
local DIM,LIT={R=0.2,G=0.1,B=0,A=1},{R=1,G=0.67,B=0.19,A=1}
local function indicator(name)
    local widget=object('/Game/HUD.'..name)
    local tree=object('/Game/HUD.'..name..'.WidgetTree',{outer=widget})
    for _,key in ipairs(Attacks.ARROWS) do
        widget[key]=object('/Game/HUD.'..name..'.WidgetTree.'..key,{outer=tree,parent=widget,ColorAndOpacity=DIM})
    end
    widget.Reticle=object('/Game/HUD.'..name..'.WidgetTree.Reticle',{outer=tree,parent=widget})
    objects['/Game/HUD.'..name]=widget
    return widget
end
local main=indicator('WBP_CombatTargetIndicator_C_1')
local twin=indicator('WBP_CombatTargetIndicator_C_2')
local MAIN,TWIN='/Game/HUD.WBP_CombatTargetIndicator_C_1','/Game/HUD.WBP_CombatTargetIndicator_C_2'

local hooks,removed={},0
local delayed={}
local api={
    RegisterHook=function(path,pre,post) hooks[path]={pre,post}; return 1,2 end,
    UnregisterHook=function(path,pre,post) assert(hooks[path] and pre==1 and post==2); hooks[path]=nil; removed=removed+1 end,
    ExecuteWithDelay=function(_,callback) delayed[#delayed+1]=callback end,
    ExecuteInGameThread=function(callback) callback() end,
}
local function run()
    local batch=delayed
    delayed={}
    for _,callback in ipairs(batch) do callback() end
end
local events,logged={},{}
local log=setmetatable({},{__index=function(_,level)
    return function(...) logged[#logged+1]=level..' '..table.concat({...}) end
end})
local source=Attacks.new(api,function(event) events[#events+1]=event end,log)
-- A summary of the events since the last take.
local function take()
    local parts={}
    for _,event in ipairs(events) do
        local text=event.kind
        if event.direction then text=text..' '..event.direction end
        if event.reason then text=text..' '..event.reason end
        if event.active~=nil then text=text..' '..tostring(event.active) end
        if event.late then text=text..' late' end
        if event.path then text=text..' '..(event.path==MAIN and 'main' or event.path==TWIN and 'twin' or event.path) end
        parts[#parts+1]=text
    end
    events={}
    return table.concat(parts,', ')
end
local function param(value) return {get=function() return value end} end
local STYLING=Attacks.STYLING
-- The game styling an arrow: the before callback sees the call, the after one
-- sees the arrow once its colour is set.
local function style(target,key,color)
    local image=target[key]
    if color then image.ColorAndOpacity=color end
    hooks[STYLING][1](param(image),param({}))
    hooks[STYLING][2](param(image),param({}))
end
local function centre(target,sprite)
    hooks[STYLING][1](param(target.Reticle),param(object('/Game/Atlas.'..sprite)))
    hooks[STYLING][2](param(target.Reticle),param({}))
end

assert(next(hooks)==nil,'nothing is hooked before start')
assert(source:start() and hooks[STYLING] and hooks[Attacks.EARLY],'start hooks the styling call and the early warning')
assert(source:start(),'a second start keeps the hooks')

-- Other atlas images and images outside an indicator are ignored.
hooks[STYLING][1](param(object('/Game/HUD.Portrait')),param({}))
local stray=object('/Game/Menu.WidgetTree.TopArrow',{outer=object('/Game/Menu.WidgetTree',{outer=object('/Game/Menu')}),
    ColorAndOpacity=LIT})
hooks[STYLING][2](param(stray),param({}))
assert(take()=='','only indicator images count')

-- An attack: the first styling shows it, the second turns it critical, later ones change nothing.
style(main,'LeftArrow',LIT)
assert(events[1].indicator==main and events[1].late==false,'the event carries the live indicator')
assert(take()=='arrow 3 main','a lit arrow is an attack from its direction')
style(main,'LeftArrow')
assert(take()=='critical 3 main','its second styling is the critical one')
style(main,'LeftArrow')
assert(take()=='','a critical attack stays critical')
-- The arrow going dark ends it; the indicator is checked again next frame.
style(main,'LeftArrow',DIM)
assert(take()=='resolve 3 dark main' and #delayed==1,'a dark arrow ends its attack')
main.TopArrow.ColorAndOpacity=LIT
run()
assert(take()=='arrow 1 late main','an arrow lit by next frame is an attack')
-- Another indicator's attack is its own.
style(twin,'RightArrow',LIT)
assert(take()=='arrow 4 twin')
-- The centre icon turning to the sword resolves the indicator's attack.
centre(main,'T_Combat_Icon_Sword')
assert(take()=='resolve sword main')
centre(main,'T_Combat_Icon_Sword')
assert(take()=='','the sword with no attack resolves nothing')
-- A hidden indicator's attack is over.
twin.visible=false
style(twin,'RightArrow')
assert(take()=='resolve hidden twin')

-- The unblockable skull: shown by a visible indicator, taken away only by the
-- one that showed it; a hidden twin's skull is not on screen.
centre(twin,'T_Combat_Icon_SkullRed')
assert(take()=='','a hidden skull is not shown')
centre(main,'T_Combat_Icon_SkullRed')
assert(events[1].indicator==main and take()=='unblockable true main')
centre(main,'T_Combat_Icon_SkullRed')
assert(take()=='','a skull shows once')
centre(twin,'T_Combat_Icon_Sword')
assert(take()=='','a hidden twin does not take it away')
centre(main,'T_Combat_Icon_Sword')
assert(take()=='unblockable false main, resolve sword main',
    'the indicator that showed it takes it away, and the sword resolves the attack')

-- The early warning: the game's 1-4 become arrow directions, with the attacker.
local attacker=object('/Game/Map.Soldier')
local component=object('/Game/Map.Soldier.Combat',{owner=attacker})
hooks[Attacks.EARLY][1](param({}),param({Direction=3,bIsUnblockable=false,Instigator=component}))
assert(events[1].attacker==attacker and events[1].unblockable==false,'the early warning names its attacker')
assert(take()=='early 1','early direction 3 is the top arrow')
hooks[Attacks.EARLY][1](param({}),param({Direction=0,bIsUnblockable=true}))
assert(events[1].attacker==nil and events[1].unblockable and take()=='early','an unblockable early warning')

-- Events count up; a failing receiver or a fault in the call never escapes it,
-- and each kind of fault is logged once.
local broken={get=function() error('unreadable') end}
for _=1,3 do
    hooks[STYLING][1](broken,param({}))
    hooks[STYLING][2](broken,param({}))
end
local errors=0
for _,line in ipairs(logged) do if line:match('^error') then errors=errors+1 end end
assert(errors==2,'one error per kind, not one per call')

-- Stop unhooks and forgets: after a new start the same arrow is a new attack.
style(main,'BottomArrow',LIT)
take()
source:stop()
assert(removed==2 and next(hooks)==nil,'stop removes both hooks')
local warned=0
for _,line in ipairs(logged) do if line:match('^warn') and line:match('2 more times') then warned=warned+1 end end
assert(warned==2,'repeated faults are counted at stop')
source:stop()
assert(removed==2,'a second stop has nothing to remove')
source:start()
style(main,'BottomArrow')
assert(take()=='arrow 2 main','state does not survive a stop')
source:stop()

-- A styling hook the game refuses leaves the source stopped.
local refusing=Attacks.new({RegisterHook=function() error('no such function') end},function() end,log)
assert(refusing:start()==false and not refusing.active,'an unavailable styling call does not start')

print('PASS: attack indicator source emits arrow, critical, resolve, unblockable and early events inside the call')
