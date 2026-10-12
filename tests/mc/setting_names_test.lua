-- A template that moves to another category keeps its readable setting ids, so
-- its saved settings, its enablement among them, still apply.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local Menu=require('mc.menu')
local Model=require('mc.menu_model')

local function category(name)
    return {id=name,objects={root={source='lookup',object='hud'}},settings={},menu={}}
end
local function template(categoryName)
    return {name='Cue',module='Mod',category=categoryName,objects={'root'},managed=false,
        menu={{id='Main',label='Main',fields={{id='Size',label='Size',values={min=0,max=100,step=1},default=20}}}},
        attach=function() end,update=function() end,detach=function() end}
end
local location='/mods/Mod/Scripts/mc.lua'
local function generate(categoryName,catalog)
    local menu=Menu.generate(Model.build({category(categoryName)},{template(categoryName)},{location}).registry,
        {catalog=catalog})
    local ids={}
    for _,row in ipairs(menu.pageByModule.Mod.rows) do ids[row.label]=row.id end
    return menu,ids
end

local before,old=generate('player.notifications')
assert(old.Enabled=='MCT_Cue_Enabled' and old.Size=='MCT_Cue_Size')
local after,moved=generate('npc.attacks',before.catalog)
assert(moved.Enabled==old.Enabled and moved.Size==old.Size,
    'the moved template takes over the ids its old category no longer uses')
for identity in pairs(after.catalog.names) do
    assert(not identity:find('player.notifications',1,true),'ids no longer generated are dropped')
end

-- A catalog saved before this rule gave the moved template numeric ids while
-- its old category held the readable ones: the next run takes them back.
local stale={version=1,next=before.catalog.next+100,entries=before.catalog.entries,names={}}
for identity,name in pairs(before.catalog.names) do stale.names[identity]=name end
local fallback=0
for identity in pairs(after.catalog.names) do
    fallback=fallback+1
    stale.names[identity]='MCT_'..(900+fallback)
end
local _,restored=generate('npc.attacks',stale)
assert(restored.Enabled=='MCT_Cue_Enabled' and restored.Size=='MCT_Cue_Size','the readable ids come back')
print('PASS: a template moved to another category keeps its readable setting ids')
