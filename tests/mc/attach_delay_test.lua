-- A category's attachDelay attaches a new root once no reconcile has reached it for
-- the delay; each reconcile restarts the timer. A settled root attaches at once. While
-- it waits the root is hidden, and it is revealed when it attaches or MCT stops.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local Runtime=require('mc.runtime')

local function fixture(withDefer)
    local root={id='root',class='Root',valid=true,opacity=0.8}
    function root:IsValid() return self.valid end
    function root:GetRenderOpacity() return self.opacity end
    function root:SetRenderOpacity(value) self.opacity=value end
    local host={
        valid=function(v) return v~=nil and v.valid~=false end,
        identity=function(v) return v.id end,
        ready=function() return true end,
        matches=function(v,s) return v.class==s.class end,
        parent=function() end,
        member=function(v,name) return v[name] end,
        find=function() return {root} end,
        watch=function() end,
        screen=function() return {width=1920,height=1080} end,
        subscribe=function() return function() end end,
        onError=function(e) error(e.message) end,
    }
    local timers={}
    local options={}
    if withDefer then options.defer=function(ms,callback) timers[#timers+1]={ms=ms,run=callback} end end
    local attaches,attachOpacity=0,nil
    local category={name='c',attachDelay=2000,objects={root={source='lookup',class='Root'}}}
    local templates={}
    for _,id in ipairs({'a','b'}) do
        templates[#templates+1]={id=id,category='c',objects={'root'},
            attach=function(_,_,saved) attaches=attaches+1; attachOpacity=root.opacity; return saved end}
    end
    category.single=true
    local runtime=Runtime.new(host,{category},templates,nil,options)
    runtime:select('c',{a={}})
    return runtime,root,timers,function() return attaches end,function() return attachOpacity end
end

do
    -- A new root waits; another reconcile restarts the timer; the last timer attaches.
    local runtime,root,timers,attaches,attachOpacity=fixture(true)
    runtime:start()
    assert(attaches()==0 and #timers==1 and timers[1].ms==2000, 'a new root waits for the delay')
    assert(root.opacity==0, 'a waiting root is hidden')
    runtime:event({kind='changed',object=root,epoch=runtime.epoch})
    assert(attaches()==0 and #timers==2, 'another reconcile restarts the timer')
    timers[1].run()
    assert(attaches()==0, 'a superseded timer does nothing')
    assert(root.opacity==0, 'a restarted timer keeps the root hidden')
    timers[2].run()
    assert(attaches()==1, 'the latest timer attaches')
    assert(attachOpacity()==0.8 and root.opacity==0.8, 'the root is revealed before it attaches')
    -- A menu selection on a settled root attaches at once.
    runtime:select('c',{b={}})
    assert(attaches()==2 and #timers==2, 'a settled root does not wait again')
    runtime:stop()
end

do
    -- Without defer there is no delay.
    local runtime,root,timers,attaches=fixture(false)
    runtime:start()
    assert(attaches()==1 and #timers==0 and root.opacity==0.8, 'without defer nothing waits or hides')
    runtime:stop()
end

do
    -- A pending timer after stop attaches nothing.
    local runtime,root,timers,attaches=fixture(true)
    runtime:start()
    assert(root.opacity==0)
    runtime:stop()
    assert(root.opacity==0.8, 'stopping reveals a waiting root')
    timers[1].run()
    assert(attaches()==0 and root.opacity==0.8)
end

do
    -- settle (the loading screen lifting) attaches a waiting root now and reveals it.
    local runtime,root,timers,attaches,attachOpacity=fixture(true)
    runtime:start()
    assert(attaches()==0 and root.opacity==0)
    runtime:settle()
    assert(attaches()==1 and attachOpacity()==0.8, 'settle attaches the waiting root, revealed')
    timers[1].run()
    assert(attaches()==1, 'the superseded timer does nothing after settle')
    runtime:settle()
    assert(attaches()==1, 'settle with nothing waiting does nothing')
    runtime:stop()
end

print('PASS: attachDelay hides a new root until it is quiet, restarts on reconcile, settles once')
