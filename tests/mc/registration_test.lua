package.path='./Scripts/?.lua;'..package.path
local Registration=require('mc.registration')
local repoRoot=assert(debug.getinfo(1,'S').source:match('^@(.+)/tests/mc/registration_test%.lua$'))
local passed=0
local function test(name,body)
    local ok,why=pcall(body)
    assert(ok,name..': '..tostring(why));passed=passed+1
end
local function shared()
    local values={}
    return {GetSharedVariable=function(_,key)return values[key]end,
        SetSharedVariable=function(_,key,value)values[key]=value end},values
end

test('shared client publishes provider template paths',function()
    local state,values=shared()
    local publisher=Registration.publisher(state,repoRoot)
    publisher:begin()
    local previous=_G.ModRef;_G.ModRef=state
    package.loaded.mc_client=nil
    local client=assert(loadfile('./Scripts/mc_client.lua'))()
    client.addTemplate('sample')
    _G.ModRef=previous
    assert(values['MCT.TemplateRegistration.v1.1.count']==1)
    assert(values['MCT.TemplateRegistration.v1.1.item.1']:match('/tests/mc/mc_sample%.lua$'))
end)

test('publisher collects once and closes registration',function()
    local state,values=shared()
    local publisher=Registration.publisher(state,repoRoot)
    publisher:begin()
    local previous=_G.ModRef;_G.ModRef=state
    local client=assert(loadfile('./Scripts/mc_client.lua'))()
    values['MCT.TemplateRegistration.v1.1.item.1']=repoRoot..'/Scripts/sample.lua'
    values['MCT.TemplateRegistration.v1.1.count']=1
    local paths=publisher:collect()
    assert(#paths==1 and paths[1]:match('/Scripts/sample%.lua$'))
    assert(not pcall(publisher.collect,publisher))
    assert(not pcall(client.addTemplate,'late'))
    _G.ModRef=previous
end)

test('client installation is content-aware',function()
    local root=assert(os.getenv('MCT_TEST_DIR'),'MCT_TEST_DIR required')..'/registration-client.lua'
    assert(Registration.install('./Scripts/mc_client.lua',root))
    assert(not Registration.install('./Scripts/mc_client.lua',root))
    local installed=assert(loadfile(root))()
    assert(type(installed.addTemplate)=='function')
end)

print('PASS: '..passed..' cross-state template registration tests')
