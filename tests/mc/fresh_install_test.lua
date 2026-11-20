package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
-- A release ZIP has no Scripts/cache folder (it is ignored by git): startup must create it
-- before writing the central config and the templates list there.
local Bootstrap=require('mc.bootstrap')
local Layout=require('mc.layout')

local testRoot=assert(os.getenv('MCT_TEST_DIR'),'MCT_TEST_DIR required')..'/fresh-install'
local moduleRoot=testRoot..'/Fangdango'
local menuRoot=testRoot..'/ModCoreTemplates'
require('safe_file').mkdir(moduleRoot..'/Scripts')
require('safe_file').mkdir(menuRoot..'/Scripts')
local paths=Layout.paths(menuRoot)
assert(not io.open(paths.cache..'/.probe','wb'),'cache folder must start missing')

local field={id='Size',label='Size',values={min=0,max=100,step=1},default=20}
local category={id='player.quickslots',
    objects={root={source='lookup',object='switcher'}},settings={},menu={}}
local template={id='Wheels',module='Fangdango',providerId='Fangdango',category=category.id,uniqueBy='category',
    objects={'root'},managed=false,
    menu={{id='Layout',label='Layout',fields={field}}},
    attach=function() end,update=function() end,detach=function() end}
local location=moduleRoot..'/Scripts/mc.lua'
local errors={}
local host={valid=function() return true end,identity=function(value) return value end,
    ready=function() return true end,parent=function() end,screen=function()
        return {width=1920,height=1080,left=0,center=960,right=1920,bottom=0,middle=540,top=1080}
    end,matches=function() return false end,find=function() return {} end,
    watch=function() return function() end end,subscribe=function() return function() end end,
    onError=function(value) errors[#errors+1]=value.stage..': '..value.message end}
local barrier
local boot=Bootstrap.new({host=host,categories={category},
    execute=function(path) return location==path and template or nil end,menuRoot=menuRoot,
    subscribeLoopStart=function(callback) barrier=callback;return function() end end})
boot:registerTemplate(location)
barrier()
assert(boot.phase=='running',table.concat(errors,'; '))
assert(#errors==0,table.concat(errors,'; '))
local config=io.open(paths.config,'rb')
assert(config,'central config was not written');config:close()
boot:stop()
print('PASS: a fresh install creates Scripts/cache and writes its config')
