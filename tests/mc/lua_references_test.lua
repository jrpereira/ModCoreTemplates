-- Lua references: capture checks the object through the source once; afterwards a
-- reference is live exactly while its weak handle is, without asking the source again.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local References=require('mc.lua_references')

local checks=0
local function object(name)
    local o={name=name,alive=true}
    function o:IsValid() return self.alive end
    function o:GetAddress() return 1 end
    return o
end
local source={
    valid=function(o) checks=checks+1; return o~=nil and o.alive and not o.name:find('Default__',1,true) end,
    identity=function(o) return o.name end,
    ready=function() return true end,
    matches=function() return true end,
    parent=function() end,
    find=function() return {} end,
    watch=function() end,
    screen=function() end,
    subscribe=function() return function() end end,
    onError=function() end,
}
local host=References.new(source)

assert(host.capture(object('Default__Widget'))==nil,'capture rejects what the source rejects')

local live=object('Widget_1')
local reference=assert(host.capture(live))
checks=0
for _=1,5 do assert(host.valid(reference) and host.unwrap(reference)==live) end
assert(checks==0,'a captured reference is checked through its handle, not the source')
live.alive=false
assert(not host.valid(reference) and host.unwrap(reference)==nil,'a dead object ends its reference')
print('PASS: a captured reference is live while its weak handle is')
