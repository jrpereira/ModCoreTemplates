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
    local multi=options and options.priorities~=nil
    local category={id='c',single=not multi,hooks=hooks,objects={root={source='lookup',class='Root'}}}
    local templates={}
    for _,id in ipairs({'a','b'}) do
        templates[#templates+1]={id=id,category='c',objects={'root'},
            priority=options and options.priorities and options.priorities[id],
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
                update=function(params,event)
                    assert(params.settings and params.state and event.name=='update')
                    log[#log+1]=id..':update '..event.signal..' '..tostring(event.kind)
                    if options and options.failUpdate==id then error('update failed') end
                end,
            }}
    end
    local runtime=Runtime.new(host,{category},templates,nil,{unavailable=options and options.unavailable,
        awakeChanged=options and options.awakeChanged})
    runtime:select('c',multi and {a={},b={}} or {a={}})
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
    local runtime,take=fixture({attach='MC_PlayerReady',wake='MC_CombatStart',sleep='MC_CombatEnd'})
    runtime:start()
    assert(take()=='' and next(runtime:attachments('a'))==nil,'nothing attaches before the player is ready')
    runtime:signal('MC_CombatStart')
    assert(take()=='a:wake MC_CombatStart','combat wakes the template even before it attaches')
    runtime:signal('MC_CombatEnd')
    assert(take()=='a:sleep MC_CombatEnd')
    runtime:signal('MC_PlayerReady')
    assert(take()=='a:attach' and runtime:awake('a')==false,'ready attaches; out of combat it is asleep')
    runtime:stateChanged(FOCUS)
    assert(take()=='','a sleeping template receives no events')
    runtime:signal('MC_CombatStart')
    runtime:stateChanged(FOCUS)
    assert(take()=='a:wake MC_CombatStart, a:focus','an awake template receives its events')
    runtime:signal('MC_CombatStart')
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
    local runtime,take=fixture({attach='MC_PlayerReady',wake='MC_CombatStart',sleep='MC_CombatEnd'})
    runtime:start()
    runtime:signal('MC_PlayerReady')
    take()
    runtime:select('c',{b={}})
    assert(take()=='b:attach','a template selected after ready attaches at once')
    runtime:signal('MC_PlayerReady')
    assert(take()=='','a second ready changes nothing')
    runtime:stop()
end

do
    -- player.quickslots: attach as usual, wake once the player is ready.
    local runtime,take=fixture({wake='MC_PlayerReady'})
    runtime:start()
    assert(take()=='a:attach' and not runtime:awake('a'),'without an attach hook it attaches at once')
    runtime:signal('MC_PlayerReady')
    assert(take()=='a:wake MC_PlayerReady')
    runtime:signal('MC_CombatStart')
    runtime:signal('MC_CombatEnd')
    assert(take()=='' and runtime:awake('a'),'with no opposite, ready keeps it awake')
    runtime:stop()
end

do
    -- wake defaults to attach, and runs before attach on the same signal.
    local runtime,take=fixture({attach='MC_PlayerReady'})
    runtime:start()
    assert(take()=='')
    runtime:signal('MC_PlayerReady')
    assert(take()=='a:wake MC_PlayerReady, a:attach','wake runs before attach')
    runtime:stop()
end

