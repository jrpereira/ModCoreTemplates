package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local Bootstrap=require('mc.bootstrap')
local Layout=require('mc.layout')
local Menu=require('mc.menu')
local Model=require('mc.menu_model')
local Provider=require('mc.provider_settings')
-- The compiled declaration and its normalized groups, as menu_model takes them.
local function template(menu,variations)
    local declaration=Provider.template(menu,variations)
    return declaration,Provider.normalize(declaration)
end
local Ini=require('mc_ini')
-- A key's first value in a config section, as mc_ini reads it.
local function iniValue(content,section,key)
    local entry=Ini.entries(Ini.parse(content),section,key)[1]
    return entry and entry.value
end

-- Declaring a range: {low, high} defaults become the stored '<low>|<high>'.
local function fails(pattern,source)
    local ok,err=pcall(template,{{id='Layout',label='Layout',fields={source}}})
    assert(not ok and tostring(err):find(pattern,1,true),'expected '..pattern..', got '..tostring(err))
end
local function range(change)
    local source={id='Grow',label='Grow',type='range',values={min=0,max=100,step=10,suffix='%',delta={10}},default={20,60}}
    if change then change(source) end
    return source
end
local _,groups=template({{id='Layout',label='Layout',fields={range()}}})
local grow=groups[1].fields[1]
assert(grow.type=='range' and grow.widget=='range' and grow.default=='20|60' and grow.bounds.deltaMin==10
    and grow.bounds.step==10,'a range normalizes')
fails('provider range default',range(function(s) s.default={20,25} end))
fails('provider range default',range(function(s) s.default={20,20} end))
fails('provider range default',range(function(s) s.default=20 end))
fails('divide max-min',range(function(s) s.values.step=1;s.values.max=100 end))
fails('on the step',range(function(s) s.values.delta={15} end))
fails('unsupported property',range(function(s) s.values.width=1 end))
fails("need type='range'",range(function(s) s.type=nil end))
fails('takes no tabs widget',range(function(s) s.widget='tabs' end))
fails('low marker',range(function(s) s.values.min={50,0} end))
fails('leave no value',range(function(s) s.values.min={0,60};s.values.max={40,100};s.values.delta={0,10} end))
assert(Provider.rangeText(grow.bounds,'20 | 60')=='20|60' and Provider.rangeText(grow.bounds,'60|20')==nil
    and Provider.rangeText(grow.bounds,{0,100})=='0|100' and Provider.rangeText(grow.bounds,'0|105')==nil)
assert(Provider.rangePair('20|60')[1]==20 and Provider.rangePair('20|60')[2]==60)
-- Pairs give each marker its own bounds; one delta number is both limits.
local _,zoned=template({{id='Layout',label='Layout',fields={range(function(s)
    s.values={min={0,60},max={40,100},step=10};s.default={40,60} end)}}})
local zones=zoned[1].fields[1].bounds
assert(zones.lowMax==40 and zones.highMin==60 and Provider.rangeText(zones,'50|60')==nil
    and Provider.rangeText(zones,'0|100')=='0|100','each marker keeps to its bounds')
print('PASS: a range declares min, max, step, delta and a {low, high} default')

-- A template's range: menu data, module config, and {low, high} for the template.
local testRoot=assert(os.getenv('MCT_TEST_DIR'),'MCT_TEST_DIR required')..'/span-setting'
local moduleRoot=testRoot..'/Preymonition'
local menuRoot=testRoot..'/ModCoreTemplates'
Layout.prepare(moduleRoot)
local category={id='player.quickslots',
    objects={root={source='lookup',object='switcher'}},settings={},menu={}}
local seen
local template={id='Center',module='Preymonition',providerId='Preymonition',category=category.id,uniqueBy='category',
    objects={'root'},managed=false,
    menu={{id='Parry',label='Parry',fields={range()}}},
    attach=function() end,update=function() end,detach=function() end}
local location=moduleRoot..'/Scripts/mc_center.lua'
local preview=Menu.generate(Model.build({category},{template},{location}).registry)
-- Loading prefixes the id with the module folder; the preview's setting ids already
-- name the module through providerId.
local growId,selectorValue
for _,definition in pairs(preview.definitions[category.id]) do
    if definition.id=='Center' then growId=definition.settings.Grow end
