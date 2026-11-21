-- Where generated rows are saved: a template's rows as [<Module>.<Template>] <Setting>,
-- a category's template picks as [Templates] <Category>, its shared fields as
-- [<category>] <Setting>. Templates declare
-- nothing for it; their menu ids are unchanged.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local Menu=require('mc.menu')
local Model=require('mc.menu_model')

local category={id='npc.attacks',objects={root={source='lookup',object='hud'}},settings={},
    menu={groups={{id='Shared',label='Shared',fields={
        {id='Glow',label='Glow',type='integer',min=0,max=10,step=1,default=5},
        {id='Note',type='text',default='plain'},
    }}}}}
local function template(id,fields,extra)
    local t={id=id,module='Preymonition',providerId='Preymonition',category=category.id,
        objects={'root'},managed=false,menu={{id='Parry',label='Parry',fields=fields}},
        attach=function() end,update=function() end,detach=function() end}
    for key,value in pairs(extra or {}) do t[key]=value end
    return t
end
local location='/Mods/Preymonition/Scripts/mc_cues.lua'
local function generate(templates)
    local locations={}
    for index in ipairs(templates) do locations[index]=location end
    return Menu.generate(Model.build({category},templates,locations).registry)
end

local menu=generate({
    template('Omens',{{id='.Style',label='Style',values={{key='off',label='Off'},{key='on',label='On'}},default='on'},
        {id='.Size',label='Size',values={min=0,max=100,step=10},default=50}}),
    template('Bars',{{id='.Width',label='Width',values={min=0,max=10,step=1},default=2}},
        {uniqueBy='priority',priority=10}),
    template('Lines',{{id='.Width',label='Width',values={min=0,max=10,step=1},default=3}},
        {uniqueBy='priority',priority=10}),
})
local byId={}
for _,row in ipairs(menu.rows) do byId[row.id]=row end
local function at(id,section,key)
    local row=assert(byId[id],'no row '..id)
    local s,k=Menu.placeOf(row)
    assert(s==section and k==key,id..' saved at ['..tostring(s)..'] '..tostring(k)..', not ['..section..'] '..key)
end
local omens=menu.definitions[category.id].Omens
-- Menu ids keep naming the module and template.
assert(omens.settings.ParryStyle=='MCT_Preymonition_Omens_ParryStyle')
at(omens.settings.ParryStyle,'Preymonition.Omens','ParryStyle')
at(omens.settings.ParrySize,'Preymonition.Omens','ParrySize')
at(omens.enabledId,'Preymonition.Omens','Enabled')
at(menu.definitions[category.id].Bars.settings.ParryWidth,'Preymonition.Bars','ParryWidth')
at('MCT_NpcAttacksPriority10Template','Templates','NpcAttacksPriority10')
at('MCT_NpcAttacksGlow',category.id,'Glow')
-- A category's text setting has no row; it is saved beside the shared fields.
local note=menu.textSettings.MCT_NpcAttacksNote
assert(note and note.storage.section==category.id and note.storage.key=='Note')

-- The page hands the place to ModCoreSettings as the field's storage.
local page=menu.pageByModule.Preymonition
local published={}
for _,field in ipairs(page.menu.fields) do published[field.id]=field end
assert(published[omens.settings.ParryStyle].storage.section=='Preymonition.Omens'
    and published[omens.settings.ParryStyle].storage.key=='ParryStyle')
assert(page.menu.storage.file=='config.ini')
-- ModCoreSettings compiles it to the row's own section and key, when on LUA_PATH (not in CI).
local hasMenuData,MenuData=pcall(require,'menu_data')
if hasMenuData then
    local manifest=MenuData.manifest(page.menu)
    assert(manifest:find('ConfigSection=Preymonition.Omens',1,true)
        and manifest:find('ConfigKey=ParrySize',1,true),'ModCoreSettings stores at the row\'s place')
else
    print('SKIP: ModCoreSettings menu_data not on LUA_PATH')
end

-- Two rows at one place fail the menu: a module npc's template attacks saving Glow
-- where the npc.attacks category saves its own.
local ok,why=pcall(generate,{template('attacks',{{id='Glow',label='Glow',values={min=0,max=1,step=1},default=0}},
    {module='npc',providerId='npc'})})
assert(not ok and tostring(why):find('menu storage clash',1,true),tostring(why))

print('PASS: template rows are saved per template, category rows per category')
