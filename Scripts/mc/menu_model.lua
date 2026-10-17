-- Adapt menu declarations to runtime value-only settings.
local U = require('mc.util')
local Provider = require('mc.provider_settings')
local Runtime = require('mc.runtime')
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
        assert(type(definition.id) == 'string' and not categories[definition.id], 'duplicate/invalid category')
        assert(definition.uniqueBy == nil, definition.id .. ': uniqueBy belongs on templates, not categories')
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
            assert(type(slot) == 'table', definition.id .. '.slot must be a table')
            for key in pairs(slot) do
                assert(key == 'provider' or key == 'slot', definition.id .. '.slot: unknown field ' .. tostring(key))
            end
            assert(type(slot.provider) == 'string' and #slot.provider <= 128
                and slot.provider:match('^[%w_.-]+$'), definition.id .. '.slot.provider is invalid')
            assert(type(slot.slot) == 'string' and #slot.slot <= 64 and slot.slot:match('^[%w_]+$'),
                definition.id .. '.slot.slot is invalid')
            slot = slot.provider .. ':' .. slot.slot
        end
        categories[definition.id] = {id=definition.id, menu=declaration, runtimeSettings=values,
            slot=slot}
        names[#names + 1] = definition.id
    end
    table.sort(names)
    local registry = {templates={}, categories={}}
    function registry.categories:list() return names end
    function registry.categories:getCategory(name) return assert(categories[name], 'unknown category') end
    for index, template in ipairs(templates) do
        local category = registry.categories:getCategory(template.category)
        category.count = (category.count or 0) + 1
        local unique = Runtime.uniqueKey(template)
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
        -- id is unique across modules and, with providerId (the module's id), names the
        -- template's settings; label is what the menu shows.
        assert(type(template.id) == 'string' and template.id:match('^%a[%w_.]*$'),
            'template.id is required: a letter, then letters, digits, _ or .')
        assert(template.label == nil or type(template.label) == 'string' and template.label ~= '',
            template.id .. ': template.label must be a non-empty string')
        assert(template.providerId == nil or type(template.providerId) == 'string'
            and template.providerId:match('^[%w_.-]+$'), template.id .. ': invalid providerId')
        template.label = template.label or template.id
        -- Preserve template identity: callbacks may close over this table.
        template.settings = values
        local metadata = {id=template.id, providerId=template.providerId, label=template.label, category=template.category,
            module=template.module, menu=declaration}
        registry.templates[#registry.templates + 1] = {id=template.id, template=metadata,
            unique=unique, priority=template.priority or Runtime.DEFAULT_PRIORITY, location=assert(locations[index], 'template source path required')}
    end
    -- A category without templates has nothing to attach, so the runtime and object
    -- source never watch its objects.
    local used = {}
    for _, runtime in ipairs(runtimeCategories) do
        if categories[runtime.id].count then used[#used + 1] = runtime end
    end
    return {registry=registry, categories=used, templates=templates}
end

return M
