-- Write a template module's settings reference, docs/SETTINGS.md, and its
-- MOD_SETTINGS.txt pointer, from the module's template declarations.
--
-- usage: lua5.4 <MCT>/tools/settings_reference.lua <module folder> [--check]
--
-- The module's templates load as MCT loads them, and its menu is generated with
-- MCT's categories, so setting keys match what the game saves. --check writes
-- nothing and fails when either file is missing or out of date.
local moduleDir, flag = arg[1], arg[2]
assert(moduleDir and (flag == nil or flag == '--check'),
    'usage: lua5.4 tools/settings_reference.lua <module folder> [--check]')
moduleDir = moduleDir:gsub('[/\\]+$', '')
local mct = (arg[0]:match('^(.*)[/\\]tools[/\\][^/\\]+$') or '.')

package.path = moduleDir .. '/Scripts/?.lua;' .. mct .. '/Scripts/?.lua;' .. mct .. '/Scripts/vendor/?.lua;'
    .. package.path
-- Templates keep objects as UE4SSLuaEventBridge weak handles; loading needs only the test double.
dofile(mct .. '/tests/support/lifetimes.lua').install()
local Defaults = require('mc.template_defaults')
local Metadata = require('mc.module_metadata')
local Bootstrap = require('mc.bootstrap')
local Model = require('mc.menu_model')
local Menu = require('mc.menu')
local Layout = require('mc.layout')
local U = require('mc.util')

