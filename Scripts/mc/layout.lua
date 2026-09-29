-- Installed mod layout. Only DMM's discovery manifest must remain at mod root.
local M = {configFile='Scripts/cache/config.ini'}
function M.paths(root)
    assert(type(root) == 'string' and root ~= '', 'mod root required')
    root = root:gsub('[/\\]+$', '')
    return {root=root, categories=root .. '/Scripts/categories',
        cache=root .. '/Scripts/cache', config=root .. '/' .. M.configFile,
        catalog=root .. '/Scripts/cache/identity-catalog.lua', pages=root .. '/Scripts/cache/menu-pages.lua',
        manifest=root .. '/mod_settings.ini'}
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