end
selectorValue='Preymonition_Center'
local page=preview.pageByModule.Preymonition
local field
for _,item in ipairs(page.menu.fields) do if item.id==growId then field=item end end
assert(field and field.type=='range' and field.values.min==0 and field.values.delta[1]==10 and field.values.suffix=='%'
    and field.default[1]==20 and field.default[2]==60 and field.widget==nil,'the page carries a range field')
-- ModCoreSettings compiles it, when its Scripts are on LUA_PATH (not in CI).
local hasMenuData,MenuData=pcall(require,'menu_data')
if hasMenuData then
    local manifest=MenuData.manifest(page.menu)
    assert(manifest:find('Type=range',1,true) and manifest:find('Default=20|60',1,true),'ModCoreSettings takes the range')
else
    print('SKIP: ModCoreSettings menu_data not on LUA_PATH')
end

local selectorId=preview.selectors[category.id].id
-- Saved as [<Module>.<Template>] <Setting>; the category's pick as [Templates] <Category>.
assert(field.storage.section=='Preymonition.Center' and field.storage.key=='Grow')
local growSection,growKey=field.storage.section,field.storage.key
-- The pick lives in MCT's central config, the template's settings in its module's.
local centralPath=Layout.prepare(menuRoot).config
local saved=assert(io.open(centralPath,'wb'))
saved:write('[Templates]\nPlayerQuickslots='..selectorValue..'\n');saved:close()
local startupError
local host={valid=function() return true end,identity=function(value) return value end,
    ready=function() return true end,parent=function() end,screen=function()
        return {width=1920,height=1080,left=0,center=960,right=1920,bottom=0,middle=540,top=1080}
    end,matches=function() return false end,find=function() return {} end,
    watch=function() return function() end end,subscribe=function() return function() end end,
    onError=function(value) startupError=value.message end}
local boot=Bootstrap.new({host=host,categories={category},
    execute=function(path) return ({[location]=template})[path] end,menuRoot=menuRoot,
    subscribeLoopStart=function(callback) seen=callback;return function() end end})
boot:registerTemplate(location)
seen();assert(boot.phase=='running',startupError)
local function config()
    local file=assert(io.open(moduleRoot..'/config.ini','rb'))
    local text=file:read('*a');file:close()
    return text
end
assert(iniValue(config(),growSection,growKey)=='20|60','a missing range is written with its default')
local function state()
    return boot.menu.decodeState(boot.menuController:values())[category.id].selections.Preymonition_Center
end
assert(state().Grow[1]==20 and state().Grow[2]==60,'the template reads {low, high}')
-- Apply: settings_api v2 carries the range as its stored text.
local text=Ini.set(config(),growSection,growKey,'30|80')
saved=assert(io.open(moduleRoot..'/config.ini','wb'));saved:write(text);saved:close()
local providerId=page.id
assert(boot.menuController:apply({providerId=providerId,revision=1,values={[selectorId]=selectorValue,[growId]='30|80'}}))
assert(boot.menuController:values()[growId]=='30|80' and state().Grow[1]==30 and state().Grow[2]==80,
    'Apply takes the range from the notification')
assert(not pcall(boot.menuController.apply,boot.menuController,
    {providerId=providerId,revision=2,values={[selectorId]=selectorValue,[growId]='30|35'}}),
    'a range the track cannot hold is refused')
-- A saved range the track cannot hold is rewritten with the default at the next start.
assert(require('mc.menu_files').readConfigValues(moduleRoot..'/config.ini',{},page.rows)[growId]=='30|80')
text=Ini.set(config(),growSection,growKey,'30|35')
saved=assert(io.open(moduleRoot..'/config.ini','wb'));saved:write(text);saved:close()
assert(require('mc.menu_files').readConfigValues(moduleRoot..'/config.ini',{},page.rows)[growId]==nil,
    'an invalid range is left out')
assert(require('mc.menu_files').ensureConfig(moduleRoot..'/config.ini',page.rows,{}))
assert(iniValue(config(),growSection,growKey)=='20|60','an invalid range is rewritten with its default')
boot:stop()
print('PASS: a template range is menu data, stored as text and read as {low, high}')
