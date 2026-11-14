package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local Metadata=require('mc.module_metadata')
local root=assert(os.getenv('MCT_TEST_DIR'),'MCT_TEST_DIR required')..'/9_ModCore_Provider'

-- A template's module is its mod folder; MCT never reads the folder's mod.json, which
-- ModCoreSettings reads for the module's name, author, version and icon.
local template=Metadata.apply({id='Template',category='player.quickslots'},root..'/Scripts/mc_template.lua')
assert(template.module=='9_ModCore_Provider' and template.author==nil and template.version==nil
    and template.icon==nil)
assert(Metadata.apply({id='T'},root..'\\Scripts\\mc_nested.lua').module=='9_ModCore_Provider',
    'Windows paths resolve to the same folder')
assert(Metadata.apply({id='T'},root..'/Scripts/templates/mc_nested.lua').module==nil,
    'a file below Scripts is not a module template')
-- The folder wins over a declared module; outside a mod folder the declared one is kept.
assert(Metadata.apply({id='T',module='Other'},root..'/Scripts/mc_template.lua').module=='9_ModCore_Provider')
assert(Metadata.apply({module='Declared'},'template').module=='Declared')
assert(Metadata.apply({},'template').module==nil)
-- providerId is the module id ModCoreSettings gives for the folder, else the folder name.
local asked
local function moduleId(folder) asked=folder; return folder=='9_ModCore_Provider' and 'Provider' or nil end
assert(Metadata.apply({id='T'},root..'/Scripts/mc_template.lua',moduleId).providerId=='Provider'
    and asked=='9_ModCore_Provider')
local other=assert(os.getenv('MCT_TEST_DIR'))..'/Unknown'
assert(Metadata.apply({id='T'},other..'/Scripts/mc_template.lua',moduleId).providerId=='Unknown')
assert(Metadata.apply({id='T'},root..'/Scripts/mc_template.lua').providerId=='9_ModCore_Provider')
assert(Metadata.apply({},'template',moduleId).providerId==nil, 'outside a mod folder there is no provider')
-- Template ids are unique within a module only: loading prefixes them with the module id
-- and keeps the declared id, once, even when the same table is applied again.
local wheels={id='Wheels',category='player.quickslots'}
Metadata.apply(wheels,root..'/Scripts/mc_wheels.lua',moduleId)
assert(wheels.id=='Provider_Wheels' and wheels.localId=='Wheels',wheels.id)
Metadata.apply(wheels,root..'/Scripts/mc_wheels.lua',moduleId)
assert(wheels.id=='Provider_Wheels','applying again does not prefix twice')
assert(Metadata.apply({id='Wheels'},'template').id=='Wheels','outside a mod folder the id stays')
assert(not pcall(Metadata.apply,{id='9bad'},root..'/Scripts/mc_bad.lua'),'the declared id is validated')
print('PASS: a template\'s module is the mod folder holding its provider file')
