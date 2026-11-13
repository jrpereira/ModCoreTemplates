package.path = './Scripts/?.lua;./Scripts/?/init.lua;./Scripts/vendor/?.lua;' .. package.path
local Runtime = require('mc.runtime')
local Events = require('mc_events')
local passed = 0
local function test(name, body)
    local ok, why = pcall(body)
    assert(ok, name .. ': ' .. tostring(why))
    passed = passed + 1
end

-- One quickslot-like category opting in, one NPC-like category that does not.
local function fixture(layoutEvent)
    local objects, errors, passes = {}, {}, {}
    local sink, epoch
    local host = {
        valid=function(o) return o ~= nil and o.valid ~= false end,
        identity=function(o) return o.id end,
        ready=function(o) return o.ready ~= false end,
        matches=function(o, s) return s.class == o.class end,
        parent=function(o) return o.parent end,
        watch=function() end,
        screen=function() return {width=1920,height=1080} end,
        find=function(s)
            local found = {}
            for _, o in ipairs(objects) do
                if o.valid ~= false and s.class == o.class then found[#found + 1] = o end
            end
            return found
        end,
        subscribe=function(callback, getEpoch) sink, epoch = callback, getEpoch; return function() end end,
        onError=function(e) errors[#errors + 1] = e end,
    }
    local categories = {
        {id='player.quickslots', layoutEvent=layoutEvent, objects={slots={source='lookup',class='Slot'}}},
        {id='npc.pawn', objects={pawn={source='lookup',class='Pawn'}}},
    }
    local calls = {}
    local function template(id, category, target)
        return {id=id, category=category, module='Test', objects={target}, managed=false,
            attach=function(o) calls[#calls + 1] = id .. ':attach:' .. o.id end,
            update=function(o) calls[#calls + 1] = id .. ':update:' .. o.id end,
            detach=function(o) calls[#calls + 1] = id .. ':detach:' .. o.id end,
            events={['controls.group.focus']=function() calls[#calls + 1] = id .. ':focus' end,
                ['templates.layout.changed']=function() calls[#calls + 1] = id .. ':layout' end}}
    end
    local bars = template('bars', 'player.quickslots', 'slots')
    local npc = template('npc', 'npc.pawn', 'pawn')
    local runtime = Runtime.new(host, categories, {bars, npc}, nil, {
        layoutChanged=function(ids) passes[#passes + 1] = table.concat(ids, ',') end})
    local f = {runtime=runtime, passes=passes, calls=calls, errors=errors}
    function f.object(id, class)
        local object = {id=id, class=class or 'Slot'}
        objects[#objects + 1] = object
        return object
    end
    function f.changed(object) sink({kind='changed', object=object, epoch=epoch()}) end
    return f
end

test('one notification per attach pass, not per widget', function()
    local f = fixture(true)
    f.object('hud'); f.object('aa')
    f.runtime:select('player.quickslots', {bars={}})
    f.runtime:start()
    assert(#f.calls == 2, 'expected both roots attached')
    assert(#f.passes == 1 and f.passes[1] == 'player.quickslots', table.concat(f.passes, ' | '))
end)

test('detach and update passes notify; passes without callbacks stay silent', function()
    local f = fixture(true)
    local hud = f.object('hud')
    f.runtime:start()
    assert(#f.passes == 0, 'notified with no template selected')
    f.runtime:select('player.quickslots', {bars={}})
    assert(#f.passes == 1)
    f.changed(hud)
    assert(#f.passes == 1, 'a reconcile that ran no callback notified')
    f.runtime:select('player.quickslots', {bars={size=2}})
    assert(#f.passes == 2 and f.calls[#f.calls] == 'bars:update:hud')
    f.runtime:select('player.quickslots', {})
    assert(#f.passes == 3 and f.calls[#f.calls] == 'bars:detach:hud')
end)

test('runtime stop restores and notifies once', function()
    local f = fixture(true)
    f.object('hud')
    f.runtime:select('player.quickslots', {bars={}}); f.runtime:start()
    local before = #f.passes
    assert(f.runtime:stop())
    assert(#f.passes == before + 1 and f.calls[#f.calls] == 'bars:detach:hud')
end)

test('event callbacks on live attachments notify', function()
    local f = fixture(true)
    f.object('hud')
    f.runtime:select('player.quickslots', {bars={}}); f.runtime:start()
    local before = #f.passes
    f.runtime:stateChanged({name='controls.group.focus', revision=1, group={from=1,to=2}})
    assert(f.calls[#f.calls] == 'bars:focus' and #f.passes == before + 1)
end)

test('answering the layout event does not publish another', function()
    local f = fixture(true)
    f.object('hud')
    f.runtime:select('player.quickslots', {bars={}}); f.runtime:start()
    local before, calls = #f.passes, #f.calls
    f.runtime:stateChanged({name=Events.layout, revision=1, category='player.quickslots'})
    assert(Runtime.LAYOUT_EVENT == Events.layout)
    assert(#f.calls == calls + 1 and f.calls[#f.calls] == 'bars:layout', table.concat(f.calls, ' '))
    assert(#f.passes == before, table.concat(f.passes, ' | '))
end)

test('categories without layoutEvent never notify', function()
    local f = fixture(true)
    f.object('pawn1', 'Pawn')
    f.runtime:select('npc.pawn', {npc={}}); f.runtime:start()
    f.runtime:select('npc.pawn', {})
    assert(#f.calls == 2 and #f.passes == 0, table.concat(f.passes, ' | '))
    local g = fixture(nil)
    g.object('hud')
    g.runtime:select('player.quickslots', {bars={}}); g.runtime:start()
    assert(#g.calls == 1 and #g.passes == 0)
end)

test('a failing listener is reported, not raised', function()
    local objects = {{id='hud', class='Slot'}}
    local errors = {}
    local host = {valid=function(o) return o ~= nil end, identity=function(o) return o.id end,
        ready=function() return true end, matches=function(o, s) return s.class == o.class end,
        parent=function() end, watch=function() end, screen=function() return {} end,
        find=function() return objects end, subscribe=function() return function() end end,
        onError=function(e) errors[#errors + 1] = e end}
    local runtime = Runtime.new(host,
        {{id='player.quickslots', layoutEvent=true, objects={slots={source='lookup',class='Slot'}}}},
        {{id='bars', category='player.quickslots', objects={'slots'}, managed=false,
          attach=function() end, update=function() end, detach=function() end}},
        nil, {layoutChanged=function() error('listener failure') end})
    runtime:select('player.quickslots', {bars={}}); runtime:start()
    assert(#runtime.errors == 1 and runtime.errors[1].stage == 'layout')
end)

test('the quickslots category opts in', function()
    local category = assert(loadfile('Scripts/categories/player_quickslots.lua'))()
    assert(category.id == 'player.quickslots' and category.layoutEvent == true)
end)

test('startup publishes templates.layout.changed through mc_events', function()
    local shared, commands = {}, {}
    local controller
    controller = {IsValid=function() return true end,
        Player={ViewportClient={ProcessConsoleExec=function(_, command, _, from)
            assert(from == controller); commands[#commands + 1] = command end}}}
    local api = {ExecuteInGameThread=function(f) f() end,
        UE4SSLuaEventBridge={onLoopStart=function() return function() end end},
        FindFirstOf=function(class) assert(class == 'PlayerController'); return controller end,
        ModRef={GetSharedVariable=function(_, key) return shared[key] end,
            SetSharedVariable=function(_, key, value) shared[key] = value end}}
    local configured = {host={}, categories={}, events={register=function() end}, state={}}
    local Startup = require('mc.lua_startup')
    local captured
    local Bootstrap = require('mc.bootstrap')
    local original = Bootstrap.new
    Bootstrap.new = function(options) captured = options; return {} end
    local ok, why = pcall(Startup.start, configured, api)
    Bootstrap.new = original
    assert(ok, why)
    assert(type(captured.layoutChanged) == 'function')
    captured.layoutChanged({'player.quickslots'})
    captured.layoutChanged({'player.quickslots'})
    assert(shared['MCT.Templates.LayoutChanged.v1.data'] == '2 player.quickslots',
        tostring(shared['MCT.Templates.LayoutChanged.v1.data']))
    assert(#commands == 2 and commands[1] == 'MCT_Templates_LayoutChanged_v1')
    -- A subscriber reads the published category.
    assert(Events.layout == 'templates.layout.changed')
end)

print('PASS: ' .. passed .. ' MCT layout event tests')
