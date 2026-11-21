-- A reconcile reads a category's objects once per pass, however many enabled templates
-- name them, and each template still gets its own bundle.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local Runtime=require('mc.runtime')

local hud={id='hud',class='Hud',valid=true}
local root={id='root',class='Root',valid=true,Hud=hud}
for _,object in ipairs({root,hud}) do function object:IsValid() return self.valid end end
local memberReads=0
local host={
    valid=function(v) return v~=nil and v.valid~=false end,
    identity=function(v) return v.id end,
    ready=function() return true end,
    matches=function(v,s) return v.class==s.class end,
    parent=function() end,
    member=function(v,name) memberReads=memberReads+1; return v[name] end,
    find=function() return {root} end,
    watch=function() end,
    screen=function() return {width=1920,height=1080} end,
    subscribe=function() return function() end end,
    onError=function(e) error(e.message) end,
}
local seen,updates={},0
local templates={}
for _,id in ipairs({'a','b','c'}) do
    templates[#templates+1]={id=id,category='c',objects={'root','hud'},
        attach=function(_,_,named) seen[id]=named end,
        update=function() updates=updates+1 end,detach=function() end}
end
local runtime=Runtime.new(host,{{id='c',objects={root={source='lookup',class='Root'},
    hud={source='reference',from='root',member='Hud',required=true}}}},templates)
runtime:select('c',{a={},b={},c={}})
memberReads=0
runtime:start()
assert(memberReads==1,'one pass reads the shared member once: '..memberReads)
assert(seen.a and seen.b and seen.c,'every template attaches')
assert(seen.a.hud and seen.b.hud and seen.a~=seen.b,'each template gets its own bundle')
memberReads=0
runtime:event({kind='changed',object=root,epoch=runtime.epoch})
assert(memberReads==1,'a later pass reads it once again: '..memberReads)
runtime:stop()
print('PASS: a category\'s objects are resolved once per reconcile')
