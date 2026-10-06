local Layout = require('mc.layout')
local U = require('mc.util')
local Provider = require('mc.provider_settings')
local M = {}

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

-- The returned catalog must be persisted alongside the manifest before startup.
-- Removed mappings remain reserved, preventing saved numeric choices from changing meaning.
function M.generate(registry, options)
    options = options or {}
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
    local lines, rows, groups, bindings, selectors, multiSelectors, warnings = {}, {}, {}, {}, {}, {}, {}
    local groupSections, groupOrder = {}, {}
    local aggregateGroups, aggregateGroupOrder = {}, {}
    local aggregateRows, pageRows, categoryLabels, currentCategory, currentOwner = {}, {}, {}, nil, nil
    local function emit(section, fields)
        lines[#lines + 1] = '[' .. section .. ']'
        local names = {}; for name, value in pairs(fields) do
            if value ~= nil and name:sub(1, 1) ~= '_' then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do lines[#lines + 1] = name .. '=' .. tostring(fields[name]) end
        lines[#lines + 1] = ''
    end
    emit('Mod', {Id = 'ModCoreTemplates', Name = 'ModCore Templates', Version = '1.0.1',
        Description = options.description and text(options.description) or nil})
    local function row(fields)
        assert(#rows < 256, 'generated menu exceeds DMM limit of 256 settings')
        if fields.mcNavigation ~= 1 then
            fields.ConfigFile, fields.ConfigSection, fields.ConfigKey = Layout.configFile, 'Templates', fields.Id
        end
        rows[#rows + 1] = fields
        fields._category = currentCategory
        fields._owner = currentOwner
        pageRows[currentCategory] = pageRows[currentCategory] or {}
        pageRows[currentCategory][#pageRows[currentCategory] + 1] = fields
        emit('Setting.' .. fields.Id, fields)
        return fields.Id
    end
    local function picker(settingId, label, group, values, labels, source, visible, level, default)
        return row({Id = settingId, Label = text(label), Group = group, Type = 'picker',
            PresetValues = table.concat(values, '|'), PresetLabels = table.concat(labels, '|'),
            Default = default == nil and values[1] or default,
            VisibleWhen = source, VisibleValues = visible,
            mcHeading = level == 1 and true or nil,
            mcLevel = level ~= 1 and level or nil})
    end
    local function group(identity, label, selector, selected, source, visible, level, heading, publicId,
        labelValues)
        local groupId = publicId and namedId(publicId, {'group', identity}) or id({'group', identity})
        if not groups[groupId] then
            groups[groupId] = true
            local labels = {}
            if labelValues then
                for index = 2, #labelValues do
                    labels[#labels + 1] = tostring(labelValues[index]) .. ':' .. text(label)
                end
            else
                labels[1] = tostring(selected) .. ':' .. text(label)
            end
            local fields = {VisibleWhen = source, VisibleValues = visible,
                mcLevel = level, mcHeading = heading, mcLabelWhen = selector,
                mcLabels = table.concat(labels, ';')}
            groupSections[groupId] = fields
            groupOrder[#groupOrder + 1] = groupId
            emit('Category.' .. groupId, fields)
        end
        return groupId
    end
    local entries = {}; for _, entry in ipairs(registry.templates) do entries[#entries + 1] = entry end
    table.sort(entries, function(a, b) return a.id < b.id end)
    local perCategory = {}
    for _, entry in ipairs(entries) do
        local category = entry.template.category
        perCategory[category] = perCategory[category] or {}
        table.insert(perCategory[category], entry)
    end
    local function storageIdentity(entry) return entry.id end
    local decoded = {}
    local categorySettings = {}
    local textSettings = {}
    for _, category in ipairs(registry.categories:list()) do
        local categoryLabel = (options.categoryLabels or {})[category]
            or title(category:gsub('%.', ' '))
        categoryLabels[category] = categoryLabel
        local available = perCategory[category]
        if not available then
            warnings[#warnings + 1] = category .. ': empty category omitted; DMM cannot render a None-only picker'
        else
            currentCategory = category
            local categorySingle = available[1].single == true
            -- A slot category is shown only in its slot, through its own hidden page.
            local slot = registry.categories:getCategory(category).slot
            local slotIds = {}
            local function slotRow(when, values, source)
                local item = rows[#rows]
                if item.mcNavigation == 1 then return end
                assert(not source or slotIds[source],
                    category .. ': slot row ' .. item.Id .. ' depends on a row outside the slot')
                item._slot, slotIds[item.Id] = {when=when, values=values}, true
            end
            local aggregateCategory = not slot
            for _, entry in ipairs(available) do
                assert((entry.single == true) == categorySingle,
                    category .. ': templates disagree on single')
                if entry.template.menu.target == 'module' then aggregateCategory = false end
            end
            assert(#available <= 63, category .. ': more than 63 templates exceeds picker capacity including None')
            local selector
            local values, labels, byValue = {0}, {'None'}, {}
            for _, entry in ipairs(available) do
                local value = allocate({'template', storageIdentity(entry)})
                values[#values + 1], labels[#labels + 1] = value, text(entry.template.name)
                byValue[value] = entry.id
            end
            local prefix, suffix = assert(category:match('^([^.]+)%.([^.]+)$'))
            local aggregateGroup = title(prefix)
            if not aggregateGroups[aggregateGroup] then
                aggregateGroups[aggregateGroup] = true
                aggregateGroupOrder[#aggregateGroupOrder + 1] = aggregateGroup
                emit('Category.' .. aggregateGroup, {})
            end
            if categorySingle then
                local selectorName = category == 'player.quickslots' and 'Template'
                    or publicName(category) .. 'Template'
                selector = namedId(selectorName, {'selector', category})
                local isQuickslots = category == 'player.quickslots'
                picker(selector, title(suffix), aggregateGroup, values, labels, nil, nil,
                    isQuickslots and 1 or nil)
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
            for field, default in pairs(staticSettings) do
                local settingId = namedId(publicName(category) .. publicName(field),
                    {'category_text', category, field})
                textIds[field] = settingId
                textSettings[settingId] = {default=default, format=staticFormats[field]}
            end
            local visibleValues = categorySingle and table.concat(values, '|', 2) or nil
            for _, providerGroup in ipairs(categoryGroups) do
                local groupId = group(key({category, 'category_provider', providerGroup.id}),
                    providerGroup.label, selector, values[2], selector, visibleValues,
                    providerGroup.level, providerGroup.heading == false and 0 or nil,
                    publicName(category) .. publicName(providerGroup.id), categorySingle and values or nil)
                for _, field in ipairs(providerGroup.fields) do
                    local settingId = namedId(publicName(category) .. publicName(field.id),
                        {'category_provider', category, field.id})
                    local metadata = {Id=settingId, Label=field.label, Group=groupId,
                        Type=field.type == 'navigation' and 'picker' or field.type,
                        Default=field.default, Description=field.description,
                        mcHeading=field.level==1 and true or nil,
                        mcLevel=field.level~=1 and field.level or nil}
                    if field.type == 'picker' or field.type == 'navigation' then
                        metadata.PresetValues = table.concat(field.values, '|')
                        metadata.PresetLabels = table.concat(field.labels, '|')
                        metadata.mcType = field.tab and 'tab' or nil
                        metadata.mcNavigation = field.type == 'navigation' and 1 or nil
                        metadata.tabNavigation = field.tabNavigation
                    else
                        metadata.Minimum, metadata.Maximum, metadata.Step = field.min, field.max, field.step
                        metadata.Suffix = field.suffix
                    end
                    row(metadata)
                    rows[#rows]._control = true
                    if aggregateCategory then aggregateRows[#aggregateRows + 1] = rows[#rows] end
                    if slot then slotRow(selector, visibleValues, selector) end
                    if field.type ~= 'navigation' then sharedFields[field.id] = settingId end
                end
            end
            for _, entry in ipairs(available) do
                local template, identity = entry.template, storageIdentity(entry)
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
                    ownerSelector = namedId('CategorySeparator_' .. templateScope,
                        {'template_toggle', identity})
                    ownerValue = 1
                    picker(ownerSelector, template.name, aggregateGroup, {0, 1}, {'No', 'Yes'},
                        nil, nil, nil, 0)
                    rows[#rows]._control = true
                    if aggregateCategory then aggregateRows[#aggregateRows + 1] = rows[#rows] end
                    multiSelectors[category][#multiSelectors[category] + 1] = {
                        id=ownerSelector, value=value, definition=definition}
                end
                local function emitProviderFields(after)
                    for _, providerGroup in ipairs(providerGroups) do
                        local groupId
                        for _, field in ipairs(providerGroup.fields) do
                            if field.after == after then
                                assert(not field.after or category == 'player.quickslots',
                                    'AccessMethod placement requires player.quickslots')
                                local groupSource, groupValues = ownerSelector, ownerValue
                                if providerGroup.variationSource then
                                    groupSource = assert(providerFieldIds[providerGroup.variationSource],
                                        'group variation source must precede its group')
                                    groupValues = table.concat(providerGroup.variationValues, '|')
                                end
                                groupId = groupId or group(key({identity, 'provider', providerGroup.id}),
                                    providerGroup.label, ownerSelector, ownerValue, groupSource, groupValues,
                                    providerGroup.level, providerGroup.heading == false and 0 or nil,
                                    scopePrefix .. publicName(providerGroup.id))
                                local settingId = namedId(scopePrefix .. publicName(field.id),
                                    {'provider', identity, field.id})
                                local metadata = {Id=settingId, Label=field.label, Group=groupId,
                                    Type=field.type == 'navigation' and 'picker' or field.type,
                                    Default=field.default, Description=field.description,
                                    mcHeading=field.level==1 and true or nil,
                                    mcLevel=field.level~=1 and field.level or nil,
                                    mcLinkPage=field.linkProvider}
                                if providerGroup.variationSource then
                                    metadata.VisibleWhen = ownerSelector
                                    metadata.VisibleValues = ownerValue
                                end
                                if field.visibleWhen then
                                    local sourceId = providerFieldIds[field.visibleWhen]
                                    assert(sourceId, 'provider visibility source must precede dependent field: '
                                        .. field.id)
                                    metadata.VisibleWhen = sourceId
                                    metadata.VisibleValues = table.concat(field.visibleValues, '|')
                                end
                                if field.labelWhen then
                                    metadata.mcLabelWhen = assert(providerFieldIds[field.labelWhen],
                                        'provider label source must precede dependent field: ' .. field.id)
                                    local labels = {}
                                    for _, value in ipairs(field.labelValues) do
                                        labels[#labels + 1] = tostring(value) .. ':' .. field.labelText
                                    end
                                    metadata.mcLabels = table.concat(labels, ';')
                                end
                                if field.type == 'picker' or field.type == 'navigation' then
                                    metadata.PresetValues = table.concat(field.values, '|')
                                    metadata.PresetLabels = table.concat(field.labels, '|')
                                    metadata.mcType = field.tab and 'tab' or nil
                                    metadata.mcNavigation = field.type == 'navigation' and 1 or nil
                                    metadata.tabNavigation = field.tabNavigation
                                else
                                    metadata.Minimum, metadata.Maximum, metadata.Step = field.min, field.max, field.step
                                    metadata.Suffix = field.suffix
                                end
                                row(metadata)
                                -- Slot rows carry no Category rules, so each takes the
                                -- condition its group or field would apply.
                                if slot then
                                    if field.visibleWhen then
                                        slotRow(metadata.VisibleWhen, metadata.VisibleValues, metadata.VisibleWhen)
                                    else
                                        slotRow(groupSource, groupValues, groupSource)
                                    end
                                end
                                providerFieldIds[field.id] = settingId
                                if field.type == 'navigation' then
                                    definition.navigation[field.id] = settingId
                                else
                                    definition.settings[field.id] = settingId
                                end
                            end
                        end
                    end
                end
                emitProviderFields(nil)
            end
            currentOwner = nil
        end
    end
    currentCategory = nil
    local function append(target, section, fields)
        target[#target + 1] = '[' .. section .. ']'
        local names = {}
        for name, value in pairs(fields) do
            if value ~= nil and name:sub(1, 1) ~= '_' then names[#names + 1] = name end
        end
        table.sort(names)
        for _, name in ipairs(names) do target[#target + 1] = name .. '=' .. tostring(fields[name]) end
        target[#target + 1] = ''
    end
    local function providerManifest(providerId, providerName, selectedRows, aggregatePage, configFile)
        local output = {}
        local headerPickers = 0
        for _, item in ipairs(selectedRows) do
            if item.mcHeading == true then headerPickers = headerPickers + 1 end
        end
        assert(headerPickers <= 1, providerName .. ': only one heading picker per page')
        append(output, 'Mod', {Id=providerId, Name=providerName, Version='1.0.1',
            Description=options.description and text(options.description) or nil})
        local usedGroups = {}
        for _, item in ipairs(selectedRows) do
            usedGroups[item.Group] = true
        end
        for _, groupId in ipairs(aggregateGroupOrder) do
            if usedGroups[groupId] then
                append(output, 'Category.' .. groupId, aggregatePage and {} or {mcHeading=0})
            end
        end
        for _, groupId in ipairs(groupOrder) do
            if usedGroups[groupId] then
                local fields = groupSections[groupId]
                append(output, 'Category.' .. groupId, fields)
            end
        end
        for _, item in ipairs(selectedRows) do
            if configFile and item.mcNavigation ~= 1 then
                local stored = U.copy(item)
                stored.ConfigFile = configFile
                append(output, 'Setting.' .. item.Id, stored)
            else
                append(output, 'Setting.' .. item.Id, item)
            end
        end
        local manifest = table.concat(output, '\n')
        assert(#manifest <= 256 * 1024, 'generated manifest exceeds 256 KiB')
        return manifest
    end
    local schema = {}
    for _, r in ipairs(rows) do schema[r.Id] = r end
    local function makeDecoder(requiredRows, includedCategories, owned)
      return function(values)
        assert(type(values) == 'table', 'Apply values must be a table')
        local effective = {}
        for settingId, r in pairs(schema) do effective[settingId] = tonumber(r.Default) end
        for _, r in ipairs(requiredRows) do
            local settingId = r.Id
            local value = values[settingId]
            if value == nil and r.mcNavigation == 1 then value = tonumber(r.Default) end
            assert(type(value) == 'number' and value == value, 'missing/invalid setting ' .. settingId)
            if r.Type == 'integer' then
                assert(value >= r.Minimum and value <= r.Maximum and value % 1 == 0,
                    (r.mcType == 'keybind' and 'invalid key ' or 'invalid integer ') .. settingId)
            else
                local found = false
                for candidate in r.PresetValues:gmatch('[^|]+') do if value == tonumber(candidate) then found = true end end
                assert(found, 'invalid choice ' .. settingId)
            end
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
                for field, default in pairs(shared.static) do
                    local supplied = values[shared.textIds[field]]
                    config[field] = supplied == nil and default or supplied
                end
                for field, settingId in pairs(shared.fields) do
                    config[field] = effective[settingId]
                end
                Provider.validateCategory(registry.categories:getCategory(category).menu, config)
            end
            if definition.settings then
                for field, settingId in pairs(definition.settings) do
                    config[field] = effective[settingId]
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
    local aggregateManifest = providerManifest(aggregateId, 'ModCore Templates', aggregateRows, true)
    local allCategories = {}; for category in pairs(selectors) do allCategories[category] = true end
    for category in pairs(multiSelectors) do allCategories[category] = true end
    local aggregate = {id=aggregateId, name='ModCore Templates', manifest=aggregateManifest, rows=aggregateRows,
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
                    if item.Id == headerSelector then
                        local header = U.copy(item)
                        header.mcHeading = true
                        header.mcLevel = nil
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
            if item.mcHeading == true and item.Id ~= quickslotsSelector then
                otherHeader = true
                break
            end
        end
        if otherHeader then
            for index, item in ipairs(selected) do
                if item.Id == quickslotsSelector then
                    local selectorRow = U.copy(item)
                    selectorRow.mcHeading = nil
                    selected[index] = selectorRow
                end
            end
        end
        return selected
    end
    local categoryOwned, moduleOwned, moduleCategories, moduleAuthors, moduleVersions, moduleRoots =
        {}, {}, {}, {}, {}, {}
    -- Module configs that held a slot category's values before it moved to its slot,
    -- and modules whose templates all moved, which keep an entry that opens the slot.
    local slotSources, slotModules = {}, {}
    for _, entry in ipairs(entries) do
        local template = entry.template
        local normalized = entry.location:gsub('\\', '/'):gsub('%[%d+%]$', '')
        local parent = normalized:match('^(.*)/Scripts/templates/[^/]+%.lua$')
            or normalized:match('^(.*)/Scripts/[^/]+%.lua$')
        local slot = registry.categories:getCategory(template.category).slot
        if slot then
            if template.menu.target ~= 'templates' and parent then
                local sources = slotSources[template.category] or {}
                slotSources[template.category], sources[parent] = sources, true
                local module = (template.module or parent:match('([^/]+)$')):gsub('^_', '')
                slotModules[module] = slotModules[module] or {root=parent, slot=slot,
                    author=template.author and text(template.author),
                    version=template.version and text(template.version), owned={}, categories={}}
                slotModules[module].owned[entry.id] = true
                slotModules[module].categories[template.category] = true
            end
        elseif template.menu.target == 'templates' then
            categoryOwned[template.category] = categoryOwned[template.category] or {}
            categoryOwned[template.category][entry.id] = true
        else
            local module = template.module or (parent and parent:match('([^/]+)$'))
            assert(module and module ~= '', entry.location
                .. ': target=module requires a <Module>/Scripts/<file>.lua registration path')
            module = module:gsub('^_', '')
            moduleOwned[module], moduleCategories[module] = moduleOwned[module] or {}, moduleCategories[module] or {}
            if parent then
                assert(not moduleRoots[module] or moduleRoots[module] == parent,
                    module .. ': templates resolve to different module roots')
                moduleRoots[module] = parent
            end
            moduleOwned[module][entry.id], moduleCategories[module][template.category] = true, true
            if template.author then
                assert(not moduleAuthors[module] or moduleAuthors[module] == template.author,
                    module .. ': templates disagree on author')
                moduleAuthors[module] = text(template.author)
            end
            if template.version then
                assert(not moduleVersions[module] or moduleVersions[module] == template.version,
                    module .. ': templates disagree on version')
                moduleVersions[module] = text(template.version)
            end
        end
    end
    for _, category in ipairs(registry.categories:list()) do
        if categoryOwned[category] then
            local providerId = aggregateId .. '.' .. category
            local included = {[category]=true}
            local selectedRows = routedRows(included, categoryOwned[category])
            local page = {id=providerId, name=categoryLabels[category], category=category,
                rows=selectedRows, manifest=providerManifest(providerId, categoryLabels[category], selectedRows, false)}
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
            local output = {}
            append(output, 'Mod', {Id=providerId, Name=categoryLabels[category], Version='1.0.1'})
            append(output, 'Category.Slot', {})
            for _, item in ipairs(selectedRows) do
                local stored = U.copy(item)
                stored.Group, stored.mcHeading, stored.mcLevel = 'Slot', nil, nil
                stored.VisibleWhen, stored.VisibleValues = item._slot.when, item._slot.values
                append(output, 'Setting.' .. item.Id, stored)
            end
            local migrate = {}
            for parent in pairs(slotSources[category] or {}) do migrate[#migrate + 1] = parent .. '/config.ini' end
            table.sort(migrate)
            local retired = registry.categories:getCategory(category).retired or {}
            for _, id in ipairs(retired) do
                for _, item in ipairs(rows) do
                    assert(item.Id ~= id, category .. ': retired setting ' .. id .. ' is still generated')
                end
            end
            local page = {id=providerId, name=categoryLabels[category], slot=slot, slotCategory=category,
                rows=selectedRows, manifest=table.concat(output, '\n'), migrate=migrate, retired=retired}
            page.decode = makeDecoder(page.rows, {[category]=true})
            pages[#pages + 1], pageBySlot[category], providers[providerId] = page, page, page
        end
    end
    local moduleNames = {}; for module in pairs(moduleOwned) do moduleNames[#moduleNames + 1] = module end
    table.sort(moduleNames)
    for _, module in ipairs(moduleNames) do
        local providerId = aggregateId .. '.module.' .. publicName(module)
        local selectedRows = routedRows(moduleCategories[module], moduleOwned[module])
        local moduleRoot = moduleRoots[module]
        local page = {id=providerId, name=module, module=module, moduleRoot=moduleRoot,
            configPath=moduleRoot and moduleRoot .. '/config.ini' or nil,
            author=moduleAuthors[module],version=moduleVersions[module],rows=selectedRows,
            manifest=providerManifest(providerId, module, selectedRows, false,
                moduleRoot and 'config.ini' or nil)}
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
        local selectedRows = {}
        for _, item in ipairs(routedRows(entry.categories, entry.owned)) do
            if item.mcNavigation ~= 1 then selectedRows[#selectedRows + 1] = item end
        end
        local host = title(entry.slot:match('^[^:]+'))
        table.insert(selectedRows, 1, {Id='MCT_MergedNotice', Group=selectedRows[1].Group,
            Label='These settings have been merged into ' .. host .. ' and can also be edited there',
            Type='picker', PresetValues='0|1', PresetLabels=host .. '|' .. host, Default=0,
            mcNavigation=1, mcType='tab', mcLinkPage=entry.slot, mcLevel=5})
        local page = {id=providerId, name=module, merged=entry.slot, moduleRoot=entry.root,
            author=entry.author, version=entry.version, rows=selectedRows,
            manifest=providerManifest(providerId, module, selectedRows, false)}
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
            for field, default in pairs(shared.static) do
                local supplied = values[shared.textIds[field]]
                categoryValues[field] = supplied == nil and default or supplied
            end
            for field, settingId in pairs(shared.fields) do categoryValues[field] = values[settingId] end
            Provider.validateCategory(registry.categories:getCategory(category).menu, categoryValues)
            local effectiveCategory = U.copy(registry.categories:getCategory(category).runtimeSettings or {})
            for field, value in pairs(categoryValues) do effectiveCategory[field] = value end
            local selections = {}
            local function selected(selection)
                if not selection.id then return end
                local definition
                for _, candidate in pairs(decoded[category]) do
                    if candidate.id == selection.id then definition = candidate; break end
                end
                if not definition.enabled then return end
                local own = {}
                for field, settingId in pairs(definition.settings) do own[field] = values[settingId] end
                selections[selection.id] = own
            end
            local selectionsForCategory = decodedSelections[category]
            if selectors[category] then selected(selectionsForCategory)
            else for _, selection in ipairs(selectionsForCategory) do selected(selection) end end
            state[category] = {settings=effectiveCategory, selections=selections}
        end
        return state
    end
    return {manifest = aggregateManifest, fullManifest = table.concat(lines, '\n'), catalog = catalog,
        rows = rows, selectors = selectors, multiSelectors=multiSelectors, definitions = decoded, warnings = warnings,
        textSettings = textSettings, decodeState=decodeState, categorySettings=categorySettings,
        decode = makeDecoder(rows, allCategories), aggregate=aggregate, pages=pages,
        pageByCategory=pageByCategory, pageByModule=pageByModule, pageBySlot=pageBySlot, providers=providers}
end

return M
