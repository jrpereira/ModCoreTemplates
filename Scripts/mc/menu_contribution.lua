-- Describe generated MCT pages in ModCoreSettings menu-contribution terms. Pages carry
-- menu data; ModCoreSettings builds them, and names, describes and classifies the mods
-- they attach to.
local Layout = require('mc.layout')
local M = {id='ModCoreTemplates'}
-- ModCoreSettings accepts at most this many settings per slot row entry.
local ROW_SETTINGS = 32

local function folder(path)
    return assert(path:gsub('[/\\]+$', ''):match('([^/\\]+)$'), 'invalid folder path: ' .. path)
end

function M.build(menu, root)
    assert(type(root) == 'string' and root ~= '', 'MCT root required')
    root = root:gsub('[/\\]+$', '')
    -- MCT's own pages carry the release from VERSION.
    local version = Layout.version(root)
    local showAggregate = #menu.aggregate.rows > 0
    for _, page in ipairs(menu.pages) do
        if page.category then showAggregate = true end
    end
    -- The aggregate takes the place of the menu entry for MCT's own folder. With no rows of
    -- its own it is the Templates page: hooks list every loaded template by module.
    local aggregate = {id=M.id, name='ModCore Templates', author='ModCoreTemplates',
        version=version, attach=folder(root), configDirectory=root}
    if #menu.aggregate.rows > 0 then aggregate.menu, aggregate.visible = menu.aggregate.menu, showAggregate
    else
        aggregate.hooks = root .. '/Scripts/mct_templates_page.lua'
        aggregate.description = 'Every loaded template, by module, with the active ones marked.'
    end
    local pages = {aggregate}
    for _, page in ipairs(menu.pages) do
        if page.category then
            pages[#pages + 1] = {id=page.id, name=page.name, author='ModCoreTemplates',
                version=version, description='Templates and settings for ' .. page.name .. '.',
                menu=page.menu, configDirectory=root, under=M.id}
        end
    end
    -- A slot page stays hidden; its rows appear in the slot, edited and stored here.
    -- ModCoreSettings shows it under the aggregate when no row finds its slot.
    local rows = {}
    for _, page in ipairs(menu.pages) do
        if page.slot then
            pages[#pages + 1] = {id=page.id, name=page.name, author='ModCoreTemplates',
                version=version, description='Templates and settings for ' .. page.name .. '.',
                menu=page.menu, configDirectory=root, visible=false, under=M.id}
            local settings = {}
            for _, row in ipairs(page.rows) do
                settings[#settings + 1] = row.id
                if #settings == ROW_SETTINGS then
                    rows[#rows + 1] = {page=page.id, slot=page.slot, settings=settings}
                    settings = {}
                end
            end
            if #settings > 0 then rows[#rows + 1] = {page=page.id, slot=page.slot, settings=settings} end
        end
    end
    -- A module's templates are its settings: the page attaches to the module's folder, which
    -- gives it the module's name, author, version and icon.
    for _, page in ipairs(menu.pages) do
        if page.module then
            pages[#pages + 1] = {id=page.id, name=page.name,
                description='Templates and settings for ' .. page.name .. '.',
                menu=page.menu, configDirectory=page.moduleRoot or root,
                attach=page.moduleRoot and folder(page.moduleRoot) or nil}
        end
    end
    -- A module whose settings all moved to a slot keeps its page; it edits the slot's
    -- rows in the central config and links to the slot.
    for _, page in ipairs(menu.pages) do
        if page.merged then
            pages[#pages + 1] = {id=page.id, name=page.name,
                description='Templates and settings for ' .. page.name .. '.',
                menu=page.menu, configDirectory=root, attach=folder(page.moduleRoot)}
        end
    end
    return {pages=pages, rows=#rows > 0 and rows or nil}
end

return M
