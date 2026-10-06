package.path='./Scripts/?.lua;'..package.path
local Bootstrap=require('mc.bootstrap')
local repoRoot=debug.getinfo(1,'S').source:match('^@(.+)/tests/mc/template_path_test%.lua$') or assert(os.getenv('PWD'))
local folder=repoRoot..'/tests/fixtures/HelperProvider/Scripts'
local template=folder..'/mc_probe.lua'
local passed=0
local function test(name,body)
    local ok,why=pcall(body)
    assert(ok,name..': '..tostring(why));passed=passed+1
end
local function occurrences(entry)
    local count,start=0,1
    while true do
        local found=(';'..package.path..';'):find(';'..entry..';',start,true)
        if not found then return count end
        count,start=count+1,found+1
    end
end

test('registered templates require helpers from their own folder',function()
    local before=package.path
    local loaded=Bootstrap.executeTemplate(template)
    assert(loaded.category=='probe' and loaded.name=='Probe helper')
    assert(package.path:sub(1,#before)==before,'provider folder must follow MCT folders')
end)

test('provider folders are added to the search path once',function()
    package.loaded['helperprovider.shared']=nil
    Bootstrap.executeTemplate(template)
    Bootstrap.executeTemplate(template)
    assert(occurrences(folder..'/?.lua')==1)
end)

test('a template path without a folder is rejected',function()
    local ok,why=pcall(Bootstrap.executeTemplate,'mc_probe.lua')
    assert(not ok and tostring(why):find('template has no directory',1,true))
end)

print(('template_path_test: %d passed'):format(passed))
