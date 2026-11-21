-- ModCoreSettings limits each published page to 256 fields, so MCT checks each page,
-- not the total over all modules.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local Menu=require('mc.menu')
local Model=require('mc.menu_model')

local function template(module,category,count)
    local fields={}
    for index=1,count do
        fields[index]={id='F'..index,label='Field '..index,values={min=0,max=10,step=1},default=1}
    end
    return {id='T',module=module,providerId=module,category=category,uniqueBy='category',
        objects={'root'},managed=false,menu={{id='Main',label='Main',fields=fields}},
        attach=function() end,update=function() end,detach=function() end}
end
local function category(id)
    return {id=id,objects={root={source='lookup',object='root'}},settings={},menu={}}
end
local function generate(sizes)
    local categories,templates,locations={},{},{}
    for index,count in ipairs(sizes) do
        local module='Module'..index
        categories[index]=category('test.c'..index)
        templates[index]=template(module,categories[index].id,count)
        locations[index]='/mods/'..module..'/Scripts/mc.lua'
    end
    return pcall(Menu.generate,Model.build(categories,templates,locations).registry)
end

local ok,menu=generate({150,150})
assert(ok,'two pages of about 150 settings each fit: '..tostring(menu))
assert(#menu.rows>256,'the total passes 256 without failing')
ok,menu=generate({300})
assert(not ok and tostring(menu):find('Module1: page exceeds 256 settings',1,true),
    'one page over 256 fails: '..tostring(menu))
print('PASS: the 256-setting limit applies per page')
