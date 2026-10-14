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
    -- The Templates list fills ModCore Settings' Templates tab. Its hooks read the list MCT
    -- writes on each commit, so the active marks follow selections; the rows name the
    -- list's rows, which hold for the session.
    local hooks = root .. '/Scripts/mct_templates_page.lua'
    local listed = {}
    -- The same file MCT's own Scripts load, run here only to name the rows.
    for _, field in ipairs(require('mct_templates_page').menu({page=M.id, directory=root}).fields) do
        listed[#listed + 1] = field.id
    end
    local description = 'Every loaded template, by module and category, with the active ones marked.'
    -- The aggregate takes the place of the menu entry for MCT's own folder. With no rows of
    -- its own it is the list while category pages need it as their parent; otherwise it
    -- links to the Templates tab, so MCT keeps its entry in the mod list.
    local aggregate = {id=M.id, name='ModCore Templates', author='ModCoreTemplates',
        version=version, attach=folder(root)}
    local pages, list = {aggregate}, aggregate
    if #menu.aggregate.rows > 0 then
        aggregate.menu, aggregate.configDirectory = menu.aggregate.menu, root
        list = {id=M.id .. '.templates', name='Templates', author='ModCoreTemplates', version=version,
            configDirectory=root, visible=false, under=M.id}
    elseif showAggregate then
        aggregate.configDirectory = root
    else
        aggregate.link = 'settings:templates'
        -- Shown on its own, named as MCT, only when ModCore Settings has no Templates tab.
        list = {id=M.id .. '.templates', name='ModCore Templates', author='ModCoreTemplates',
            version=version, configDirectory=root, visible=false}
    end
    list.hooks, list.description = hooks, description
    -- Pages placed under the aggregate only while it is listed.
    local parent = showAggregate and M.id or nil
    for _, page in ipairs(menu.pages) do
        if page.category then
            pages[#pages + 1] = {id=page.id, name=page.name, author='ModCoreTemplates',
                version=version, description='Templates and settings for ' .. page.name .. '.',
                menu=page.menu, configDirectory=root, under=M.id}
        end
    end
    -- A slot page stays hidden; its rows appear in the slot, edited and stored here.
    -- ModCoreSettings shows it (under the aggregate, when listed) when no row finds its slot.
    local rows = {}
    for first = 1, #listed, ROW_SETTINGS do
        rows[#rows + 1] = {page=list.id, slot='settings:templates',
            settings={table.unpack(listed, first, math.min(first + ROW_SETTINGS - 1, #listed))}}
    end
    for _, page in ipairs(menu.pages) do
        if page.slot then
            pages[#pages + 1] = {id=page.id, name=page.name, author='ModCoreTemplates',
                version=version, description='Templates and settings for ' .. page.name .. '.',
                menu=page.menu, configDirectory=root, visible=false, under=parent}
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
    if list ~= aggregate then pages[#pages + 1] = list end
    return {pages=pages, rows=rows}
end

return M