do
    -- The default sleep is wake's opposite.
    local runtime,take=fixture({attach='MC_CombatStart'})
    runtime:start()
    runtime:signal('MC_CombatStart')
    assert(take()=='a:wake MC_CombatStart, a:attach')
    runtime:signal('MC_CombatEnd')
    assert(take()=='a:sleep MC_CombatEnd','the default sleep is the opposite signal')
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
    local runtime,take,errors=fixture({wake='MC_CombatStart'},{failWake=true})
    runtime:start()
    assert(take()=='a:attach')
    runtime:signal('MC_CombatStart')
    assert(take()=='a:wake MC_CombatStart' and #errors==1 and errors[1].stage=='wake')
    runtime:signal('MC_CombatEnd')
    assert(take()=='a:sleep MC_CombatEnd')
    runtime:stop()
end

do
    -- A combat hook that could not be registered: its pair holds for good, so
    -- the template attaches and stays awake instead of never waking, or
    -- never waking again after the first fight.
    local runtime,take=fixture({attach='MC_PlayerReady',wake='MC_CombatStart',sleep='MC_CombatEnd'},
        {unavailable={'MC_CombatStart'}})
    runtime:start()
    assert(take()=='a:wake' and runtime:awake('a'),'awake from the start without combat signals')
    runtime:signal('MC_PlayerReady')
    assert(take()=='a:attach','attach still waits for the player')
    runtime:signal('MC_CombatEnd')
    runtime:signal('MC_CombatStart')
    assert(take()=='' and runtime:awake('a'),'firings of an unavailable pair are ignored')
    runtime:stop()
    -- A sleep other than an unavailable wake's opposite cannot be undone by a
    -- wake that never fires: the template stays awake, and reconcile never fails.
    local errors
    runtime,take,errors=fixture({wake='MC_CombatStart',sleep='MC_PlayerUnready'},
        {unavailable={'MC_CombatStart'}})
    runtime:start()
    assert(take()=='a:wake, a:attach')
    runtime:signal('MC_PlayerUnready')
    assert(take()=='' and runtime:awake('a') and #errors==0,'still awake, without a runtime error')
    runtime:stop()
    -- An unavailable attach signal no longer holds attachments back.
    runtime,take=fixture({attach='MC_PlayerReady'},{unavailable={'MC_PlayerReady'}})
    runtime:start()
    assert(take()=='a:wake, a:attach','attaches at once without the loading screen hook')
    runtime:stop()
end

do
    -- A loading screen fading in ends combat and unreadies the player: a death
    -- and reload never reports combat end.
    local runtime,take=fixture({attach='MC_PlayerReady',wake='MC_CombatStart',sleep='MC_CombatEnd'})
    runtime:start()
    runtime:signal('MC_PlayerReady')
    runtime:signal('MC_CombatStart')
    assert(take()=='a:attach, a:wake MC_CombatStart')
    runtime:signal('MC_CombatEnd')
    runtime:signal('MC_PlayerUnready')
    assert(take()=='a:sleep MC_CombatEnd' and runtime:awake('a')==false,'the fade-in puts it to sleep')
    runtime:signal('MC_PlayerReady')
    assert(take()=='' and runtime:awake('a')==false,'ready again, it sleeps until combat')
    runtime:stop()
    -- Templates awake while the player is ready sleep through the loading screen.
    runtime,take=fixture({wake='MC_PlayerReady'})
    runtime:start()
    assert(take()=='a:attach')
    runtime:signal('MC_PlayerReady')
    assert(take()=='a:wake MC_PlayerReady')
    runtime:signal('MC_PlayerUnready')
    assert(take()=='a:sleep MC_PlayerUnready','asleep while loading')
    runtime:signal('MC_PlayerReady')
    assert(take()=='a:wake MC_PlayerReady','awake again once it lifts')
    runtime:stop()
end

do
    -- An end no hook can fire never ends its start; the start still works.
    local runtime,take=fixture({attach='MC_PlayerReady',wake='MC_CombatStart',sleep='MC_CombatEnd'},
        {unavailable={'MC_CombatEnd','MC_PlayerUnready'}})
    runtime:start()
    assert(take()=='','attach still waits for the player')
    runtime:signal('MC_PlayerReady')
    runtime:signal('MC_CombatStart')
    assert(take()=='a:attach, a:wake MC_CombatStart' and runtime:awake('a'),'the start still wakes it')
    runtime:stop()
end

do
    -- Invalid hooks fail when the category loads.
    local function rejects(hooks,pattern)
        local ok,why=pcall(fixture,hooks)
        assert(not ok and tostring(why):find(pattern,1,true),tostring(why))
    end
    rejects({start='MC_PlayerReady'},'unknown hook start')
    rejects({attach='PlayerReady'},'unknown signal PlayerReady')
    rejects({sleep='MC_CombatEnd'},'sleep requires wake or attach')
    rejects({wake='MC_PlayerReady',sleep='MC_PlayerReady'},'sleep must differ from wake')
    rejects({wake='MC_CombatStart',update='MC_CombatStart'},'unknown signal MC_CombatStart')
    rejects({wake='MC_NPCAttackIndicator'},'unknown signal MC_NPCAttackIndicator')
    local ok,why=pcall(function() fixture({attach='MC_PlayerReady'})[1]:signal('Nope') end)
    assert(not ok,'an unknown signal is refused')
end

do
    -- update: an update event reaches the awake templates of the categories that
    -- take it, at once, with its data; awakeChanged follows wake and sleep, so a
    -- source listens only while a template does.
    local changes={}
    local runtime,take,errors=fixture({attach='MC_PlayerReady',wake='MC_CombatStart',sleep='MC_CombatEnd',
        update='MC_NPCAttackIndicator'},{failUpdate='a',awakeChanged=function(rt)
            changes[#changes+1]=rt:listening('MC_NPCAttackIndicator')
        end})
    runtime:emit('MC_NPCAttackIndicator',{kind='arrow'})
    assert(take()=='','nothing is delivered before the runtime starts')
    runtime:start()
    runtime:signal('MC_PlayerReady')
    take()
    assert(not runtime:listening('MC_NPCAttackIndicator') and #changes==0,'nobody listens outside combat')
    runtime:emit('MC_NPCAttackIndicator',{kind='arrow'})
    assert(take()=='','a sleeping template receives no update')
    runtime:signal('MC_CombatStart')
    assert(take()=='a:wake MC_CombatStart' and changes[1]==true,'waking makes the category listen')
    local indicator={live=true}
    local event={kind='critical',indicator=indicator}
    runtime:emit('MC_NPCAttackIndicator',event)
    assert(take()=='a:update MC_NPCAttackIndicator critical','the awake template receives it in the same call')
    assert(event.indicator==indicator,'its data reaches the template as given, not copied')
    assert(#errors==1 and errors[1].stage=='update' and errors[1].template=='a','a failing update is reported')
    runtime:signal('MC_CombatEnd')
    assert(take()=='a:sleep MC_CombatEnd' and changes[2]==false,'the last sleep stops the listening')
    local ok=pcall(runtime.emit,runtime,'MC_CombatStart',{})
    assert(not ok,'only update events are emitted')
end
do
    -- A category without an update hook never receives one.
    local runtime,take=fixture({wake='MC_CombatStart'})
    runtime:start()
    runtime:signal('MC_CombatStart')
    take()
    runtime:emit('MC_NPCAttackIndicator',{kind='arrow'})
    assert(take()=='' and not runtime:listening('MC_NPCAttackIndicator'),'no update hook, no update')
end

do
    -- Templates in a category wake, sleep and receive events in priority
    -- order, lowest first, whatever their ids.
    local runtime,take=fixture({wake='MC_CombatStart',update='MC_NPCAttackIndicator'},{priorities={a=11,b=10}})
    runtime:start()
    assert(take()=='b:attach, a:attach','attach follows priority')
    runtime:signal('MC_CombatStart')
    local woke=take()
    assert(woke=='b:wake MC_CombatStart, a:wake MC_CombatStart','wake follows priority: '..woke)
    runtime:emit('MC_NPCAttackIndicator',{kind='arrow'})
    assert(take()=='b:update MC_NPCAttackIndicator arrow, a:update MC_NPCAttackIndicator arrow',
        'updates follow priority')
    runtime:stateChanged(FOCUS)
    assert(take()=='b:focus, a:focus','other events follow priority')
    -- Without a priority a template comes after those with one.
    runtime,take=fixture({wake='MC_CombatStart'},{priorities={b=10}})
    runtime:start()
    take()
    runtime:signal('MC_CombatStart')
    assert(take()=='b:wake MC_CombatStart, a:wake MC_CombatStart','a template without priority comes last')
    local ok=pcall(fixture,{wake='MC_CombatStart'},{priorities={a='high'}})
    assert(not ok,'a priority must be a number')
end

print('PASS: category hooks gate attach on signals and deliver wake/sleep and update as template events in priority order')
