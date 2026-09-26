package.path='./Scripts/?.lua;'..package.path
local Discovery=require('mc.template_discovery')
local function file(path)
    return {__name=path:match('[^/]+$'),__absolute_path=path}
end
local function module(name,files)
    local root='C:/Game/Mods/'..name..'/Scripts/templates/'
    local listed={}
    for _,name in ipairs(files) do listed[name]=file(root..name) end
    return {__name=name,__absolute_path='C:/Game/Mods/'..name,
        __files={enabled=file('C:/Game/Mods/'..name..'/enabled.txt')},
        Scripts={__name='Scripts',templates={__name='templates',__files=listed}}}
end
local mods={__name='Mods',__absolute_path='C:/Game/Mods',
    Fangdango=module('Fangdango',{'mc.lua','main.lua','mc_minima.lua','mc_wheels.lua','mc_bars.lua'}),
    Bare=module('Bare',{'second.lua','first.lua','notes.txt'}),
    Disabled={__name='Disabled',__absolute_path='C:/Game/Mods/Disabled',
        Scripts={templates={__files={file('C:/Game/Mods/Disabled/Scripts/templates/mc.lua')}}}},
    Empty={__name='Empty',__absolute_path='C:/Game/Mods/Empty'},
}
local paths=Discovery.discover('C:\\Game\\Mods\\_ModCore_Templates',
    {Game={__name='Game',Binaries={__name='Binaries',Win64={__name='Win64',Mods=mods}}}})
assert(#paths==3)
assert(paths[1]:match('/Bare/Scripts/templates/first%.lua$'))
assert(paths[2]:match('/Bare/Scripts/templates/second%.lua$'))
assert(paths[3]:match('/Fangdango/Scripts/templates/mc%.lua$'))
local bareTree={Dawnwalker={Binaries={Win64={ue4ss={Mods={
    Fangdango={__files={enabled={__name='ENABLED.TXT'}},Scripts={templates={__files={
        file('C:/Game/Mods/Fangdango/Scripts/templates/main.lua'),
        file('C:/Game/Mods/Fangdango/Scripts/templates/mc_wheels.lua'),
    }}}},
}}}}}}
local bare=Discovery.discover('C:/Game/Mods/_ModCore_Templates',bareTree)
assert(#bare==1 and bare[1]:match('/Fangdango/Scripts/templates/main%.lua$'))
print('PASS: module template discovery and mc.lua/main.lua precedence')
