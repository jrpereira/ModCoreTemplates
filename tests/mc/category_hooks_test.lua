-- category.hooks time templates by MCT's signals: attach holds new attachments
-- until its signal; wake and sleep reach each selected template once as its
-- wake and sleep events, and gate its other events. A signal holds until its
-- opposite fires.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local Runtime=require('mc.runtime')

local function fixture(hooks,options)
    local root={id='root',class='Root',valid=true}
    function root:IsValid() return self.valid end
    local errors={}
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
        onError=function(e) errors[#errors+1]=e end,
    }
    local log={}
    local category={name='c',single=true,hooks=hooks,objects={root={source='lookup',class='Root'}}}
    local templates={}
    for _,id in ipairs({'a','b'}) do
        templates[#templates+1]={id=id,category='c',objects={'root'},
            attach=function(_,_,saved) log[#log+1]=id..':attach'; return saved end,
            events={
                wake=function(params,event)
                    assert(params.settings and params.state and event.name=='wake')
                    log[#log+1]=id..':wake'..(event.signal and ' '..event.signal or '')
                    if options and options.failWake then error('wake failed') end
                end,
                sleep=function(_,event)
                    log[#log+1]=id..':sleep'..(event.signal and ' '..event.signal or '')
                end,
                ['controls.group.focus']=function() log[#log+1]=id..':focus' end,
            }}
    end
    local runtime=Runtime.new(host,{category},templates,nil)
    runtime:select('c',{a={}})
    local function take()
        local result=table.concat(log,', ')
        for index=#log,1,-1 do log[index]=nil end
        return result
    end
    return runtime,take,errors
end
local FOCUS={name='controls.group.focus',group={from=1,to=2}}

do
    -- npc.attacks: attach on ready, awake during combat.
    local runtime,take=fixture({attach='MCTPlayerReady',wake='MCTCombatStart',sleep='MCTCombatEnd'})
    runtime:start()
    assert(take()=='' and next(runtime:attachments('a'))==nil,'nothing attaches before the player is ready')
    runtime:signal('MCTCombatStart')
    assert(take()=='a:wake MCTCombatStart','combat wakes the template even before it attaches')
    runtime:signal('MCTCombatEnd')
    assert(take()=='a:sleep MCTCombatEnd')
    runtime:signal('MCTPlayerReady')
    assert(take()=='a:attach' and runtime:awake('a')==false,'ready attaches; out of combat it is asleep')
    runtime:stateChanged(FOCUS)
    assert(take()=='','a sleeping template receives no events')
    runtime:signal('MCTCombatStart')
    runtime:stateChanged(FOCUS)
    assert(take()=='a:wake MCTCombatStart, a:focus','an awake template receives its events')
    runtime:signal('MCTCombatStart')
    assert(take()=='','a repeated signal changes nothing')
    -- Switching templates: the old one detaches before it sleeps; the new
    -- one wakes before it attaches.
    runtime:select('c',{b={}})
    assert(take()=='a:sleep, b:wake, b:attach')
    runtime:stop()
    assert(take()=='b:sleep','stopping puts the awake template to sleep')
end

do
    -- Ready has no opposite: once fired it holds, so a later selection attaches at once.
    local runtime,take=fixture({attach='MCTPlayerReady',wake='MCTCombatStart',sleep='MCTCombatEnd'})
    runtime:start()
    runtime:signal('MCTPlayerReady')
    take()
    runtime:select('c',{b={}})
    assert(take()=='b:attach','a template selected after ready attaches at once')
    runtime:signal('MCTPlayerReady')
    assert(take()=='','a second ready changes nothing')
    runtime:stop()
end

do
    -- player.quickslots: attach as usual, wake once the player is ready.
    local runtime,take=fixture({wake='MCTPlayerReady'})
    runtime:start()
    assert(take()=='a:attach' and not runtime:awake('a'),'without an attach hook it attaches at once')
    runtime:signal('MCTPlayerReady')
    assert(take()=='a:wake MCTPlayerReady')
    runtime:signal('MCTCombatStart')
    runtime:signal('MCTCombatEnd')
    assert(take()=='' and runtime:awake('a'),'with no opposite, ready keeps it awake')
    runtime:stop()
end

do
    -- wake defaults to attach, and runs before attach on the same signal.
    local runtime,take=fixture({attach='MCTPlayerReady'})
    runtime:start()
    assert(take()=='')
    runtime:signal('MCTPlayerReady')
    assert(take()=='a:wake MCTPlayerReady, a:attach','wake runs before attach')
    runtime:stop()
end

do
    -- The default sleep is wake's opposite.
    local runtime,take=fixture({attach='MCTCombatStart'})
    runtime:start()
    runtime:signal('MCTCombatStart')
    assert(take()=='a:wake MCTCombatStart, a:attach')
    runtime:signal('MCTCombatEnd')
    assert(take()=='a:sleep MCTCombatEnd','the default sleep is the opposite signal')
    runtime:stop()
end

do
    -- Without hooks a selected template is awake from the start, as before.
    local runtime,take=fixture(nil)
    runtime:start()
    assert(take()=='a:wake, a:attach' and runtime:awake('a'))
    runtime:stateChanged(FOCUS)
    assert(take()=='a:focus')
    runtime:stop()
    assert(take()=='a:sleep')
end

do
    -- A failing wake is reported; the template still counts as awake, so
    -- its sleep can undo a partial wake.
    local runtime,take,errors=fixture({wake='MCTCombatStart'},{failWake=true})
    runtime:start()
    assert(take()=='a:attach')
    runtime:signal('MCTCombatStart')
    assert(take()=='a:wake MCTCombatStart' and #errors==1 and errors[1].stage=='wake')
    runtime:signal('MCTCombatEnd')
    assert(take()=='a:sleep MCTCombatEnd')
    runtime:stop()
end

do
    -- Invalid hooks fail when the category loads.
    local function rejects(hooks,pattern)
        local ok,why=pcall(fixture,hooks)
        assert(not ok and tostring(why):find(pattern,1,true),tostring(why))
    end
    rejects({start='MCTPlayerReady'},'unknown hook start')
    rejects({attach='PlayerReady'},'unknown signal PlayerReady')
    rejects({sleep='MCTCombatEnd'},'sleep requires wake or attach')
    rejects({wake='MCTPlayerReady',sleep='MCTPlayerReady'},'sleep must differ from wake')
    local ok,why=pcall(function() fixture({attach='MCTPlayerReady'})[1]:signal('Nope') end)
    assert(not ok,'an unknown signal is refused')
end

print('PASS: category hooks gate attach on signals and deliver wake/sleep as template events')
