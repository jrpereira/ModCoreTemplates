-- A resolution, window or UI-scale change made mid-session reaches every attached
-- template at the next MC_PlayerReady or MC_CombatStart: the screen is read once
-- there and each attachment laid out for another one is updated with the new
-- params.screen, as a settings revision would. The same screen updates nothing,
-- and no other moment reads it.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local Runtime=require('mc.runtime')

local function fixture(hooks)
    local roots={{id='one',class='Root'},{id='two',class='Root'}}
    local screen={width=1920,height=1080,scale=1}
    local reads,errors,log=0,{},{}
    local host={
        valid=function(v) return v~=nil and v.valid~=false end,
        identity=function(v) return v.id end,
        ready=function() return true end,
        matches=function(v,s) return v.class==s.class end,
        parent=function() end,
        find=function() return roots end,
        watch=function() end,
        screen=function()
            reads=reads+1
            if screen.missing then return nil end
            return {width=screen.width,height=screen.height,scale=screen.scale,
                center=screen.width/2,middle=screen.height/2}
        end,
        subscribe=function() return function() end end,
        onError=function(e) errors[#errors+1]=e end,
    }
    local function template(id,category)
        local function note(operation)
            return function(object,params)
                log[#log+1]=id..':'..operation..':'..object.id..' '..params.screen.width..'x'
                    ..params.screen.height..'@'..params.screen.scale
            end
        end
        return {id=id,category=category,objects={'root'},managed=false,
            attach=note('attach'),update=note('update'),detach=function() end}
    end
    local categories={
        {id='timed',hooks=hooks,objects={root={source='lookup',class='Root'}}},
        {id='plain',objects={root={source='lookup',class='Root'}}},
    }
    local runtime=Runtime.new(host,categories,{template('a','timed'),template('b','plain')})
    runtime:select('timed',{a={}})
    runtime:select('plain',{b={}})
    local function take()
        table.sort(log)
        local result=table.concat(log,', ')
        for index=#log,1,-1 do log[index]=nil end
        return result
    end
    local f={runtime=runtime,screen=screen,errors=errors,take=take}
    function f.reads() local n=reads; reads=0; return n end
    return f
end

do
    local f=fixture({attach='MC_PlayerReady',wake='MC_CombatStart',sleep='MC_CombatEnd'})
    f.runtime:start()
    f.runtime:signal('MC_PlayerReady')
    assert(f.take()=='a:attach:one 1920x1080@1, a:attach:two 1920x1080@1, '
        ..'b:attach:one 1920x1080@1, b:attach:two 1920x1080@1')
    f.reads()

    -- The same screen: one read, nothing updated.
    f.runtime:signal('MC_CombatStart')
    assert(f.take()=='','an unchanged screen updates nothing')
    assert(f.reads()==1,'the screen is read once per check')

    -- Other signals never read the screen.
    f.screen.width=2560
    f.runtime:signal('MC_CombatEnd')
    assert(f.take()=='' and f.reads()==0,'combat end does not check the screen')

    -- A wider screen: every attachment in every category is updated with it,
    -- including the category no hook names.
    f.runtime:signal('MC_CombatStart')
    assert(f.take()=='a:update:one 2560x1080@1, a:update:two 2560x1080@1, '
        ..'b:update:one 2560x1080@1, b:update:two 2560x1080@1')
    assert(f.reads()==1,'the new screen is read once for all attachments')
    f.runtime:signal('MC_CombatEnd')
    f.runtime:signal('MC_CombatStart')
    assert(f.take()=='','the updated attachments hold the new screen')

    -- A UI-scale change alone counts, and MC_PlayerReady checks too.
    f.screen.scale=1.5
    f.runtime:signal('MC_PlayerReady')
    assert(f.take()=='a:update:one 2560x1080@1.5, a:update:two 2560x1080@1.5, '
        ..'b:update:one 2560x1080@1.5, b:update:two 2560x1080@1.5')

    -- A settings change still reattaches through the same path with the screen it reads.
    f.screen.height=1440
    f.runtime:select('plain',{b={size=2}})
    assert(f.take()=='b:update:one 2560x1440@1.5, b:update:two 2560x1440@1.5')
    f.runtime:signal('MC_CombatEnd')
    f.runtime:signal('MC_CombatStart')
    assert(f.take()=='a:update:one 2560x1440@1.5, a:update:two 2560x1440@1.5',
        'only the attachments laid out for another screen update')
    assert(#f.errors==0,f.errors[1] and f.errors[1].message)
    f.runtime:stop()
end

do
    -- No screen to read (the viewport not up yet): nothing is marked or fails.
    local f=fixture({wake='MC_CombatStart'})
    f.runtime:start()
    f.take()
    f.screen.missing=true
    f.runtime:signal('MC_CombatStart')
    assert(f.take()=='' and #f.errors==0)
    f.runtime:stop()
end

print('PASS screen_change_test')
