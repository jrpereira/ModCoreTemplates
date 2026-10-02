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
assert(declaration.groups[1].fields[2].id=='ControlLayoutLink')
assert(declaration.groups[1].fields[2].tab==nil)
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
assert(dropdown[2].fields[1].tab==false)

local choices={}
for value=1,9 do choices[value]='Choice '..value end
local _,largePicker=Provider.template({
    {id='Choice',label='Choice',values=choices,default=1},
}, {})
assert(largePicker[2].fields[1].tab==nil)

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

print('PASS: concise template fields, value domains, variations and relative IDs')
