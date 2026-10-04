-- Adapt menu declarations to runtime value-only settings.
local U = require('mc.util')
local Provider = require('mc.provider_settings')
local M = {}
local function defaults(groups, values)
    local result = U.copy(values or {})
    for _, group in ipairs(groups) do
        for _, field in ipairs(group.fields) do
            if field.type ~= 'navigation' and result[field.id] == nil then result[field.id] = field.default end
        end
    end
    return result
end
local function overrideDefaults(declaration, values)
    for _, group in ipairs(declaration.groups or {}) do
        for _, field in ipairs(group.fields or {}) do
            if field.type ~= 'navigation' and values[field.id] ~= nil then field.default = values[field.id] end
        end
    end
end

function M.build(definitions, templates, locations)
    local categories, names, runtimeCategories = {}, {}, {}
    for _, definition in ipairs(definitions) do
        assert(type(definition.name) == 'string' and not categories[definition.name], 'duplicate/invalid category')
        assert(type(definition.settings) ~= 'table'
            or (definition.settings.fields == nil and definition.settings.groups == nil
                and definition.settings.target == nil),
            'category menu declaration belongs in category.menu')
        local declaration = U.copy(definition.menu or {})
        local values = U.copy(definition.settings or {})
        overrideDefaults(declaration, values)
        local groups, static = Provider.normalizeCategory(declaration)
        values = defaults(groups, values)
        for key, value in pairs(static) do if values[key] == nil then values[key] = value end end
        local runtime = U.copy(definition)
        runtime.settings, runtime.menu = values, declaration
        runtimeCategories[#runtimeCategories + 1] = runtime
        -- A slot names where another provider's page shows this category's menu.
        local slot = definition.slot
        if slot ~= nil then
            assert(type(slot) == 'table', definition.name .. '.slot must be a table')
            for key in pairs(slot) do
                assert(key == 'provider' or key == 'slot', definition.name .. '.slot: unknown field ' .. tostring(key))
            end
            assert(type(slot.provider) == 'string' and #slot.provider <= 128
                and slot.provider:match('^[%w_.-]+$'), definition.name .. '.slot.provider is invalid')
            assert(type(slot.slot) == 'string' and #slot.slot <= 64 and slot.slot:match('^[%w_]+$'),
                definition.name .. '.slot.slot is invalid')
            assert(definition.single == true, definition.name .. ': a slot requires a single category')
            slot = slot.provider .. ':' .. slot.slot
        end
        -- Setting ids this category no longer declares, removed once from the module
        -- configs its slot migrated from.
        local retired = definition.retired
        if retired ~= nil then
            assert(slot, definition.name .. '.retired requires a slot')
            U.array(retired, definition.name .. '.retired')
            for _, id in ipairs(retired) do
                assert(type(id) == 'string' and #id <= 128 and id:match('^MCT_[%w_]+$'),
                    definition.name .. '.retired: invalid setting id ' .. tostring(id))
            end
            retired = U.copy(retired)
        end
        categories[definition.name] = {name=definition.name, menu=declaration, runtimeSettings=values,
            single=definition.single == true, slot=slot, retired=retired}
        names[#names + 1] = definition.name
    end
    table.sort(names)
    local registry = {templates={}, categories={}}
    function registry.categories:list() return names end
    function registry.categories:getCategory(name) return assert(categories[name], 'unknown category') end
    for index, template in ipairs(templates) do
        local category = registry.categories:getCategory(template.category)
        assert(type(template.settings) ~= 'table'
            or (template.settings.fields == nil and template.settings.groups == nil
                and template.settings.target == nil),
            'template menu declaration belongs in template.menu')
        template.menuTarget = template.menuTarget or 'module'
        local declaration = Provider.template(template.menu, template.variations)
        declaration.target = template.menuTarget
        declaration.enabled = template.enabled ~= false
        local values = U.copy(template.settings or {})
        overrideDefaults(declaration, values)
        values = defaults(Provider.normalize(declaration), values)
        template.id = template.id or U.identity(template)
        template.name = template.name or template.id
        -- Preserve template identity: callbacks may close over this table.
        template.settings = values
        local metadata = {name=template.name, category=template.category,
            module=template.module, author=template.author, version=template.version,
            menu=declaration}
        registry.templates[#registry.templates + 1] = {id=template.id, template=metadata,
            single=category.single, location=assert(locations[index], 'template source path required')}
    end
    return {registry=registry, categories=runtimeCategories, templates=templates}
end

return M
