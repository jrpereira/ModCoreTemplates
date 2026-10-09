local Layout = require('mc.layout')
local U = require('mc.util')
local Provider = require('mc.provider_settings')
local M = {}

-- Pages are described as ModCoreSettings menu data (see its menu_data.lua): groups and
-- fields with choices or a range, visibility and label rules, and storage. ModCoreSettings
-- turns them into menu pages.

local function text(value)
    U.text(value, 'menu text')
    assert(not value:find('[%c|;%[%]]') and not value:match('^%s') and not value:match('%s$'),
        'menu text contains unsupported separators, controls, or edge whitespace')
    assert(#value <= 4096, 'menu text too long')
    return value
end

local function key(parts)
    local out = {}
    for _, part in ipairs(parts) do part = tostring(part); out[#out + 1] = #part .. ':' .. part end
    return table.concat(out)
end

local function title(value)
    return value:gsub('_', ' '):gsub('(%a)([%w_]*)', function(a, b) return a:upper() .. b end)
end

-- A visibility rule on a picker: shown while field holds one of values.
local function rule(field, values)
    if field == nil then return nil end
    return {field=field, values=U.copy(values)}
end

-- A group's heading flag: false hides the heading, otherwise it shows.
local function hidden(heading)
    if heading == false then return false end
end

local function choices(values, labels)
    local out = {}
    for index, value in ipairs(values) do out[index] = {value=value, label=labels[index]} end
    return out
end

-- The module a template belongs to is the mod folder holding its provider file.
local function moduleRoot(location)
    local normalized = location:gsub('\\', '/'):gsub('%[%d+%]$', '')
    return normalized:match('^(.*)/Scripts/templates/[^/]+%.lua$')
        or normalized:match('^(.*)/Scripts/[^/]+%.lua$')
end
M.moduleRoot = moduleRoot

-- The returned catalog must be persisted alongside the published pages before startup.
-- Removed mappings remain reserved, preventing saved numeric choices from changing meaning.
-- options.version is the release from VERSION; pages omit their version without it.
function M.generate(registry, options)
    options = options or {}
    assert(options.version == nil or type(options.version) == 'string' and options.version:match('^%d+%.%d+%.%d+$'),
        'invalid menu version')
    local catalog = U.copy(options.catalog or {version = 1, next = 1, entries = {}})
    assert(catalog.version == 1 and type(catalog.entries) == 'table', 'invalid identity catalog')
    assert(type(catalog.next) == 'number' and catalog.next >= 1 and catalog.next % 1 == 0
        and catalog.next <= 1000000001, 'invalid catalog counter')
    local occupied = {}
    for name, value in pairs(catalog.entries) do
        assert(type(name) == 'string' and type(value) == 'number' and value >= 1
            and value % 1 == 0 and value <= 1000000000 and value < catalog.next and not occupied[value], 'invalid catalog entry')
        occupied[value] = true
    end
    local function allocate(parts)
        local name = key(parts)
        if not catalog.entries[name] then
            assert(catalog.next <= 1000000000, 'identity catalog exhausted')
            catalog.entries[name] = catalog.next
            catalog.next = catalog.next + 1
        end
        return catalog.entries[name]
    end
    local function id(parts) return 'MCT_' .. allocate(parts) end
    catalog.names = catalog.names or {}
    assert(type(catalog.names) == 'table', 'invalid named setting catalog')
    local publicIds = {}
    for key, name in pairs(catalog.names) do
        assert(type(key) == 'string' and type(name) == 'string' and name:match('^MCT_[%w_]+$')
            and not publicIds[name], 'invalid/duplicate named setting catalog entry')
        publicIds[name] = true
    end
    local function namedId(name, fallback)
        local identity = key(fallback)
        if catalog.names[identity] then return catalog.names[identity] end
        local settingId = 'MCT_' .. name
        if publicIds[settingId] then settingId = id(fallback) end
        publicIds[settingId] = true
        catalog.names[identity] = settingId
        return settingId
    end
    local function publicName(value)
        local result = tostring(value):gsub('[^%w]+', ' ')
            :gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end)
            :gsub('%s+', '')
        assert(result ~= '', 'public menu name is empty')
        return result
    end
    local rows, groups, selectors, multiSelectors = {}, {}, {}, {}
    local groupSections, groupOrder = {}, {}
    local aggregateGroups, aggregateGroupOrder = {}, {}
    local aggregateRows, pageRows, categoryLabels, currentCategory, currentOwner = {}, {}, {}, nil, nil
    local function row(fields)
        assert(#rows < 256, 'generated menu exceeds 256 settings')
        rows[#rows + 1] = fields
        fields._category = currentCategory
        fields._owner = currentOwner
        pageRows[currentCategory] = pageRows[currentCategory] or {}
        pageRows[currentCategory][#pageRows[currentCategory] + 1] = fields
        return fields.id
    end
    local function picker(settingId, label, group, list, visible, level, default)
        return row({id = settingId, label = text(label), group = group, choices = list,
            default = default == nil and list[1].value or default, visible = visible, level = level})
    end
    -- A generated group is headed by its label and shown only by its visibility rule.
    local function group(identity, label, visible, level, heading, publicId)
        local groupId = publicId and namedId(publicId, {'group', identity}) or id({'group', identity})
        if not groups[groupId] then
            groups[groupId] = true
            groupSections[groupId] = {id = groupId, label = text(label), visible = visible, level = level,
                heading = heading}
            groupOrder[#groupOrder + 1] = groupId
        end
        return groupId
    end
    local function field(settingId, source, groupId)
        local item = {id = settingId, label = source.label, group = groupId, default = source.default,
            description = source.description, level = source.level}
        if source.type == 'picker' or source.type == 'navigation' then
            item.choices = choices(source.values, source.labels)
            item.tabs = source.tab or nil
            item.action = source.type == 'navigation' or nil
            item.link = source.linkProvider
        else
            item.range = {min = source.min, max = source.max, step = source.step, suffix = source.suffix}
        end
        return item
    end
    local entries = {}; for _, entry in ipairs(registry.templates) do entries[#entries + 1] = entry end
    table.sort(entries, function(a, b) return a.id < b.id end)
    local perCategory = {}
    for _, entry in ipairs(entries) do
        local category = entry.template.category
        perCategory[category] = perCategory[category] or {}
        table.insert(perCategory[category], entry)
    end
    local decoded = {}
    local categorySettings = {}
    local textSettings = {}
    for _, category in ipairs(registry.categories:list()) do
        categoryLabels[category] = title(category:gsub('%.', ' '))
        local available = perCategory[category]
        -- Categories without templates are reserved for future providers and get no
        -- page: a None-only picker has nothing to choose.
        if available then
            currentCategory = category
            local categorySingle = available[1].single == true
            -- A slot category is shown only in its slot, through its own hidden page.
            local slot = registry.categories:getCategory(category).slot
            local slotIds = {}
            local function slotRow(visible)
                local item = rows[#rows]
                if item.action then return end
                assert(not visible or slotIds[visible.field],
                    category .. ': slot row ' .. item.id .. ' depends on a row outside the slot')
                item._slot, slotIds[item.id] = {visible = visible}, true
            end
            local aggregateCategory = not slot
            for _, entry in ipairs(available) do
                assert((entry.single == true) == categorySingle,
                    category .. ': templates disagree on single')
                if entry.template.menu.target == 'module' then aggregateCategory = false end
            end
            assert(#available <= 63, category .. ': more than 63 templates exceeds picker capacity including None')
            local selector
            local values, list, byValue = {0}, {{value = 0, label = 'None'}}, {}
            for _, entry in ipairs(available) do
                local value = allocate({'template', entry.id})
                values[#values + 1] = value
                -- Each template choice notes its module, which ModCoreSettings names.
                list[#list + 1] = {value = value, label = text(entry.template.name),
                    module = entry.template.module}
                byValue[value] = entry.id
            end
            local prefix, suffix = assert(category:match('^([^.]+)%.([^.]+)$'))
            local aggregateGroup = title(prefix)
            if not aggregateGroups[aggregateGroup] then
                aggregateGroups[aggregateGroup] = true
                aggregateGroupOrder[#aggregateGroupOrder + 1] = aggregateGroup
            end
            if categorySingle then
                local selectorName = category == 'player.quickslots' and 'Template'
                    or publicName(category) .. 'Template'
                selector = namedId(selectorName, {'selector', category})
                local isQuickslots = category == 'player.quickslots'
                picker(selector, title(suffix), aggregateGroup, list, nil, isQuickslots and 1 or nil)
                rows[#rows]._control = true
                if aggregateCategory then aggregateRows[#aggregateRows + 1] = rows[#rows] end
                if slot then slotRow() end
                selectors[category] = {id = selector, byValue = byValue}
            else
                multiSelectors[category] = {}
            end
            decoded[category] = {}
            local categoryGroups, staticSettings, staticFormats = Provider.normalizeCategory(
                registry.categories:getCategory(category).menu)
            local sharedFields, textIds = {}, {}
            categorySettings[category] = {fields=sharedFields, static=staticSettings, textIds=textIds}
            for name, default in pairs(staticSettings) do
                local settingId = namedId(publicName(category) .. publicName(name),
                    {'category_text', category, name})
                textIds[name] = settingId
                textSettings[settingId] = {default=default, format=staticFormats[name]}
            end
            -- Shared category fields show while any template is selected.
            local selected = categorySingle and rule(selector, {table.unpack(values, 2)}) or nil
            for _, providerGroup in ipairs(categoryGroups) do
                local groupId = group(key({category, 'category_provider', providerGroup.id}),
                    providerGroup.label, selected, providerGroup.level, hidden(providerGroup.heading),
                    publicName(category) .. publicName(providerGroup.id))
                for _, source in ipairs(providerGroup.fields) do
                    local settingId = namedId(publicName(category) .. publicName(source.id),
                        {'category_provider', category, source.id})
                    row(field(settingId, source, groupId))
                    rows[#rows]._control = true
                    if aggregateCategory then aggregateRows[#aggregateRows + 1] = rows[#rows] end
                    if slot then slotRow(selected) end
                    if source.type ~= 'navigation' then sharedFields[source.id] = settingId end
                end
            end
            for _, entry in ipairs(available) do
                local template, identity = entry.template, entry.id
                currentOwner = identity
                local value = allocate({'template', identity})
                local templateScope
                if not categorySingle then templateScope = publicName(template.name) end
                local scopePrefix = templateScope and templateScope .. '_' or ''
                local definition = {id=entry.id,scope=templateScope,fields={},enabled=template.menu.enabled}
                local providerGroups = Provider.normalize(template.menu)
                definition.settings, definition.navigation = {}, {}
                local providerFieldIds = {}
                decoded[category][value] = definition
                local ownerSelector, ownerValue = selector, value
                if not categorySingle then
                    ownerSelector = namedId(templateScope .. '_Enabled', {'template_enabled', identity})
                    ownerValue = 1
                    -- The heading names the template whether or not it is enabled.
                    local headingId = group(key({identity, 'template_heading'}), template.name,
                        nil, nil, nil, templateScope)
                    picker(ownerSelector, 'Enabled', headingId, choices({0, 1}, {'No', 'Yes'}), nil, nil, 0)
                    rows[#rows]._control = true
                    if aggregateCategory then aggregateRows[#aggregateRows + 1] = rows[#rows] end
                    multiSelectors[category][#multiSelectors[category] + 1] = {
                        id=ownerSelector, value=value, definition=definition}
                end
                local owned = rule(ownerSelector, {ownerValue})
                for _, providerGroup in ipairs(providerGroups) do
                    local groupId
                    for _, source in ipairs(providerGroup.fields) do
                        local groupVisible = owned
                        if providerGroup.variationSource then
                            groupVisible = rule(assert(providerFieldIds[providerGroup.variationSource],
                                'group variation source must precede its group'), providerGroup.variationValues)
                        end
                        groupId = groupId or group(key({identity, 'provider', providerGroup.id}),
                            providerGroup.label, groupVisible, providerGroup.level,
                            hidden(providerGroup.heading),
                            scopePrefix .. publicName(providerGroup.id))
                        local settingId = namedId(scopePrefix .. publicName(source.id),
                            {'provider', identity, source.id})
                        local item = field(settingId, source, groupId)
                        if providerGroup.variationSource then item.visible = owned end
                        if source.visibleWhen then
                            local sourceId = providerFieldIds[source.visibleWhen]
                            assert(sourceId, 'provider visibility source must precede dependent field: '
                                .. source.id)
                            item.visible = rule(sourceId, source.visibleValues)
                        end
                        if source.labelWhen then
                            local labels = {}
                            for _, choice in ipairs(source.labelValues) do labels[choice] = source.labelText end
                            item.relabel = {field = assert(providerFieldIds[source.labelWhen],
                                'provider label source must precede dependent field: ' .. source.id), values = labels}
                        end
                        row(item)
                        -- Slot rows carry no group rules, so each takes the rule its group or
                        -- field would apply.
                        if slot then slotRow(source.visibleWhen and item.visible or groupVisible) end
                        providerFieldIds[source.id] = settingId
                        if source.type == 'navigation' then
                            definition.navigation[source.id] = settingId
                        else
                            definition.settings[source.id] = settingId
                        end
                    end
                end
            end
            currentOwner = nil
        end
    end
    currentCategory = nil
    local function plain(item)
        local out = {}
        for name, value in pairs(item) do
            if name:sub(1, 1) ~= '_' then out[name] = U.copy(value) end
        end
        return out
    end
    -- A page's menu data. Values are stored in configFile (the central config by default),
    -- relative to the page's config directory.
    local function providerMenu(providerName, selectedRows, aggregatePage, configFile)
        local titles = 0
        for _, item in ipairs(selectedRows) do
            if item.level == 1 then titles = titles + 1 end
        end
        assert(titles <= 1, providerName .. ': only one heading picker per page')
        local used = {}
        for _, item in ipairs(selectedRows) do used[item.group] = true end
        local menu = {storage = {file = configFile or Layout.configFile, section = 'Templates'},
            groups = {}, fields = {}}
        -- Category groups head the aggregate's sections; other pages have one category.
        for _, groupId in ipairs(aggregateGroupOrder) do
            if used[groupId] then
                local heading
                if not aggregatePage then heading = false end
                menu.groups[#menu.groups + 1] = {id = groupId, heading = heading}
            end
        end
        for _, groupId in ipairs(groupOrder) do
            if used[groupId] then menu.groups[#menu.groups + 1] = U.copy(groupSections[groupId]) end
        end
        for _, item in ipairs(selectedRows) do
            local stored = plain(item)
            -- The aggregate lists several categories, so none takes the title row.
            if aggregatePage and stored.level == 1 then stored.level = 2 end
            menu.fields[#menu.fields + 1] = stored
        end
        return menu
    end
    local schema = {}
    for _, r in ipairs(rows) do schema[r.id] = r end
    local function makeDecoder(requiredRows, includedCategories, owned)
      return function(values)
        assert(type(values) == 'table', 'Apply values must be a table')
        local effective = {}
        for settingId, r in pairs(schema) do effective[settingId] = r.default end
        for _, r in ipairs(requiredRows) do
            local settingId = r.id
            local value = values[settingId]
            if value == nil and r.action then value = r.default end
            assert(type(value) == 'number' and value == value, 'missing/invalid setting ' .. settingId)
            assert(M.accepts(r, value), (r.range and 'invalid integer ' or 'invalid choice ') .. settingId)
            effective[settingId] = value
        end
        local result = {}
        local function readSelection(definition, category)
            local selection = {settings = {}}
            if not definition then return selection end
            selection.id = definition.id
            local config = selection.settings
            local shared = categorySettings[category]
            if shared then
                for name, default in pairs(shared.static) do
                    local supplied = values[shared.textIds[name]]
                    config[name] = supplied == nil and default or supplied
                end
                for name, settingId in pairs(shared.fields) do
                    config[name] = effective[settingId]
                end
                Provider.validateCategory(registry.categories:getCategory(category).menu, config)
            end
            if definition.settings then
                for name, settingId in pairs(definition.settings) do
                    config[name] = effective[settingId]
                end
            end
            return selection
        end
        for category, selector in pairs(selectors) do
          if not includedCategories or includedCategories[category] then
            local definition = decoded[category][effective[selector.id]]
            if not owned or not definition or owned[definition.id] then
                result[category] = readSelection(definition, category)
            end
          end
        end
        for category, templates in pairs(multiSelectors) do
          if not includedCategories or includedCategories[category] then
            local selections = {}
            if owned then selections._partial, selections._known = true, {} end
            for _, item in ipairs(templates) do
                if not owned or owned[item.definition.id] then
                    if owned then selections._known[item.definition.id] = true end
                if effective[item.id] == 1 then
                    selections[#selections + 1] = readSelection(item.definition, category)
                end
                end
            end
            result[category] = selections
          end
        end
        return result
      end
    end
    local aggregateId = 'ModCoreTemplates'
    local aggregateMenu = providerMenu('ModCore Templates', aggregateRows, true)
    local allCategories = {}; for category in pairs(selectors) do allCategories[category] = true end
    for category in pairs(multiSelectors) do allCategories[category] = true end
    local aggregate = {id=aggregateId, name='ModCore Templates', menu=aggregateMenu, rows=aggregateRows,
        decode=makeDecoder(aggregateRows, allCategories)}
    local pages, pageByCategory, pageByModule, providers = {}, {}, {}, {[aggregateId]=aggregate}
    local function routedRows(categories, owned)
        local selected = {}
        local category = next(categories)
        local headerSelector = category and next(categories, category) == nil
            and selectors[category] and selectors[category].id
        for _, item in ipairs(rows) do
            if categories[item._category] then
                if item._control or (item._owner and owned[item._owner]) then
                    if item.id == headerSelector then
                        local header = U.copy(item)
                        header.level = 1
                        selected[#selected + 1] = header
                    else
                        selected[#selected + 1] = item
                    end

                end
            end
        end
        local quickslotsSelector = selectors['player.quickslots']
            and selectors['player.quickslots'].id
        local otherHeader = false
        for _, item in ipairs(selected) do
            if item.level == 1 and item.id ~= quickslotsSelector then
                otherHeader = true
                break
            end
        end
        if otherHeader then
            for index, item in ipairs(selected) do
                if item.id == quickslotsSelector then
                    local selectorRow = U.copy(item)
                    selectorRow.level = nil
                    selected[index] = selectorRow
                end
            end
        end
        return selected
    end
    local categoryOwned, moduleOwned, moduleCategories, moduleRoots = {}, {}, {}, {}
    -- Modules whose templates all moved to a slot keep an entry that opens the slot.
    local slotModules = {}
    for _, entry in ipairs(entries) do
        local template = entry.template
        local parent = moduleRoot(entry.location)
        local slot = registry.categories:getCategory(template.category).slot
        if slot then
            if template.menu.target ~= 'templates' and parent then
                local module = parent:match('([^/]+)$')
                slotModules[module] = slotModules[module] or {root=parent, slot=slot, owned={}, categories={}}
                slotModules[module].owned[entry.id] = true
                slotModules[module].categories[template.category] = true
            end
        elseif template.menu.target == 'templates' then
            categoryOwned[template.category] = categoryOwned[template.category] or {}
            categoryOwned[template.category][entry.id] = true
        else
            local module = parent and parent:match('([^/]+)$') or template.module
            assert(module and module ~= '', entry.location
                .. ': target=module requires a <Module>/Scripts/<file>.lua registration path')
            moduleOwned[module], moduleCategories[module] = moduleOwned[module] or {}, moduleCategories[module] or {}
            moduleRoots[module] = parent
            moduleOwned[module][entry.id], moduleCategories[module][template.category] = true, true
        end
    end
    for _, category in ipairs(registry.categories:list()) do
        if categoryOwned[category] then
            local providerId = aggregateId .. '.' .. category
            local included = {[category]=true}
            local selectedRows = routedRows(included, categoryOwned[category])
            local page = {id=providerId, name=categoryLabels[category], category=category,
                rows=selectedRows, menu=providerMenu(categoryLabels[category], selectedRows, false)}
            page.decode = makeDecoder(page.rows, included)
            pages[#pages + 1], pageByCategory[category], providers[providerId] = page, page, page
        end
    end
    local pageBySlot = {}
    for _, category in ipairs(registry.categories:list()) do
        local slot = registry.categories:getCategory(category).slot
        if slot and perCategory[category] then
            local providerId = aggregateId .. '.slot.' .. category
            local selectedRows = {}
            for _, item in ipairs(rows) do
                if item._category == category and item._slot then selectedRows[#selectedRows + 1] = item end
            end
            local menu = {storage = {file = Layout.configFile, section = 'Templates'},
                groups = {{id = 'Slot'}}, fields = {}}
            for _, item in ipairs(selectedRows) do
                local stored = plain(item)
                stored.group, stored.level = 'Slot', nil
                stored.visible = U.copy(item._slot.visible)
                menu.fields[#menu.fields + 1] = stored
            end
            local page = {id=providerId, name=categoryLabels[category], slot=slot,
                rows=selectedRows, menu=menu}
            page.decode = makeDecoder(page.rows, {[category]=true})
            pages[#pages + 1], pageBySlot[category], providers[providerId] = page, page, page
        end
    end
    local moduleNames = {}; for module in pairs(moduleOwned) do moduleNames[#moduleNames + 1] = module end
    table.sort(moduleNames)
    for _, module in ipairs(moduleNames) do
        local providerId = aggregateId .. '.module.' .. publicName(module)
        local selectedRows = routedRows(moduleCategories[module], moduleOwned[module])
        -- A module outside a mod folder keeps its settings in the central config.
        local root = moduleRoots[module]
        local page = {id=providerId, name=module, module=module, moduleRoot=root,
            configPath=root and root .. '/config.ini' or nil, rows=selectedRows,
            menu=providerMenu(module, selectedRows, false, root and 'config.ini' or nil)}
        page.decode = makeDecoder(page.rows, moduleCategories[module], moduleOwned[module])
        pages[#pages + 1], pageByModule[module], providers[providerId] = page, page, page
    end
    -- A module whose templates all moved to a slot keeps its own page over the slot's
    -- rows and central storage, headed by a notice that opens the slot.
    local mergedNames = {}
    for module in pairs(slotModules) do
        if not moduleOwned[module] then mergedNames[#mergedNames + 1] = module end
    end
    table.sort(mergedNames)
    for _, module in ipairs(mergedNames) do
        local entry = slotModules[module]
        local providerId = aggregateId .. '.module.' .. publicName(module)
        -- The notice is the page's only link: navigation rows stay out, as in the slot.
        -- The template picker sits below the notice as in the slot, not in the title row.
        local selectedRows = {}
        for _, item in ipairs(routedRows(entry.categories, entry.owned)) do
            if item.level == 1 then
                item = U.copy(item)
                item.level = nil
            end
            if not item.action then selectedRows[#selectedRows + 1] = item end
        end
        local host = title(entry.slot:match('^[^:]+'))
        table.insert(selectedRows, 1, {id='MCT_MergedNotice', group=selectedRows[1].group,
            label='These settings have been merged into ' .. host .. ' and can also be edited there',
            choices={{value=0, label=host}}, default=0, action=true, tabs=true, link=entry.slot, level=5})
        local page = {id=providerId, name=module, merged=entry.slot, moduleRoot=entry.root, rows=selectedRows,
            menu=providerMenu(module, selectedRows, false)}
        page.decode = makeDecoder(page.rows, entry.categories, entry.owned)
        pages[#pages + 1], pageByModule[module], providers[providerId] = page, page, page
    end
    local decodeAll = makeDecoder(rows, allCategories)
    local function decodeState(values)
        local decodedSelections = decodeAll(values) -- validate the complete committed snapshot
        local state = {}
        for category in pairs(allCategories) do
            local shared = categorySettings[category]
            local categoryValues = {}
            for name, default in pairs(shared.static) do
                local supplied = values[shared.textIds[name]]
                categoryValues[name] = supplied == nil and default or supplied
            end
            for name, settingId in pairs(shared.fields) do categoryValues[name] = values[settingId] end
            Provider.validateCategory(registry.categories:getCategory(category).menu, categoryValues)
            local effectiveCategory = U.copy(registry.categories:getCategory(category).runtimeSettings or {})
            for name, value in pairs(categoryValues) do effectiveCategory[name] = value end
            local selections = {}
            local function selected(selection)
                if not selection.id then return end
                local definition
                for _, candidate in pairs(decoded[category]) do
                    if candidate.id == selection.id then definition = candidate; break end
                end
                if not definition.enabled then return end
                local own = {}
                for name, settingId in pairs(definition.settings) do own[name] = values[settingId] end
                selections[selection.id] = own
            end
            local selectionsForCategory = decodedSelections[category]
            if selectors[category] then selected(selectionsForCategory)
            else for _, selection in ipairs(selectionsForCategory) do selected(selection) end end
            state[category] = {settings=effectiveCategory, selections=selections}
        end
        return state
    end
    return {menu = aggregateMenu, catalog = catalog,
        rows = rows, selectors = selectors, multiSelectors=multiSelectors, definitions = decoded,
        textSettings = textSettings, decodeState=decodeState, categorySettings=categorySettings,
        decode = decodeAll, aggregate=aggregate, pages=pages,
        pageByCategory=pageByCategory, pageByModule=pageByModule, pageBySlot=pageBySlot, providers=providers}
end

-- Whether a row accepts a value: one of its choices, or a whole number in its range.
function M.accepts(r, value)
    if type(value) ~= 'number' or value ~= value then return false end
    if r.range then return value >= r.range.min and value <= r.range.max and value % 1 == 0 end
    for _, choice in ipairs(r.choices) do if choice.value == value then return true end end
    return false
end

return M
