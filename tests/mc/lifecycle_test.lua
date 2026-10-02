package.path = './Scripts/?.lua;./Scripts/?/init.lua;' .. package.path
local Runtime = require('mc.runtime')
local Selectors = require('mc.selectors')
local Bootstrap = require('mc.bootstrap')
local passed = 0
local function test(name, body)
    local ok, why = pcall(body)
    assert(ok, name .. ': ' .. tostring(why))
    passed = passed + 1
end
local function fixture(single, paths)
    local objects, calls, errors = {}, {}, {}
    local sink, epoch, scans, unsubs = nil, nil, 0, 0
    local host = {
        valid=function(o) return o ~= nil and o.valid ~= false end,
        identity=function(o) assert(o.valid ~= false, 'identity read after invalidation'); return o.id end,
        ready=function(o) return o.ready ~= false end,
        matches=function(o, s) return s.object == o.path or s.class ~= nil and s.class == o.class end,
        parent=function(o) return o.parent end,
        watch=function() end,
        screen=function() return {width=1920,height=1080,left=0,center=960,right=1920,
            bottom=0,middle=540,top=1080} end,
        find=function(s)
            scans = scans + 1
            local found = {}
            for _, o in ipairs(objects) do
                if o.valid ~= false and (s.object == o.path or s.class ~= nil and s.class == o.class) then found[#found + 1] = o end
            end
            return found
        end,
        subscribe=function(callback, getEpoch) sink, epoch = callback, getEpoch; return function() unsubs=unsubs+1 end end,
        onError=function(e) errors[#errors + 1] = e end,
    }
    local categories = {{name='player.quickslots', single=single, objects=paths or {slots={source='lookup',class='Slot'}}}}
    local function template(id)
        local targets={}
        for name in pairs(categories[1].objects) do targets[#targets+1]=name end
        local t = {id=id, category='player.quickslots', module='Test',
            objects=targets, managed=false}
        t.attach = function(o, params)
            assert(o.valid ~= false)
            assert(params.screen.center == 960)
            calls[#calls + 1] = id .. ':attach:' .. o.id .. ':' .. tostring(params.settings.size)
        end
        t.update = function(o)
            assert(o.valid ~= false)
            calls[#calls + 1] = id .. ':update:' .. o.id .. ':' .. tostring(t.settings.size)
        end
        t.detach = function(o) assert(o.valid ~= false); calls[#calls + 1] = id .. ':detach:' .. o.id end
        return t
    end
    local a, b = template('a'), template('b')
    local runtime = Runtime.new(host, categories, {a,b})
    local f = {runtime=runtime, host=host, objects=objects, calls=calls, errors=errors, a=a, b=b, categories=categories}
    function f.object(id, class, parent, ready)
        local object = {id=id, path=id, class=class or 'Slot', parent=parent, ready=ready}
        objects[#objects + 1] = object
        return object
    end
    function f.emit(kind, object, version)
        sink({kind=kind, object=object, id=object and object.id, epoch=version or epoch()})
    end
    function f.counts() return scans, unsubs end
    return f
end

test('initial discovery, group creation, no repeated attach or scans', function()
    local f = fixture()
    local first = f.object('one')
    f.runtime:select('player.quickslots', {a={size=1}})
    f.runtime:start()
    assert(#f.calls == 1)
    local second = f.object('two')
    f.emit('changed', second)
    f.emit('changed', first)
    assert(#f.calls == 2 and f.counts() == 1)
end)

test('category targets are searched only when required or selected by a template', function()
    local searches={}
    local roots={a={source='lookup',object='a',required=true},b={source='lookup',object='b'},unused={source='lookup',object='unused'}}
    local host={
        valid=function(o) return o~=nil end,identity=function(o) return o.id end,
        ready=function() return true end, parent=function() end,
        matches=function(o,s) return o.id==s.object end,
        find=function(s) searches[#searches+1]=s.object; return {{id=s.object}} end,
        watch=function() end,
        screen=function() return {width=1920,height=1080} end,
        subscribe=function() return function() end end,onError=function(e) error(e.message) end,
    }
    local template={id='b',category='c',objects={'b'},managed=false,
        attach=function() end,update=function() end,detach=function() end}
    local runtime=Runtime.new(host,{{name='c',objects=roots}},{template})
    runtime:start()
    assert(#searches==1 and searches[1]=='a')
    runtime:select('c',{b={}})
    assert(#searches==3 and searches[2]=='a' and searches[3]=='b')
    runtime:select('c',{})
    assert(#searches==4 and searches[4]=='a')
    runtime:stop()
end)

test('overlapping selectors attach once', function()
    local f = fixture(false, {one={source='lookup',object='one'}, all={source='lookup',class='Slot'}})
    f.object('one')
    f.runtime:select('player.quickslots', {a={}})
    f.runtime:start()
    assert(#f.calls == 1)
end)

test('settings invoke update, not attach or detach', function()
    local f = fixture()
    f.object('one')
    f.runtime:select('player.quickslots', {a={size=1}}); f.runtime:start()
    local settings = {size=2}
    f.runtime:select('player.quickslots', {a=settings})
    settings.size = 9
    assert(#f.calls == 2 and f.calls[2] == 'a:update:one:2')
end)

test('readiness and late parent assignment; parent removal detaches descendants', function()
    local f = fixture(false, {root={source='lookup',object='root'}, slots={source='lookup',class='Slot', within='root'}})
    local root = f.object('root', 'Root')
    local child = f.object('child', 'Slot', nil, false)
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    assert(#f.calls == 1)
    f.emit('changed', child); assert(#f.calls == 1)
    child.parent, child.ready = root, true
    f.emit('changed', root); assert(#f.calls == 2)
    f.emit('lost', root)
    assert(#f.calls == 4 and next(f.runtime:attachments('a')) == nil)
end)

test('reparenting valid objects detaches and can reattach', function()
    local f = fixture(false, {root={source='lookup',object='root'}, slots={source='lookup',class='Slot', within='root'}})
    local root = f.object('root', 'Root')
    local child = f.object('child', 'Slot', root)
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    child.parent = nil; f.emit('changed', child)
    assert(f.calls[3] == 'a:detach:child')
    child.parent = root; f.emit('changed', child)
    assert(f.calls[4] == 'a:attach:child:nil')
end)

test('invalid objects never receive detach, replacements attach independently', function()
    local f = fixture()
    local old = f.object('old')
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    old.valid = false
    f.emit('lost', old)
    local new = f.object('new'); new.path = old.path
    f.emit('changed', new)
    assert(#f.calls == 2 and f.runtime:attachments('a').old == nil)
end)

test('disable and single selection switch detach before attaching', function()
    local f = fixture(true)
    f.object('one')
    f.runtime:select('player.quickslots', {b={}}); f.runtime:start()
    assert(not pcall(function() f.runtime:select('player.quickslots', {a={},b={}}) end))
    f.runtime:select('player.quickslots', {a={}})
    assert(f.calls[2] == 'b:detach:one' and f.calls[3] == 'a:attach:one:nil')
    f.runtime:select('player.quickslots', {})
    assert(f.calls[4] == 'a:detach:one')
end)

test('world invalidation discards records and rejects stale queued events', function()
    local f = fixture()
    local old = f.object('old')
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    old.valid = false
    f.emit('world_invalidated', nil, 1)
    assert(f.runtime.epoch == 2 and next(f.runtime:attachments('a')) == nil)
    local new = f.object('new')
    f.emit('changed', new, 1); assert(#f.calls == 1)
    f.emit('changed', new, 2); assert(#f.calls == 1)
    f.emit('world_ready', nil, 2)
    assert(#f.calls == 2 and f.calls[2] == 'a:attach:new:nil')
end)

test('callback errors do not prevent other templates and retry only on an event', function()
    local f = fixture()
    local o = f.object('one')
    local attach = f.a.attach
    f.a.attach = function() error('test failure') end
    f.runtime:select('player.quickslots', {a={},b={}}); f.runtime:start()
    assert(#f.errors == 1 and #f.calls == 1)
    f.a.attach = attach; f.emit('changed', o)
    assert(#f.calls == 2 and f.calls[2] == 'a:attach:one:nil')
end)

test('callback-generated events do not retry a persistent failure in the same turn', function()
    local f = fixture()
    local object=f.object('one')
    local attempts=0
    f.a.attach=function()
        attempts=attempts+1
        assert(attempts<5,'unbounded callback retry')
        f.emit('changed',object)
        return false,'temporary layout failure'
    end
    f.runtime:select('player.quickslots',{a={}})
    f.runtime:start()
    assert(attempts==1 and #f.errors==1)
    f.emit('changed',object)
    assert(attempts==2 and #f.errors==2)
end)

test('failed detach blocks single-category replacement and retries', function()
    local f = fixture(true)
    local o = f.object('one')
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    local detach = f.a.detach
    f.a.detach = function() error('restoration failed') end
    f.runtime:select('player.quickslots', {b={}})
    assert(#f.calls == 1 and f.runtime:attachments('a').one)
    f.a.detach = detach; f.emit('changed', o)
    assert(f.calls[2] == 'a:detach:one' and f.calls[3] == 'b:attach:one:nil')
end)

test('not-ready attach retries on readiness event', function()
    local f = fixture()
    local o = f.object('one')
    local attach = f.a.attach
    f.a.attach = function() return false, 'not_ready: ability_box' end
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    assert(#f.calls == 0 and #f.errors == 0)
    f.a.attach = attach; f.emit('changed', o)
    assert(#f.calls == 1)
end)

test('shutdown cancels subscription, skips invalid refs, ignores late events', function()
    local f = fixture()
    local a, b = f.object('a'), f.object('b')
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    a.valid = false
    f.runtime:stop()
    local _, unsubs = f.counts()
    assert(unsubs == 1 and #f.calls == 3 and f.calls[3] == 'a:detach:b')
    f.emit('changed', b)
    assert(#f.calls == 3)
end)

test('selector graph rejects cycles and missing roots', function()
    assert(not pcall(Selectors.compile, {a={source='lookup',class='Slot', within='b'}, b={source='lookup',class='Slot',within='a'}}))
    assert(not pcall(Selectors.compile, {a={source='lookup',class='Slot', within='missing'}}))
    assert(not pcall(Selectors.compile, {a={source='lookup',class='Slot',object='one'}}))
end)

test('startup defers template execution until barrier and accepts other modules', function()
    local f = fixture()
    f.object('one')
    local barrier, stopped, executed = nil, 0, {}
    local definitions = {own=f.a, external=f.b}
    local boot = Bootstrap.new({host=f.host,categories=f.categories,
        execute=function(path) executed[#executed+1] = path; return definitions[path] end,
        selections={['player.quickslots']={a={size=3},b={size=4}}},
        subscribeLoopStart=function(callback) barrier=callback; return function() stopped=stopped+1 end end})
    assert(#executed==0 and #f.calls==0)
    assert(boot:registerTemplate('own'))
    assert(boot:registerTemplate('external') and not boot:registerTemplate('external'))
    barrier()
    assert(boot.phase=='running' and #executed==2 and #f.calls==2 and stopped==1)
    barrier();assert(#executed==2)
    assert(not pcall(function() boot:registerTemplate('late') end))
end)

test('startup drains cross-state registrations before loading templates', function()
    local f=fixture()
    f.object('one')
    local barrier,collected,executed=nil,0,{}
    local definitions={external=f.a}
    local boot=Bootstrap.new({host=f.host,categories=f.categories,
        execute=function(path) executed[#executed+1]=path;return definitions[path] end,
        collectTemplates=function() collected=collected+1;return {'external'} end,
        subscribeLoopStart=function(callback) barrier=callback;return function() end end})
    assert(boot.phase=='registering' and collected==0 and #executed==0)
    barrier()
    assert(boot.phase=='running' and collected==1 and #executed==1 and executed[1]=='external')
end)

test('template main can return multiple definitions', function()
    local f=fixture()
    f.object('one')
    local barrier
    local boot=Bootstrap.new({host=f.host,categories=f.categories,
        execute=function(path)
            return {f.a,f.b}
        end,
        selections={['player.quickslots']={a={size=3},b={size=4}}},
        subscribeLoopStart=function(callback) barrier=callback; return function() end end})
    boot:registerTemplate('bundle')
    barrier()
    local count=0
    for _ in pairs(boot.menu.definitions['player.quickslots']) do count=count+1 end
    assert(boot.phase=='running' and count==2 and #f.calls==2)
end)

test('template loaded hook runs once before model construction', function()
    local f=fixture()
    local barrier,loads,registrations,cleanups=nil,0,0,0
    local template=f.a
    template.loaded=function() loads=loads+1 end
    local events={register=function(_,loaded)
        assert(loads==1 and loaded.id==template.id,'events registered before template loaded')
        registrations=registrations+1
        return function() cleanups=cleanups+1;return true end
    end}
    local boot=Bootstrap.new({host=f.host,categories=f.categories,
        execute=function(path)
            local value={}
            for key,entry in pairs(template) do value[key]=entry end
            value.category='player.quickslots'
            value.module='Test'
            return value
        end,events=events,
        subscribeLoopStart=function(callback) barrier=callback;return function() end end})
    boot:registerTemplate('template')
    assert(loads==0 and boot.phase=='registering')
    barrier()
    assert(loads==1 and registrations==1 and boot.phase=='running')
    barrier()
    assert(loads==1 and registrations==1)
    boot:stop();assert(cleanups==1)
end)

test('subscription is active before snapshot and duplicate notifications are harmless', function()
    local f = fixture()
    local object = f.object('one')
    local subscribe = f.host.subscribe
    f.host.subscribe = function(sink, epoch)
        local stop = subscribe(sink, epoch)
        sink({kind='changed', object=object, epoch=epoch()})
        return stop
    end
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    assert(#f.calls == 1)
end)

test('loss during subscription is applied before initial attachment', function()
    local f = fixture()
    local object = f.object('one')
    local subscribe = f.host.subscribe
    f.host.subscribe = function(sink, epoch)
        local stop = subscribe(sink, epoch)
        sink({kind='lost', id=object.id, epoch=epoch()})
        return stop
    end
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    assert(#f.calls == 0)
end)

test('failed initial discovery closes subscriptions and fails startup', function()
    local f = fixture()
    f.host.find = function() error('enumeration unavailable') end
    f.runtime:select('player.quickslots', {a={}})
    f.runtime:start()
    local _, unsubs = f.counts()
    assert(f.runtime.phase == 'failed' and unsubs == 1 and #f.errors == 1)
end)

test('reentrant selection queues update until attachment completes', function()
    local f = fixture()
    f.object('one')
    local attach = f.a.attach
    f.a.attach = function(o, settings)
        attach(o, settings)
        f.runtime:select('player.quickslots', {a={size=2}})
    end
    f.runtime:select('player.quickslots', {a={size=1}}); f.runtime:start()
    assert(#f.calls == 2 and f.calls[2] == 'a:update:one:2')
end)

test('shutdown can retry a failed detach without resubscribing', function()
    local f = fixture()
    f.object('one')
    f.runtime:select('player.quickslots', {a={}}); f.runtime:start()
    local detach = f.a.detach
    f.a.detach = function() error('temporary detach failure') end
    f.runtime:stop()
    assert(f.runtime:attachments('a').one)
    f.a.detach = detach; f.runtime:stop()
    local _, unsubs = f.counts()
    assert(next(f.runtime:attachments('a')) == nil and unsubs == 1)
end)

test('shutdown retains a failed host unsubscribe for retry', function()
    local f=fixture()
    local subscribe=f.host.subscribe
    local attempts=0
    f.host.subscribe=function(sink,epoch)
        local release=subscribe(sink,epoch)
        return function()
            attempts=attempts+1
            if attempts==1 then error('temporary host unsubscribe failure') end
            release()
        end
    end
    f.runtime:start()
    assert(f.runtime:stop()==false and attempts==1)
    assert(f.runtime:stop()==true and attempts==2)
    local _,unsubs=f.counts()
    assert(unsubs==1)
end)

test('failed update preserves attachment and retries without attaching again', function()
    local f = fixture()
    local o = f.object('one')
    f.runtime:select('player.quickslots', {a={size=1}}); f.runtime:start()
    local update = f.a.update
    f.a.update = function() return false, 'not_ready' end
    f.runtime:select('player.quickslots', {a={size=2}})
    assert(f.runtime:attachments('a').one and #f.calls == 1)
    f.a.update = update; f.emit('changed', o)
    assert(f.calls[2] == 'a:update:one:2')
end)

test('all callbacks receive template settings overlaid on category settings', function()
    local f = fixture()
    f.object('one')
    local seen = {}
    f.a.attach = function(_, params) seen.attach = params.settings; assert(params.screen.right==1920) end
    f.a.update = function(_, params) seen.update = params.settings; assert(params.screen.middle==540) end
    f.a.detach = function(_, params) seen.detach = params.settings; assert(params.screen.bottom==0) end
    f.runtime:setCategorySettings('player.quickslots', {size=10, opacity=0.5, visible=true, count=5})
    f.runtime:select('player.quickslots', {a={size=20, visible=false, count=0}})
    f.runtime:start()
    assert(seen.attach.size == 20 and seen.attach.opacity == 0.5)
    assert(seen.attach.visible == false and seen.attach.count == 0)
    f.runtime:setCategorySettings('player.quickslots', {size=11, opacity=0.8, visible=true, count=6})
    assert(seen.update.size == 20 and seen.update.opacity == 0.8)
    assert(seen.update.visible == false and seen.update.count == 0)
    f.runtime:select('player.quickslots', {})
    assert(seen.detach.size == 20 and seen.detach.opacity == 0.8)
    assert(seen.detach.visible == false and seen.detach.count == 0)
end)

test('screen coordinates refresh when the viewport changes', function()
    local f = fixture()
    f.object('one')
    local width, seen = 1920, {}
    f.host.screen = function()
        return {width=width,height=1080,left=0,center=width/2,right=width,
            bottom=0,middle=540,top=1080}
    end
    f.a.attach = function(_, params) seen[#seen+1]=params.screen end
    f.a.update = function(_, params) seen[#seen+1]=params.screen end
    f.runtime:select('player.quickslots', {a={size=1}})
    f.runtime:start()
    width=2560
    f.runtime:select('player.quickslots', {a={size=2}})
    assert(seen[1].width==1920 and seen[1].center==960)
    assert(seen[2].width==2560 and seen[2].center==1280)
end)

test('detach gets the last successfully applied snapshot after failed update', function()
    local f = fixture()
    f.object('one')
    local detached
    f.a.update = function() return false, 'not_ready' end
    f.a.detach = function(_, params)
        detached = params.settings
        assert(f.a.settings.size == params.settings.size)
    end
    f.runtime:setCategorySettings('player.quickslots', {opacity=0.5})
    f.runtime:select('player.quickslots', {a={size=1}}); f.runtime:start()
    f.runtime:setCategorySettings('player.quickslots', {opacity=0.9})
    f.runtime:select('player.quickslots', {a={size=2}})
    f.runtime:select('player.quickslots', {})
    assert(detached.size == 1 and detached.opacity == 0.5)
end)

test('removing a template override exposes the category value; snapshots are isolated', function()
    local f = fixture()
    local one = f.object('one')
    local observed = {}
    f.a.attach = function(o, params)
        local settings=params.settings
        observed[o.id] = {size=settings.size, nested=settings.nested.value}
        settings.nested.value = 'mutated'
    end
    f.a.update = function(_, params) observed.update = params.settings.size end
    local category = {size=10, nested={value='category'}}
    f.runtime:setCategorySettings('player.quickslots', category)
    category.nested.value = 'external mutation'
    f.runtime:select('player.quickslots', {a={size=20}}); f.runtime:start()
    local two = f.object('two'); f.emit('changed', two)
    assert(observed.one.nested == 'category' and observed.two.nested == 'category')
    f.runtime:select('player.quickslots', {a={}})
    assert(observed.update == 10)
end)

test('template defaults override category settings and saved values override defaults', function()
    local f = fixture()
    f.object('one')
    f.a.settings = {size=20, nested={template=true}}
    local seen
    f.a.attach = function(_, params) seen=params.settings end
    f.categories[1].settings = {size=10, opacity=0.4, nested={category=true}}
    local r = Runtime.new(f.host, f.categories, {f.a})
    r:select('player.quickslots', {a={size=30}}); r:start()
    assert(seen.size == 30 and seen.opacity == 0.4)
    assert(seen.nested.template == true and seen.nested.category == nil)
end)

test('control state is copied into callbacks and refreshes active templates', function()
    local f=fixture()
    f.object('one')
    local state={revision=0,controls={group={from=1,to=1}}}
    local seen,events={},{ }
    f.a.attach=function(_,params) seen[#seen+1]=params.state.controls.group.to end
    f.a.update=function(_,params)
        seen[#seen+1]=params.state.controls.group.to
        params.state.controls.group.to=99
    end
    f.a.events={['controls.group.focus']=function(event,current)
        events[#events+1]={from=event.group.from,to=event.group.to,
            current=current.controls.group.to}
        current.controls.group.to=99
    end}
    local runtime=Runtime.new(f.host,f.categories,{f.a},state)
    runtime:select('player.quickslots',{a={}});runtime:start()
    state.revision=1;state.controls.group.from=1;state.controls.group.to=2
    runtime:stateChanged({name='controls.group.focus',revision=1,group={from=1,to=2}})
    assert(seen[1]==1 and seen[2]==2 and state.controls.group.to==2)
    assert(#events==1 and events[1].from==1 and events[1].to==2 and events[1].current==2)
    runtime:select('player.quickslots',{})
    state.revision=2;state.controls.group.from=2;state.controls.group.to=1
    runtime:stateChanged({name='controls.group.focus',revision=2,group={from=2,to=1}})
    assert(#events==1,'inactive template received an event')
end)

test('event callback failures are isolated between active templates', function()
    local f=fixture()
    f.object('one')
    local delivered=0
    f.a.events={['controls.group.focus']=function() error('event failure') end}
    f.b.events={['controls.group.focus']=function() delivered=delivered+1 end}
    local state={revision=1,controls={group={from=1,to=2}}}
    local runtime=Runtime.new(f.host,f.categories,{f.a,f.b},state)
    runtime:select('player.quickslots',{a={},b={}});runtime:start()
    runtime:stateChanged({name='controls.group.focus',revision=1,group={from=1,to=2}})
    assert(delivered==1 and #runtime.errors==1 and runtime.errors[1].stage=='event'
        and runtime.errors[1].template=='a')
end)

print('PASS: ' .. passed .. ' MCT lifecycle tests')
