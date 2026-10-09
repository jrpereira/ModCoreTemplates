package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local Metadata=require('mc.module_metadata')
local root=assert(os.getenv('MCT_TEST_DIR'),'MCT_TEST_DIR required')..'/9_ModCore_Provider'

-- A template's module is its mod folder; MCT never reads the folder's mod.json, which
-- ModCoreSettings reads for the module's name, author, version and icon.
local template=Metadata.apply({name='Template',category='player.quickslots'},root..'/Scripts/mc_template.lua')
assert(template.module=='9_ModCore_Provider' and template.author==nil and template.version==nil
    and template.icon==nil)
assert(Metadata.apply({},root..'\\Scripts\\templates\\nested.lua').module=='9_ModCore_Provider',
    'templates under Scripts/templates and Windows paths resolve to the same folder')
-- The folder wins over a declared module; outside a mod folder the declared one is kept.
assert(Metadata.apply({module='Other'},root..'/Scripts/mc_template.lua').module=='9_ModCore_Provider')
assert(Metadata.apply({module='Declared'},'template').module=='Declared')
assert(Metadata.apply({},'template').module==nil)
print('PASS: a template\'s module is the mod folder holding its provider file')
