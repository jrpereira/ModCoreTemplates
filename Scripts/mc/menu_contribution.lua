-- Describe generated MCT pages in ModCoreSettings menu-contribution terms.
local M = {id='ModCoreTemplates'}
-- ModCoreSettings accepts at most this many settings per slot row entry.
local ROW_SETTINGS = 32

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
    -- A slot page stays hidden; its rows appear in the slot, edited and stored here.
    -- ModCoreSettings shows it under the aggregate when no row finds its slot.
    local rows = {}
    for _, page in ipairs(menu.pages) do
        if page.slot then
            pages[#pages + 1] = {id=page.id, name=page.name, author='ModCoreTemplates',
                version='0.0.20', description='Templates and settings for ' .. page.name .. '.',
                manifest=page.manifest, configDirectory=root, visible=false, under=M.id}
            local settings = {}
            for _, row in ipairs(page.rows) do
                settings[#settings + 1] = row.Id
                if #settings == ROW_SETTINGS then
                    rows[#rows + 1] = {page=page.id, slot=page.slot, settings=settings}
                    settings = {}
                end
            end
            if #settings > 0 then rows[#rows + 1] = {page=page.id, slot=page.slot, settings=settings} end
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
    -- A module whose settings all moved to a slot keeps its entry, which opens the slot.
    for _, page in ipairs(menu.pages) do
        if page.link then
            pages[#pages + 1] = {id=page.id, name=page.name,
                author=page.author or 'ModCoreTemplates', version=page.version or '0.0.20',
                description='Opens the settings for ' .. page.name .. '.',
                attach=folder(page.moduleRoot), group='module', link=page.link}
        end
    end
    return {pages=pages, rows=#rows > 0 and rows or nil}
end

return M
