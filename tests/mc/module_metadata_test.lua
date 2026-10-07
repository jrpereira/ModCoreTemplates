package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local Metadata=require('mc.module_metadata')
local Layout=require('mc.layout')
local root=assert(os.getenv('MCT_TEST_DIR'),'MCT_TEST_DIR required')..'/MetadataProvider'
Layout.prepare(root)
local function manifest(content)
    local output=assert(io.open(root..'/mod.json','wb'))
    assert(output:write(content));assert(output:close())
end
manifest([[{
  "manifest_version": 1,
  "id": "MetadataProvider",
  "name": "Metadata Provider",
  "author": "A \"Quoted\" Author",
  "version": "2.3.4"
}]])
local template={name='Template',category='player.quickslots'}
Metadata.apply(template,root..'/Scripts/mc_template.lua')
assert(template.module=='MetadataProvider' and template.author=='A "Quoted" Author'
    and template.version=='2.3.4')
assert(not pcall(Metadata.apply,{module='Other'},root..'/Scripts/mc_template.lua'))
manifest([[{"dependencies":[{"id":"Nested","version":"0.0.1"}],
    "author":"A \uD83D\uDE00 Author","version":"2.3.4","id":"MetadataProvider"}]])
local nested=assert(Metadata.read(root..'/Scripts/mc_template.lua'))
assert(nested.module=='MetadataProvider' and nested.version=='2.3.4'
    and nested.author=='A '..utf8.char(0x1F600)..' Author')
manifest([[{"dependencies":[{"id":"Nested"}],"id":"MetadataProvider",
    "version_source":"Scripts/main.lua"}]])
local minimal=assert(Metadata.read(root..'/Scripts/mc_template.lua'))
assert(minimal.module=='MetadataProvider' and minimal.author==nil and minimal.version==nil)
for _,content in ipairs({
    [[{"dependencies":[{"id":"Nested"}],"author":"A"}]],
    [[{"id":"One","id":"Two","author":"A","version":"1"}]],
    [[{"id":"One","author":"A","version":"1","name":"\uD83D"}]],
    [[{"id":"One","author":"A","version":"1","name":"\uDE00"}]],
    [[{"id":"One","author":"A","version":"1",}]],
    [[{"id":"One","author":"A","version":"1"} trailing]],
}) do
    manifest(content)
    assert(not pcall(Metadata.read,root..'/Scripts/mc_template.lua'))
end
print('PASS: module metadata is discovered from the provider manifest')
