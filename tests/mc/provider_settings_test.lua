package.path='./Scripts/?.lua;'..package.path
local Provider=require('mc.provider_settings')

local declaration,groups=Provider.template({
    {id='Opacity',label='Opacity',values='percent',default=100},
    {id='Wheels',label='Wheels',variation={style=0},fields={
        {id='.X',label='X',values={min=-1000,max=1000,step=10},default=0},
        {id='.Size',label='Size',values={[110]='Large',[85]='Small',[100]='Medium'},
            default=100},
    }},
},{style={description='Layout',values={[1]='Separate',[0]='Swap'},default=0}})

assert(declaration.groups[1].fields[1].id=='Style')
assert(declaration.groups[1].fields[2]==nil,'no automatic Control Layout link')
assert(groups[2].fields[1].id=='Opacity' and groups[2].fields[1].suffix=='%')
assert(groups[3].id=='Wheels' and groups[3].variationSource=='Style')
assert(groups[3].fields[1].id=='WheelsX')
local size=groups[3].fields[2]
assert(size.id=='WheelsSize' and size.values[1]==85 and size.labels[1]=='Small'
    and size.values[3]==110 and size.default==100 and size.tab==nil)
assert(groups[1].fields[1].tab==nil and groups[1].fields[1].level==nil)
assert(groups[1].level==nil and groups[3].level==nil)
assert(groups[2].fields[1].tab==nil)

local _,dropdown=Provider.template({
    {id='Display',label='Display',values={[0]='Off',[1]='On'},default=1,tab=false},
}, {})
assert(#dropdown==1 and dropdown[1].fields[1].tab==false,'no empty Template group')

local choices={}
for value=1,9 do choices[value]='Choice '..value end
local _,largePicker=Provider.template({
    {id='Choice',label='Choice',values=choices,default=1},
}, {})
assert(largePicker[1].fields[1].tab==nil)

local _,relativeGroups=Provider.template({
    {id='.Branch',label='Branch',variation={style=1},fields={
        {id='.Value',label='Value',values='percent',default=50},
    }},
},{style={values={[0]='First',[1]='Second'},default=0}})
assert(relativeGroups[2].id=='StyleBranch'
    and relativeGroups[2].fields[1].id=='StyleBranchValue')

assert(not pcall(Provider.template,{{id='.X',label='X',values='percent',default=0}},{}))
assert(not pcall(Provider.template,{{id='X',label='X',values='missing',default=0}},{}))
assert(not pcall(Provider.template,{{id='G',label='G',fields={
    {id='.X',label='X',values='percent',default=101},
}}},{}))

local orientation={[7]='Horizontal',[5]='Vertical'}
local _,conditional=Provider.template({
    {id='Bars',label='Bars',fields={
        {id='.A',label='Orientation',values=orientation,default=7},
        {id='.KH',label='Keys',values={[0]='Above',[1]='Below'},default=0,
            conditions={visible={field='.A',match={7}}}},
        {id='.KV',label='Keys',values={[0]='Left',[1]='Right'},default=0,
            conditions={visible={field='BarsA',match={5}},
                label={field='.A',match={5},text='Vertical Keys'}}},
    }},
},{})
local kh,kv=conditional[1].fields[2],conditional[1].fields[3]
assert(kh.visibleWhen=='BarsA' and kh.visibleValues[1]==7 and kh.labelWhen==nil)
assert(kv.visibleWhen=='BarsA' and kv.visibleValues[1]==5)
assert(kv.labelWhen=='BarsA' and kv.labelValues[1]==5 and kv.labelText=='Vertical Keys')
local _,plain=Provider.template({{id='Bars',label='Bars',fields={
    {id='.A',label='Orientation',values=orientation,default=7}}}},{})
assert(plain[1].fields[1].visibleWhen==nil and plain[1].fields[1].labelWhen==nil)

local function rejects(menu,variations,pattern)
    local ok,why=pcall(Provider.template,menu,variations or {})
    assert(not ok and tostring(why):find(pattern,1,true),tostring(why))
end
local function bars(dependent,first)
    local fields={{id='.A',label='Orientation',values=orientation,default=7},dependent}
    if first then fields={dependent,fields[1]} end
    return {{id='Bars',label='Bars',fields=fields}}
end
local function keys(conditions)
    return {id='.K',label='Keys',values={[0]='A',[1]='B'},default=0,conditions=conditions}
end
rejects(bars(keys({visible={field='.A',match={7}}}),true),nil,'declared earlier')
rejects(bars(keys({visible={field='.Missing',match={7}}})),nil,'declared earlier')
rejects(bars(keys({visible={field='.A',match={3}}})),nil,'distinct source choice')
rejects(bars(keys({visible={field='.A',match={}}})),nil,'must not be empty')
rejects(bars(keys({visible={field='.A',match={7},text='x'}})),nil,'unsupported property text')
rejects(bars(keys({hidden={field='.A',match={7}}})),nil,'unsupported property hidden')
rejects(bars(keys({label={field='.A',match={7}}})),nil,'label.text')
rejects(bars(keys({label={field='.A',match={7},text='a;b'}})),nil,'unsupported metadata text')
rejects(bars({id='.S',label='Size',values='percent',default=1,
    conditions={visible={field='.S',match={1}}}}),nil,'declared earlier')
-- A field in a variation branch must depend on a picker in that branch.
rejects({{id='Bars',label='Bars',fields={{id='.A',label='Orientation',values=orientation,default=7}}},
    {id='Extra',label='Extra',variation={style=1},fields={keys({visible={field='BarsA',match={7}}})}}},
    {style={values={[0]='A',[1]='B'},default=0}},'same variation branch')
rejects({{id='K',label='K',values={[0]='A',[1]='B'},default=0,
    conditions={visible={field='.Style',match={0}}}}},
    {style={values={[0]='A',[1]='B'},default=0}},'must be absolute')
local _,variationSource=Provider.template({{id='K',label='K',values={[0]='A',[1]='B'},default=0,
    conditions={visible={field='Style',match={1}}}}},{style={values={[0]='A',[1]='B'},default=0}})
assert(variationSource[2].fields[1].visibleWhen=='Style','a shared field may depend on a variation')

print('PASS: concise template fields, value domains, variations, relative IDs and conditions')