local function read(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local text = file:read('a')
    file:close()
    return text
end
local function jsonString(path, name)
    local text = read(path)
    return text and text:match('"' .. name .. '"%s*:%s*"([^"]*)"')
end
local function title(value)
    return (value:gsub('_', ' '):gsub('(%a)([%w_]*)', function(a, b) return a:upper() .. b end))
end

-- Templates, in registration order.
local paths = {}
require('mc')._setTemplateRegistrar(function(path) paths[#paths + 1] = path; return true end)
dofile(moduleDir .. '/Scripts/main.lua')
local templates, locations = {}, {}
for _, path in ipairs(paths) do
    local loaded = Bootstrap.executeTemplate(path)
    for _, template in ipairs(loaded.category and {loaded} or loaded) do
        templates[#templates + 1] = Metadata.apply(Defaults.apply(template), path)
        locations[#locations + 1] = path
    end
end
assert(#templates > 0, moduleDir .. ': registers no templates')

local categories = {}
for _, name in ipairs(dofile(mct .. '/Scripts/categories/mc.lua')) do
    categories[#categories + 1] = dofile(mct .. '/Scripts/categories/' .. name)
end
local model = Model.build(categories, templates, locations)
local menu = Menu.generate(model.registry)
local rows = {}
for _, row in ipairs(menu.rows) do rows[row.id] = row end

-- Installed folder names, as the release manifests give them.
local moduleName = jsonString(moduleDir .. '/mod.json', 'name') or moduleDir:match('([^/\\]+)$')
local moduleFolder = jsonString(moduleDir .. '/release-manifest.json', 'module') or moduleDir:match('([^/\\]+)$')
local mctFolder = jsonString(mct .. '/release-manifest.json', 'module') or '3_ModCore_Templates'

local function cell(value)
    return (tostring(value):gsub('|', '\\|'):gsub('\n', ' '))
end
local function choiceLabel(row, value)
    for _, choice in ipairs(row.choices or {}) do
        if choice.value == value then return choice.label end
    end
    return tostring(value)
end
local function options(row)
    if row.range then
        local suffix = row.range.suffix or ''
        return ('%d%s to %d%s, in steps of %d'):format(row.range.min, suffix, row.range.max, suffix, row.range.step)
    end
    local out = {}
    for _, choice in ipairs(row.choices) do out[#out + 1] = ('%s (`%d`)'):format(choice.label, choice.value) end
    return table.concat(out, ', ')
end
local function default(row)
    if row.range then return tostring(row.default) .. (row.range.suffix or '') end
    return choiceLabel(row, row.default)
end
local function either(list)
    if #list == 1 then return list[1] end
    return table.concat(list, ', ', 1, #list - 1) .. ' or ' .. list[#list]
end
-- A row's own conditions, in words; the template picker and Enabled toggle are left out.
local function notes(row, owner)
    local out = {}
    local visible = row.visible
    if visible and visible.field and visible.field ~= owner then
        local source = assert(rows[visible.field], row.id .. ': unknown condition source')
        local labels = {}
        for _, value in ipairs(visible.values) do labels[#labels + 1] = choiceLabel(source, value) end
        out[#out + 1] = ('Shown when %s is %s.'):format(source.label, either(labels))
    end
    if visible and visible.playerExists ~= nil then
        out[#out + 1] = visible.playerExists and 'Shown in game.' or 'Shown before a game is loaded.'
    end
    if row.relabel then
        local source = rows[row.relabel.field]
        local values = {}
        for value, text in pairs(row.relabel.values) do
            local list = {}
            for _, each in ipairs(type(value) == 'table' and value or {value}) do list[#list + 1] = each end
            table.sort(list)
            local labels = {}
            for i, each in ipairs(list) do labels[i] = choiceLabel(source, each) end
            values[#values + 1] = {list[1], text, either(labels)}
        end
        table.sort(values, function(a, b) return a[1] < b[1] end)
        for _, entry in ipairs(values) do
            out[#out + 1] = ('Named %s when %s is %s.'):format(entry[2], source.label, entry[3])
        end
    end
    return table.concat(out, ' ')
end

local lines = {}
local function add(text) lines[#lines + 1] = text or '' end

add('<!-- Generated by ModCore Templates (tools/settings_reference.lua) from this module\'s')
add('     template declarations. Edit the templates, then regenerate; do not edit this file. -->')
add('# ' .. moduleName .. ' settings')
add()
add(moduleName .. ' does not ship a `mod_settings.ini`. Compatibility with `mod_settings.ini` is'
    .. ' implemented by ModCore Templates.')
add()
add('Templates are reusable components. A module that uses a template gains the template\'s settings'
    .. ' and shows them as its own. When the game starts, ModCore Templates collects the settings of'
    .. ' every installed template and ModCore Settings builds the menu pages from them, so the pages'
    .. ' always match what is installed.')
add()
add('Change these settings in the mod menu and press Apply. Each template below names the'
    .. ' `config.ini` that keeps its values, in the `[Templates]` section, with the keys and numbers'
    .. ' listed. A saved value that is not valid falls back to its default.')
add()
add('## Templates in this module')

for _, template in ipairs(templates) do
    local category = model.registry.categories:getCategory(template.category)
    local categoryName = title(template.category:gsub('%.', ' ')):gsub('^Npc ', 'NPC ')
    local definition
    for _, candidate in ipairs(menu.definitions[template.category] or {}) do
        if candidate.id == U.identity(template) then definition = candidate end
    end
    assert(definition, template.name .. ': no generated settings')
    local selector = menu.selectors[template.category] and menu.selectors[template.category].id
    local owner = selector
    for _, entry in ipairs(menu.multiSelectors[template.category] or {}) do
        if entry.definition.id == definition.id then owner = entry.id end
    end
    add()
    add('### ' .. template.name)
    add()
    if template.description then add(template.description); add() end
    local where
    local config = '`' .. moduleFolder .. '/config.ini`'
    if category.slot then
        local host, slot = category.slot:match('^([^:]+):(.+)$')
        where = ('in the %s page\'s %s section, and on this module\'s page'):format(title(host), title(slot))
        config = '`' .. mctFolder .. '/' .. Layout.configFile .. '`'
    elseif template.menuTarget == 'templates' then
        where = ('on the %s page, under ModCore Templates'):format(categoryName)
        config = '`' .. mctFolder .. '/' .. Layout.configFile .. '`'
    else
        where = 'on this module\'s page'
    end
    add(('- **Category:** %s. The settings appear %s.'):format(categoryName, where))
    if selector then
        add(('- **Turn on:** choose %s in the %s template picker (`%s`). Only one template of this'
            .. ' category is active at a time. The picker\'s numbers depend on which templates are'
            .. ' installed, so choose it in the menu.'):format(template.name, categoryName, selector))
    else
        add(('- **Turn on:** set Enabled (`%s`) to Yes (`1`).'):format(
            assert(owner, template.name .. ': no Enabled toggle')))
    end
    add('- **Saved in:** ' .. config .. ', section `[Templates]`.')

    -- Sections in declaration order: variations first, then the menu's groups.
    local sections = {}
    local variationNames = {}
    for name in pairs(template.variations or {}) do variationNames[#variationNames + 1] = name end
    table.sort(variationNames)
    if #variationNames > 0 then
        local section = {label = 'Variations', fields = {}}
        for _, name in ipairs(variationNames) do section.fields[#section.fields + 1] = title(name) end
        sections[#sections + 1] = section
    end
    local loose
    for _, item in ipairs(template.menu or {}) do
        if item.fields then
            local section = {label = item.label or item.id, fields = {}}
            if item.variation then
                local parts = {}
                for name, value in pairs(item.variation) do
                    local row = rows[assert(definition.settings[title(name)], name .. ': no variation setting')]
                    parts[#parts + 1] = ('%s is %s'):format(row.label, choiceLabel(row, value))
                end
                table.sort(parts)
                section.when = 'Shown when ' .. table.concat(parts, ' and ') .. '.'
            end
            for _, field in ipairs(item.fields) do
                local id = field.id:sub(1, 1) == '.' and item.id .. field.id:sub(2) or field.id
                if field.type ~= 'navigation' then section.fields[#section.fields + 1] = id end
            end
            sections[#sections + 1] = section
            loose = nil
        elseif item.type ~= 'navigation' then
            if not loose then loose = {fields = {}}; sections[#sections + 1] = loose end
            loose.fields[#loose.fields + 1] = item.id
        end
    end
    for _, section in ipairs(sections) do
        add()
        -- A group named after its template needs no heading of its own.
        if section.label and section.label ~= template.name then add('#### ' .. section.label); add() end
        if section.when then add(section.when); add() end
        add('| Setting | Options | Default | Key |')
        add('|---|---|---|---|')
        for _, name in ipairs(section.fields) do
            local settingId = assert(definition.settings[name], template.name .. ': no setting for ' .. name)
            local row = assert(rows[settingId], settingId .. ': no generated row')
            local label = row.label
            local note = notes(row, owner)
            if note ~= '' then label = label .. '<br>*' .. note .. '*' end
            add(('| %s | %s | %s | `%s` |'):format(cell(label), cell(options(row)), cell(default(row)), settingId))
        end
    end
end

local reference = table.concat(lines, '\n') .. '\n'
local pointer = assert(read(mct .. '/tools/MOD_SETTINGS.txt'), 'tools/MOD_SETTINGS.txt missing')
local outputs = {{moduleDir .. '/docs/SETTINGS.md', reference}, {moduleDir .. '/MOD_SETTINGS.txt', pointer}}
local stale = {}
for _, output in ipairs(outputs) do
    if read(output[1]) ~= output[2] then
        if flag == '--check' then stale[#stale + 1] = output[1]
        else
            local file = assert(io.open(output[1], 'wb'))
            file:write(output[2])
            file:close()
            print('wrote ' .. output[1])
        end
    end
end
if #stale > 0 then
    io.stderr:write('out of date; run tools/settings_reference.lua from ModCore Templates:\n  '
        .. table.concat(stale, '\n  ') .. '\n')
    os.exit(1)
end
