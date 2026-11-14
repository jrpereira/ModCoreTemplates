package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local Registration=require('mc.registration')
local repoRoot=debug.getinfo(1,'S').source:match('^@(.+)/tests/mc/registration_test%.lua$') or assert(os.getenv('PWD'))
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
    client.registerTemplate('sample')
    _G.ModRef=previous
    assert(values['MCT.TemplateRegistration.v1.1.count']==1)
    assert(values['MCT.TemplateRegistration.v1.1.item.1']:match('tests/mc/mc_sample%.lua$'))
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
    assert(not pcall(client.registerTemplate,'late'))
    _G.ModRef=previous
end)

test('an invalid registered path is rejected alone',function()
    local state,values=shared()
    local publisher=Registration.publisher(state,'C:\\Games\\Mods\\')
    publisher:begin()
    local items={'c:/games/mods/Good/Scripts/mc_good.lua',
        'C:/Games/Mods/Other/Scripts/templates/mc_x.lua',
        'D:/Elsewhere/Scripts/mc_y.lua',
        42,
        'C:\\Games\\Mods\\Win\\Scripts\\mc_win.lua'}
    for index,item in ipairs(items) do values['MCT.TemplateRegistration.v1.1.item.'..index]=item end
    values['MCT.TemplateRegistration.v1.1.count']=#items
    local rejected={}
    local paths=publisher:collect(function(path,why) rejected[#rejected+1]={path=path,why=why} end)
    assert(#paths==2 and paths[1]==items[1] and paths[2]==items[5],'valid paths are kept, prefix case-insensitive')
    assert(#rejected==3,'each invalid path is reported')
    assert(rejected[1].path==items[2] and rejected[1].why:match('outside a mod Scripts directory'))
    assert(rejected[2].path==items[3])
    assert(rejected[3].path==nil and rejected[3].why=='invalid registered template path')
end)

test('an invalid count still fails collection',function()
    local state,values=shared()
    local publisher=Registration.publisher(state,repoRoot)
    publisher:begin()
    values['MCT.TemplateRegistration.v1.1.count']=-1
    assert(not pcall(publisher.collect,publisher))
end)

test('client installation is content-aware',function()
    local root=assert(os.getenv('MCT_TEST_DIR'),'MCT_TEST_DIR required')..'/registration-client.lua'
    assert(Registration.install('./Scripts/mc_client.lua',root))
    assert(not Registration.install('./Scripts/mc_client.lua',root))
    local installed=assert(loadfile(root))()
    assert(type(installed.registerTemplate)=='function')
end)

print('PASS: '..passed..' cross-state template registration tests')
