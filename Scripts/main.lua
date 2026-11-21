-- 3_ModCore_Templates Lua entry point.
local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local scripts = assert(source:match('^(.*)[/\\][^/\\]+$'), 'cannot locate MCT Scripts')
local root = assert(scripts:match('^(.*)[/\\]Scripts$'), 'cannot locate MCT module')
local mods = assert(root:match('^(.*)[/\\][^/\\]+$'), 'cannot locate UE4SS Mods')
-- Files shared with other modules, unchanged, keep their own module names. Searched first,
-- so a copy left in Scripts by an earlier release is never loaded instead.
package.path = scripts .. '/vendor/?.lua;' .. scripts .. '/?.lua;' .. package.path
local Registration=require('mc.registration')
Registration.install(scripts..'/mc_client.lua',mods..'/shared/mc.lua')
local registrations=Registration.publisher(assert(ModRef,'ModRef unavailable'),mods)
local log = require('mc_log').new({name='ModCoreTemplates'})
registrations:begin()
local function listedCategories()
    local names = assert(loadfile(root .. '/Scripts/categories/mc.lua'))()
    assert(type(names) == 'table', 'invalid category source list')
    local files, seen = {}, {}
    for _, entry in ipairs(names) do
        assert(type(entry)=='string' and entry:match('^[%w_-]+%.lua$'),
            'invalid category filename')
        local path=root .. '/Scripts/categories/' .. entry
        assert(not seen[path], 'duplicate category file: ' .. path)
        seen[path] = true
        files[#files+1] = path
    end
    return files
end
-- Registration is open from here: a failed start closes it again, so providers that load
-- later are refused instead of registering into a generation nobody collects.
local started, bootstrap = pcall(function()
    -- Install the public registrar before later provider mods load.
    local MC=require('mc')
    local bootstrap = require('mc.lua_startup').start({
        log = log,
        menuRoot = root,
        categoryFiles = listedCategories(),
        settingsApi = require('settings_api'),
        collectTemplates = function(reject) return registrations:collect(reject) end,
    })
    MC._setTemplateRegistrar(function(path)
        return bootstrap:registerTemplate(path)
    end)
    return bootstrap
end)
if not started then
    pcall(registrations.stop, registrations)
    pcall(log.critical, 'startup failed: ', tostring(bootstrap))
    error(bootstrap, 0)
end
return bootstrap
