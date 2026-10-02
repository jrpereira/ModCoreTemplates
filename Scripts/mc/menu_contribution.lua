-- Describe generated MCT pages in ModCoreSettings menu-contribution terms.
local M = {id='ModCoreTemplates'}

local function folder(path)
    return assert(path:gsub('[/\\]+$', ''):match('([^/\\]+)$'), 'invalid folder path: ' .. path)
end

function M.build(menu, root)
    assert(type(root) == 'string' and root ~= '', 'MCT root required')
    root = root:gsub('[/\\]+$', '')
    local showAggregate = #menu.aggregate.rows > 0
    for _, page in ipairs(menu.pages) do
        if page.category then showAggregate = true end
    end
    -- The aggregate takes the place of the menu entry for MCT's own folder.
    local aggregate = {id=M.id, name='ModCore Templates', author='ModCoreTemplates',
        version='0.0.20', attach=folder(root), visible=showAggregate}
    if #menu.aggregate.rows > 0 then
        aggregate.manifest, aggregate.configDirectory = menu.aggregate.manifest, root
    end
    local pages = {aggregate}
    for _, page in ipairs(menu.pages) do
        if page.category then
            pages[#pages + 1] = {id=page.id, name=page.name, author='ModCoreTemplates',
                version='0.0.20', description='Templates and settings for ' .. page.name .. '.',
                manifest=page.manifest, configDirectory=root, under=M.id}
        end
    end
    for _, page in ipairs(menu.pages) do
        if page.module then
            pages[#pages + 1] = {id=page.id, name=page.name,
                author=page.author or 'ModCoreTemplates', version=page.version or '0.0.20',
                description='Templates and settings for ' .. page.name .. '.',
                manifest=page.manifest, configDirectory=page.moduleRoot or root,
                attach=page.moduleRoot and folder(page.moduleRoot) or nil, group='module'}
        end
    end
    return {pages=pages}
end

return M
