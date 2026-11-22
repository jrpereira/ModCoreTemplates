-- Which file a row is saved in, with MCT published from its Mods folder: a category's rows
-- (picker, priority pickers, shared fields) in MCT's central config on every page that
-- shows them, a template's rows in its own mod's config.ini on every page, module, slot
-- and category pages alike. Pages name their files relative to the Mods folder.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local Bootstrap=require('mc.bootstrap')
local Layout=require('mc.layout')
local Menu=require('mc.menu')
local Model=require('mc.menu_model')
local Ini=require('mc_ini')
local function iniValue(content,section,key)
    local entry=Ini.entries(Ini.parse(content),section,key)[1]
    return entry and entry.value
end
local function read(path)
    local file=io.open(path,'rb')
    if not file then return '' end
    local content=file:read('*a');file:close()
    return content
end
local function write(path,content)
    local file=assert(io.open(path,'wb'));file:write(content);file:close()
end

local mods=assert(os.getenv('MCT_TEST_DIR'),'MCT_TEST_DIR required')..'/storage-files/Mods'
local menuRoot=mods..'/3_ModCore_Templates'
local central='3_ModCore_Templates/Scripts/cache/config.ini'
local radial={id='player.radial',objects={root={source='lookup',object='radial'}},settings={},
    menu={groups={{id='Shared',label='Shared',fields={
        {id='Glow',label='Glow',type='integer',min=0,max=10,step=1,default=5}}}}}}
local quickslots={id='player.quickslots',objects={root={source='lookup',object='switcher'}},settings={},
    menu={},slot={provider='controls',slot='visuals'}}
local function template(module,id,category)
    return {id=id,module=module,providerId=module,category=category.id,uniqueBy='category',
        objects={'root'},managed=false,menu={{id='Look',label='Look',fields={
            {id='.Size',label='Size',values={min=0,max=100,step=1},default=20}}}},
        attach=function() end,update=function() end,detach=function() end}
end
local categories={radial,quickslots}
local templates={template('A','One',radial),template('B','Two',radial),
    template('A','Bar',quickslots),template('B','Wide',quickslots)}
local locations={mods..'/A/Scripts/mc.lua',mods..'/B/Scripts/mc.lua',
    mods..'/A/Scripts/mc.lua',mods..'/B/Scripts/mc.lua'}
for _,module in ipairs({'A','B'}) do Layout.prepare(mods..'/'..module) end
Layout.prepare(menuRoot)

-- The generated pages.
local function copies(list)
    local out={}
    for index,value in ipairs(list) do out[index]=value end
    return out
end
local menu=Menu.generate(Model.build(categories,copies(templates),copies(locations)).registry,{root=menuRoot})
local picker=menu.selectors['player.radial'].id
local glow='MCT_PlayerRadialGlow'
local function fields(page)
    local byId={}
    for _,field in ipairs(page.menu.fields) do byId[field.id]=field end
    return byId
end
for _,module in ipairs({'A','B'}) do
    local page=assert(menu.pageByModule[module],'no page for '..module)
    local byId=fields(page)
    assert(page.configDirectory==mods and page.menu.storage.file==central,
        module..': the page names its files from the Mods folder, the central config by default')
    -- One copy of the category's rows: both module pages store them in the central config.
    assert(byId[picker] and (byId[picker].storage.file or central)==central,module..': picker in the central config')
    assert(byId[glow] and (byId[glow].storage.file or central)==central,module..': shared field in the central config')
end
local function own(category,id) return menu.definitions[category][id] end
local oneSize=own('player.radial','One').settings.LookSize
assert(fields(menu.pageByModule.A)[oneSize].storage.file=='A/config.ini','a template row names its module config')
-- Slot pages too: the bar's rows go to its own mod, the pick to MCT.
local slot=assert(menu.pageBySlot['player.quickslots'])
local slotFields=fields(slot)
assert(slot.configDirectory==mods and slot.menu.storage.file==central)
assert(slotFields[own('player.quickslots','Wide').settings.LookSize].storage.file=='B/config.ini'
    and slotFields[own('player.quickslots','Bar').settings.LookSize].storage.file=='A/config.ini',
    'slot rows are saved in their template\'s mod')
