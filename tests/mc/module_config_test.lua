package.path='./Scripts/?.lua;'..package.path
local Bootstrap=require('mc.bootstrap')
local Layout=require('mc.layout')
local Menu=require('mc.menu')
local Model=require('mc.menu_model')

local testRoot=assert(os.getenv('MCT_TEST_DIR'),'MCT_TEST_DIR required')..'/module-config'
local moduleRoot=testRoot..'/Fangdango'
local menuRoot=testRoot..'/ModCoreTemplates'
Layout.prepare(moduleRoot)

local field={id='Size',label='Size',values={min=0,max=100,step=1},default=20}
local category={name='player.quickslots',single=true,
    objects={root={source='lookup',object='switcher'}},settings={},menu={}}
local template={id='Wheels',name='Wheels',module='Fangdango',category=category.name,
    objects={'root'},managed=false,
    menu={{id='Layout',label='Layout',fields={field}}},
    attach=function() end,update=function() end,detach=function() end}
local location=moduleRoot..'/Scripts/mc.lua'
local preview=Menu.generate(Model.build({category},{template},{location}).registry)
local sizeId
for _,definition in pairs(preview.definitions[category.name]) do
    if definition.id=='Wheels' then sizeId=definition.settings.Size end
end
assert(sizeId and preview.pageByModule.Fangdango.configPath==moduleRoot..'/config.ini')
assert(preview.pageByModule.Fangdango.providerPath==moduleRoot..'/enabled.txt')
assert(preview.pageByModule.Fangdango.manifest:find('ConfigFile=config.ini',1,true))

local legacyPath=Layout.prepare(menuRoot).config
local legacy=assert(io.open(legacyPath,'wb'))
legacy:write('[Templates]\n'..sizeId..'=73\n');legacy:close()
local startupError
local host={valid=function() return true end,identity=function(value) return value end,
    ready=function() return true end,parent=function() end,screen=function()
        return {width=1920,height=1080,left=0,center=960,right=1920,bottom=0,middle=540,top=1080}
    end,matches=function() return false end,find=function() return {} end,
    watch=function() return function() end end,subscribe=function() return function() end end,
    onError=function(value) startupError=value.message end}
local definitions={[location]=template}
local barrier
local boot=Bootstrap.new({host=host,categories={category},
    execute=function(path) return definitions[path] end,menuRoot=menuRoot,
    subscribeLoopStart=function(callback) barrier=callback;return function() end end})
boot:registerTemplate(location)
barrier();assert(boot.phase=='running',startupError)
local moduleConfig=assert(io.open(moduleRoot..'/config.ini','rb'))
local moduleContent=moduleConfig:read('*a');moduleConfig:close()
assert(moduleContent:find(sizeId..'=73',1,true),'legacy value was not migrated')
local central=assert(io.open(legacyPath,'rb'))
local centralContent=central:read('*a');central:close()
assert(centralContent:find(sizeId..'=73',1,true),'legacy config should be preserved')
assert(boot.menuController:values()[sizeId]==73,'runtime did not load module config')
boot:stop()
print('PASS: module-target settings use and migrate to the module config')
