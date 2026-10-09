-- Installed mod layout. Generated state lives in Scripts/cache; menu pages are
-- published through ModCoreSettings, so nothing is generated at mod root.
local M = {configFile='Scripts/cache/config.ini'}
function M.paths(root)
    assert(type(root) == 'string' and root ~= '', 'mod root required')
    root = root:gsub('[/\\]+$', '')
    return {root=root, categories=root .. '/Scripts/categories',
        cache=root .. '/Scripts/cache', config=root .. '/' .. M.configFile,
        catalog=root .. '/Scripts/cache/identity-catalog.lua', version=root .. '/VERSION',
        templates=root .. '/Scripts/cache/templates.lua'}
end
-- The release version from VERSION at the mod root, or nil when absent or invalid.
function M.version(root)
    local file = io.open(M.paths(root).version, 'rb')
    if not file then return nil end
    local value = file:read('a'):match('^%s*(%d+%.%d+%.%d+)%s*$')
    file:close()
    return value
end
local function mkdir(path)
    local command
    if package.config:sub(1,1) == '\\' then
        -- Quoting alone does not prevent cmd.exe environment expansion.
        assert(not path:find('["%%!\r\n]'), 'unsupported directory path')
        path = path:gsub('/', '\\')
        command = 'if not exist "' .. path .. '" mkdir "' .. path .. '"'
    else
        command = "mkdir -p -- '" .. path:gsub("'", "'\\''") .. "'"
    end
    local ok = os.execute(command)
    assert(ok == true or ok == 0, 'cannot create directory: ' .. path)
end
function M.prepare(root, createDirectory)
    local paths = M.paths(root)
    createDirectory = createDirectory or mkdir
    for _, path in ipairs({paths.categories,paths.cache}) do createDirectory(path) end
    return paths
end
return M
