package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path

local sessions,events,closed={},{},0
package.loaded['mc.startup_session']={
    validate=function(_,_,templates)
        for _,template in ipairs(templates) do
            if template.invalid then error('invalid provider model') end
        end
    end,
    new=function(_,_,templates,locations,own)
        local session={menu={},runtime={},menuController={},extension={},stops=0}
        function session:start() end
        function session:stop() self.stops=self.stops+1;return true end
        own(session)
        _G.partialSession=session
        if _G.failConstruction then error('injected construction failure') end
        for index,template in ipairs(templates) do
            session[index]={id=template.id,path=locations[index]}
        end
        sessions[#sessions+1]=session
        return session
    end,
}
package.loaded['mc.module_metadata']={apply=function(_,path)
    if path=='bad-metadata' then error('invalid manifest') end
end}
local Bootstrap=require('mc.bootstrap')
local hookLive=0
local goodA={id='A',category='c',loaded=function(onCleanup)
    hookLive=hookLive+1
    onCleanup(function() hookLive=hookLive-1 end)
end}
local badHook={id='bad-hook',category='c',loaded=function(onCleanup)
    hookLive=hookLive+1
    onCleanup(function() hookLive=hookLive-1 end)
    error('loaded hook failed')
end}
local badModel={id='bad-model',category='c',invalid=true,loaded=function(onCleanup)
    hookLive=hookLive+1
    onCleanup(function() hookLive=hookLive-1 end)
end}
local goodB={id='B',category='c'}
local definitions={['good-a']=goodA,['bad-hook']=badHook,['bad-model']=badModel,['good-b']=goodB,
    ['bad-metadata']={id='bad-metadata',category='c'}}
local barrier
local host={onError=function(event) events[#events+1]=event end}
local boot=Bootstrap.new({host=host,categories={},
    execute=function(path)
        if path=='bad-execution' then error('provider execute failed') end
        return definitions[path]
    end,
    subscribeLoopStart=function(callback) barrier=callback;return function() end end,
    closeHost=function() closed=closed+1 end})
for _,path in ipairs({'good-a','bad-execution','bad-metadata','bad-hook','bad-model','good-b'}) do
    boot:registerTemplate(path)
end
barrier()
assert(boot.phase=='running' and sessions[1][1].id=='A' and sessions[1][2].id=='B'
    and sessions[1][3]==nil and hookLive==1)
local failed={}
for _,event in ipairs(events) do
    if event.stage=='provider' then failed[event.provider]=true end
end
assert(failed['bad-execution'] and failed['bad-metadata'] and failed['bad-hook'] and failed['bad-model'])
boot:stop()
assert(sessions[1].stops==1 and hookLive==0 and closed==1)
print('PASS: malformed providers and throwing loaded hooks are isolated with owned cleanup')

local withdrawals,cleanupAttempts,hostAttempts=0,0,0
package.loaded['menu_contributions']={publisher=function()
    return {publish=function() end,withdraw=function() withdrawals=withdrawals+1 end}
end}
_G.failConstruction=true
local second=Bootstrap.new({host=host,categories={},menuShared={},menuRoot='unused',
    execute=function() return {id='C',category='c',loaded=function(onCleanup)
        onCleanup(function()
            cleanupAttempts=cleanupAttempts+1
            if cleanupAttempts==1 then error('hook cleanup failed') end
        end)
    end} end,
    subscribeLoopStart=function(callback) return function() end end,
    closeHost=function()
        hostAttempts=hostAttempts+1
        if hostAttempts==1 then error('host close failed') end
    end})
second:registerTemplate('c')
local ok,why=second:finishLoading()
_G.failConstruction=nil
assert(not ok and tostring(why):find('injected construction failure',1,true))
assert(second.phase=='failed' and _G.partialSession.stops==1
    and withdrawals==0 and cleanupAttempts==1 and hostAttempts==1,
    'a startup that never published has no menu pages to withdraw')
local startupSeen,cleanupSeen=false,0
for _,event in ipairs(events) do
    if event.stage=='startup' and event.message:find('injected construction failure',1,true) then startupSeen=true end
    if event.stage=='cleanup' then cleanupSeen=cleanupSeen+1 end
end
assert(startupSeen and cleanupSeen==2)
second:stop()
assert(withdrawals==0 and cleanupAttempts==2 and hostAttempts==2)
print('PASS: startup error survives independent cleanup failures and unresolved cleanup retries')

package.loaded['mc.startup_session']=nil
package.loaded['mc.module_metadata']=nil
package.loaded['menu_contributions']=nil
local Controller=require('mc.menu_controller')
local attempts=0
local menu={rows={},textSettings={},providers={A={rows={},decode=function() end}},
    decodeState=function() return {} end}
local controller=Controller.new(menu,{commit=function() end})
controller:bind({subscribe=function()
    return function() attempts=attempts+1;if attempts==1 then error('unsubscribe failed') end end
end},function() end)
assert(controller:stop()==false and attempts==1)
assert(controller:stop()==true and attempts==2)
print('PASS: failed Apply unsubscribe remains owned for retry')

package.loaded['mc.menu_model']={build=function()
    return {registry={},categories={},templates={}}
end}
package.loaded['mc.menu']={generate=function() return {rows={},textSettings={}} end}
local runtimeStops,controllerStops=0,0
package.loaded['mc.runtime']={new=function()
    return {stop=function() runtimeStops=runtimeStops+1;return true end}
end}
package.loaded['mc.menu_controller']={new=function()
    return {bind=function() error('binding failed after construction') end,stop=function()
        controllerStops=controllerStops+1
        if controllerStops==1 then error('controller cleanup failed') end
        return true
    end}
end}
local Session=require('mc.startup_session')
local owned
local constructed,constructionError=pcall(Session.new,
    {host={onError=function() end},settingsApi={},queue=function() end},{},{},{},
    function(partial) owned=partial end)
assert(not constructed and tostring(constructionError):find('binding failed after construction',1,true))
assert(owned and owned.menuController and owned.runtime)
local stopped,stopError=owned:stop()
assert(not stopped and tostring(stopError):find('controller cleanup failed',1,true)
    and controllerStops==1 and runtimeStops==1)
assert(owned:stop() and controllerStops==2 and runtimeStops==2)
print('PASS: partial session remains owned and stops independent resources after a late constructor error')