assert(slotFields[menu.selectors['player.quickslots'].id].storage.file==nil,'the slot pick stays central')
-- ModCoreSettings takes the files, when on LUA_PATH.
local hasMenuData,MenuData=pcall(require,'menu_data')
if hasMenuData then
    for _,page in ipairs({menu.pageByModule.A,slot}) do
        local manifest=MenuData.manifest(page.menu)
        assert(manifest:find('ConfigFile='..central,1,true) and manifest:find('ConfigFile=A/config.ini',1,true),
            'ModCoreSettings stores each row in its own file')
    end
else
    print('SKIP: ModCoreSettings menu_data not on LUA_PATH')
end

-- Startup reads each row from its one file. A pick saved centrally reaches both module
-- pages; an old pick left in a module's config is ignored.
write(mods..'/A/config.ini','[Templates]\nPlayerRadial=A_One\n[A.One]\nLookSize=33\n')
write(mods..'/B/config.ini','[B.Two]\nLookSize=44\n')
write(menuRoot..'/'..Layout.configFile,'[Templates]\nPlayerRadial=B_Two\n')
local startupError
local host={valid=function() return true end,identity=function(value) return value end,
    ready=function() return true end,parent=function() end,screen=function()
        return {width=1920,height=1080,left=0,center=960,right=1920,bottom=0,middle=540,top=1080}
    end,matches=function() return false end,find=function() return {} end,
    watch=function() return function() end end,subscribe=function() return function() end end,
    onError=function(value) startupError=value.message end}
local definitions={}
local byLocation={}
for index,location in ipairs(locations) do
    byLocation[location]=byLocation[location] or {}
    table.insert(byLocation[location],templates[index])
end
local function boot()
    local barrier
    local started=Bootstrap.new({host=host,categories=categories,
        execute=function(path) return definitions[path] end,menuRoot=menuRoot,
        subscribeLoopStart=function(callback) barrier=callback;return function() end end})
    -- One provider file per template, as a module registers each of its templates.
    for index,template in ipairs(templates) do
        local path=locations[index]:gsub('mc%.lua$','mc_'..template.id:lower()..'.lua')
        definitions[path]=template
        started:registerTemplate(path)
    end
    barrier()
    assert(started.phase=='running',startupError)
    return started
end
local session=boot()
local values=session.menuController:values()
local livePicker=session.menu.selectors['player.radial'].id
assert(values[livePicker]=='B_Two','the central pick wins over an old copy in a module config')
local liveOne=session.menu.definitions['player.radial'].A_One.settings.LookSize
local liveTwo=session.menu.definitions['player.radial'].B_Two.settings.LookSize
assert(values[liveOne]==33 and values[liveTwo]==44,'template settings come from their own mods')
-- Missing rows are added to their own file only.
local centralText=read(menuRoot..'/'..Layout.configFile)
local aText,bText=read(mods..'/A/config.ini'),read(mods..'/B/config.ini')
assert(iniValue(centralText,'player.radial','Glow')=='5','the shared field is added centrally')
assert(not centralText:find('[A.One]',1,true) and not centralText:find('[B.Wide]',1,true),
    'no template row in the central config')
assert(iniValue(aText,'A.Bar','LookSize')=='20' and iniValue(bText,'B.Wide','LookSize')=='20',
    'slot template rows are added to their mods')
assert(iniValue(bText,'Templates','PlayerRadial')==nil,'no pick is added to a module config')
session:stop()
-- Apply on A's page, written centrally as ModCoreSettings does, is what B's page shows
-- after a restart.
write(menuRoot..'/'..Layout.configFile,Ini.set(read(menuRoot..'/'..Layout.configFile),'Templates','PlayerRadial','A_One'))
session=boot()
assert(session.menuController:values()[livePicker]=='A_One','one pick for both module pages')
session:stop()
print('PASS: category rows are saved centrally, template rows in their own mods')
