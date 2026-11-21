-- A failure while reconciling one category is reported with its id and does not stop the
-- categories after it from attaching.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local Runtime=require('mc.runtime')

local rootA={id='rootA',class='A',valid=true}
local rootB={id='rootB',class='B',valid=true}
for _,root in ipairs({rootA,rootB}) do function root:IsValid() return self.valid end end
local errors={}
local host={
    valid=function(v) return v~=nil and v.valid~=false end,
    identity=function(v) return v.id end,
    ready=function(v)
        if v==rootA then error('broken readiness') end
        return true
    end,
    matches=function(v,s) return v.class==s.class end,
    parent=function() end,
    member=function(v,name) return v[name] end,
    find=function() return {rootA,rootB} end,
    watch=function() end,
    screen=function() return {width=1920,height=1080} end,
    subscribe=function() return function() end end,
    onError=function(e) errors[#errors+1]=e end,
}
local attached={}
local categories={
    {id='a.first',objects={root={source='lookup',class='A'}}},
    {id='b.second',objects={root={source='lookup',class='B'}}},
}
local templates={}
for _,category in ipairs(categories) do
    templates[#templates+1]={id=category.id..'_t',category=category.id,objects={'root'},uniqueBy='category',
        attach=function(_,_,saved) attached[category.id]=true; return saved end}
end
local runtime=Runtime.new(host,categories,templates)
runtime:select('a.first',{['a.first_t']={}})
runtime:select('b.second',{['b.second_t']={}})
runtime:start()
assert(attached['b.second'],'a later category still attaches after an earlier one fails')
assert(not attached['a.first'])
local reported=false
for _,e in ipairs(errors) do
    if e.stage=='reconcile' and e.message:find('a.first',1,true) and e.message:find('broken readiness',1,true) then
        reported=true
    end
end
assert(reported,'the failing category is reported with its id')
runtime:stop()
print('PASS: one category failing to reconcile does not stop the others')
