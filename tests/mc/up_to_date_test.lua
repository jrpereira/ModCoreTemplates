-- A reconcile skips an up-to-date attachment before asking the host whether its root is
-- ready: only the detach pass checks it once.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local Runtime=require('mc.runtime')

local root={id='root',class='Root',valid=true}
function root:IsValid() return self.valid end
local readyCalls=0
local host={
    valid=function(v) return v~=nil and v.valid~=false end,
    identity=function(v) return v.id end,
    ready=function() readyCalls=readyCalls+1; return true end,
    matches=function(v,s) return v.class==s.class end,
    parent=function() end,
    member=function(v,name) return v[name] end,
    find=function() return {root} end,
    watch=function() end,
    screen=function() return {width=1920,height=1080} end,
    subscribe=function() return function() end end,
    onError=function(e) error(e.message) end,
}
local attaches=0
local runtime=Runtime.new(host,{{id='c',objects={root={source='lookup',class='Root'}}}},
    {{id='t',category='c',objects={'root'},uniqueBy='category',
        attach=function(_,_,saved) attaches=attaches+1; return saved end}})
runtime:select('c',{t={}})
runtime:start()
assert(attaches==1)
readyCalls=0
runtime:event({kind='changed',object=root,epoch=runtime.epoch})
assert(attaches==1,'an up-to-date attachment is not rebuilt')
assert(readyCalls==1,'readiness is checked once, by the detach pass, not again to attach: '..readyCalls)
runtime:stop()
print('PASS: an up-to-date attachment costs no attach-side host calls')
