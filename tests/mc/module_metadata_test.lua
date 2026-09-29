package.path='./Scripts/?.lua;'..package.path
local Metadata=require('mc.module_metadata')
local Layout=require('mc.layout')
local root=assert(os.getenv('MCT_TEST_DIR'),'MCT_TEST_DIR required')..'/MetadataProvider'
Layout.prepare(root)
local manifest=assert(io.open(root..'/mod.json','wb'))
manifest:write([[{
  "manifest_version": 1,
  "id": "MetadataProvider",
  "name": "Metadata Provider",
  "author": "A \"Quoted\" Author",
  "version": "2.3.4"
}]])
manifest:close()
local template={name='Template',category='player.quickslots'}
Metadata.apply(template,root..'/Scripts/mc_template.lua')
assert(template.module=='MetadataProvider' and template.author=='A "Quoted" Author'
    and template.version=='2.3.4')
assert(not pcall(Metadata.apply,{module='Other'},root..'/Scripts/mc_template.lua'))
print('PASS: module metadata is discovered from the provider manifest')
