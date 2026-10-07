package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local Events=require('mc_events')
local values,handlers={},{}
local api={
    ModRef={GetSharedVariable=function(_,key)return values[key]end,
        SetSharedVariable=function(_,key,value)values[key]=value end},
    RegisterConsoleCommandHandler=function(name,callback)handlers[name]=callback;return true end,
}
local observed
local function f() end
-- MCT starts with no focused group until ModCore Controls reports one.
local state=require('mc.runtime').new({valid=f,identity=f,ready=f,matches=f,parent=f,find=f,
    watch=f,screen=f,subscribe=f,onError=f},{},{}).state
assert(state.controls.group.from==nil and state.controls.group.to==nil)
local hub=Events.hub(api,state,function(event,current)
    observed={event=event,current=current.controls.group.to}
end)
local unregister=hub:register({events={[Events.focus]=function()end}})
local owner={controller={},player={ViewportClient={ProcessConsoleExec=function(_,command)
    return handlers[command]()
end}}}
local publish=Events.publisher(api.ModRef)
-- MCC's first activation of its Default wheel has no previous group.
assert(publish(Events.focus,{group={to=1}},owner))
assert(state.revision==1 and state.controls.group.from==nil
    and state.controls.group.to==1)
assert(observed.event.group.from==nil and observed.current==1)
assert(publish(Events.focus,{group={from=1,to=2}},owner))
assert(state.revision==2 and state.controls.group.from==1
    and state.controls.group.to==2)
assert(observed.event.name=='controls.group.focus' and observed.current==2)
assert(unregister() and hub:stop())
assert(publish(Events.focus,{group={from=2,to=1}},owner))
assert(state.controls.group.to==2,'stopped event hub mutated MCT state')
print('PASS MCT ModCore event state')
