package.path = './Scripts/?.lua;' .. package.path
local Startup = require('mc.lua_startup')
local References = require('mc.lua_references')

local object = {valid=true, id='1:100:Widget A'}
local events, epoch
local source = {
    valid=function(value) return value.valid end,
    identity=function(value) return value.id end,
    ready=function(value) return value.valid end,
    matches=function() return true end,
    parent=function() end,
    find=function() return {object} end,
    child=function(value, class) return value==object and class=='Widget' and object or nil end,
    member=function(value, path) return value==object and path=='Bindings.Left' and object or nil end,
    watch=function() end,
    screen=function() return {width=1920,height=1080,left=0,center=960,right=1920,
        bottom=0,middle=540,top=1080} end,
    subscribe=function(callback, getEpoch)
        events, epoch = callback, getEpoch
        return function() events=nil end
    end,
    onError=function(error) error(error.message) end,
    stop=function() end,
}
local host=References.new(source)
local ref=assert(host.capture(object))
assert(host.capture(object)==ref and host.identity(ref)==object.id)
assert(host.valid(ref) and host.unwrap(ref)==object)
assert(host.child(ref,'Widget')==ref and host.member(ref,'Bindings.Left')==ref)
local seen
host.subscribe(function(event) seen=event end,function() return 1 end)
events({kind='changed',object=object,epoch=epoch()})
assert(seen.object==ref and seen.kind=='changed')
object.id='2:100:Widget A'
assert(not host.valid(ref) and host.unwrap(ref)==nil)
local newer=assert(host.capture(object))
assert(newer~=ref and host.valid(newer))

local jobs={}
local category={name='player.quickslots',objects={root={source='lookup',class='/Script/UMG.UserWidget'}}}
local template={id='example.template',name='Template',category='player.quickslots',
    module='Example',managed=false,objects={'root'},
    attach=function() end,update=function() end,detach=function() end}
local opts={categoryFiles={'category'},
    execute=function(path) return path=='category' and category or template end,
    host={valid=function() return true end,identity=function() return 'object' end,
        ready=function() return true end,matches=function() return true end,
        parent=function() end,find=function() return {} end,
        watch=function() end,
        screen=function() return source.screen() end,
        subscribe=function() return function() end end,onError=function(error) error(error.message) end}}
local boot=Startup.start(opts,{ExecuteInGameThread=function(callback) jobs[#jobs+1]=callback end})
assert(boot.phase=='registering' and #jobs==1)
boot:registerTemplate('template')
jobs[1]()
assert(boot.phase=='running')
boot:stop()
assert(boot.phase=='stopped')
print('PASS: Lua-only startup and map-scoped references')

local original=package.loaded['mc.lua_startup']
local registered={}
package.loaded['mc.lua_startup']={start=function(options)
    return {registerTemplate=function(_,path)
        registered[#registered+1]={path=path}
        return true
    end}
end}
local active=dofile('./Scripts/main.lua')
package.loaded['mc.lua_startup']=original
assert(type(active)=='table')
assert(#registered==0)
print('PASS: active MCT entry point installs direct template registration')
