-- Setting ids are derived from the template, not stored: a template that moves to
-- another category keeps its readable ids, so its saved settings, its enablement among
-- them, still apply. Two templates deriving the same id fail the menu.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local Menu=require('mc.menu')
local Model=require('mc.menu_model')

local function category(name)
    return {id=name,objects={root={source='lookup',object='hud'}},settings={},menu={}}
end
local function template(categoryName,id,providerId,localId)
    return {id=id or 'Cue',localId=localId,providerId=providerId,module='Mod',category=categoryName,
        objects={'root'},managed=false,
        menu={{id='Main',label='Main',fields={{id='Size',label='Size',values={min=0,max=100,step=1},default=20}}}},
        attach=function() end,update=function() end,detach=function() end}
end
local location='/mods/Mod/Scripts/mc.lua'
local function generate(categoryName)
    local menu=Menu.generate(Model.build({category(categoryName)},{template(categoryName)},{location}).registry)
    local ids={}
    -- The Enabled toggle is labelled with the template's name.
    for _,row in ipairs(menu.pageByModule.Mod.rows) do ids[row.label=='Cue' and 'Enabled' or row.label]=row.id end
    return menu,ids
end

local _,old=generate('player.notifications')
assert(old.Enabled=='MCT_Cue_Enabled' and old.Size=='MCT_Cue_Size')
local _,moved=generate('npc.attacks')
assert(moved.Enabled==old.Enabled and moved.Size==old.Size,'a moved template keeps its ids')

-- A loaded template's ids name its module, then its own id: MCT_<Module>_<Template>_...
local named=Menu.generate(Model.build({category('npc.attacks')},
    {template('npc.attacks','Mod_Cue','Mod','Cue')},{location}).registry)
local found
for _,row in ipairs(named.pageByModule.Mod.rows) do found=found or row.id=='MCT_Mod_Cue_Size' end
assert(found,'module and template id are separated by _')

-- Module 'A.B' with template 'Cue' and module 'AB' with template 'Cue' derive the same
-- names: the menu fails, and loading rejects the later provider file.
local ok,why=pcall(Menu.generate,Model.build({category('npc.attacks')},
    {template('npc.attacks','A.B_Cue','A.B','Cue'),template('npc.attacks','AB_Cue','AB','Cue')},
    {location,location}).registry)
assert(not ok and tostring(why):find('menu id clash',1,true),tostring(why))
print('PASS: setting ids are derived from module and template, and a clash fails the menu')
