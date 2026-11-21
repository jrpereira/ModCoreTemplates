local Layout = require('mc.layout')
local U = require('mc.util')
local Provider = require('mc.provider_settings')
local From = require('menu_from')
local M = {}

-- Pages are described as ModCoreSettings menu data (see its menu_data.lua): groups and
-- fields with a type (enum, integer or range), values, widget and style, visibility and label rules, and storage. ModCoreSettings
-- turns them into menu pages.

local function text(value) return Provider.text(value, 'menu text') end

local function key(parts)
    local out = {}
    for _, part in ipairs(parts) do part = tostring(part); out[#out + 1] = #part .. ':' .. part end
    return table.concat(out)
end

local title = Provider.title

-- A visibility rule on a picker: shown while field holds one of values.
local function rule(field, values)
    if field == nil then return nil end
    return {field=field, values=U.copy(values)}
end

-- Menu-data choices; notes and sounds (optional) are keyed by value.
local function choices(values, labels, notes, sounds)
    local out = {}
    for index, value in ipairs(values) do
        out[index] = {value=value, label=labels[index], note=notes and notes[value],
            sound=sounds and sounds[value]}
    end
    return out
end

-- A visibility rule with the field's player condition (playerExists) added, or nil.
local function withPlayer(visible, player)
    if player == nil then return visible end
    local out = U.copy(visible or {})
    out.playerExists = player
    return out
end

-- The module a template belongs to is the mod folder holding its provider file.
local function moduleRoot(location)
    local normalized = location:gsub('\\', '/'):gsub('%[%d+%]$', '')
    return normalized:match('^(.*)/Scripts/[^/]+%.lua$')
end
M.moduleRoot = moduleRoot

-- Ids are derived, not stored: a template picker's choice keys are the templates' full
-- ids (keyed enum, stored as text by ModCoreSettings), and generated setting and group
-- ids are readable names. A name two templates would share fails the menu, so startup
-- rejects the later provider file.
-- options.version is the release from VERSION; pages omit their version without it.
function M.generate(registry, options)
    options = options or {}
    assert(options.version == nil or type(options.version) == 'string' and options.version:match('^%d+%.%d+%.%d+$'),
        'invalid menu version')
    -- Each public id's holder: one identity may name an id more than once.
    local holders = {}
    local function namedId(name, identityParts)
        local identity, settingId = key(identityParts), 'MCT_' .. name
        assert(holders[settingId] == nil or holders[settingId] == identity, 'menu id clash: ' .. settingId)
        holders[settingId] = identity
        return settingId
    end
    local function publicName(value)
        local result = tostring(value):gsub('[^%w]+', ' ')
            :gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end)
            :gsub('%s+', '')
        assert(result ~= '', 'public menu name is empty')
        return result
    end
    local rows, groups, selectors, multiSelectors, pickers = {}, {}, {}, {}, {}
    local groupSections, groupOrder = {}, {}
    local aggregateGroups, aggregateGroupOrder = {}, {}
    local aggregateRows, pageRows, categoryLabels, currentCategory, currentOwner = {}, {}, {}, nil, nil
    local function row(fields)
        rows[#rows + 1] = fields
        fields._category = currentCategory
        fields._owner = currentOwner
        pageRows[currentCategory] = pageRows[currentCategory] or {}
        pageRows[currentCategory][#pageRows[currentCategory] + 1] = fields
        return fields.id
    end
    -- Where a row is saved, in its page's config file: [<Module>.<Template>] <Setting> for a
    -- template's rows, [Templates] <Category> for a category's template picks (and
    -- <Category>Priority<n> per priority), [<category>] <Setting> for its shared fields.
    -- Rows that save nothing (actions, links, text) keep none. Two rows at one place fail
    -- the menu, so startup rejects the later provider file.
    local addresses = {}
    local function storeAt(item, section, name)
        if item.action or item.link or item.widget == 'text' or item.widget == 'table' then return end
        local address = M.address(section, name)
        local place = '[' .. address.section .. '] ' .. address.key
        assert(addresses[place] == nil or addresses[place] == item.id,
            'menu storage clash: ' .. item.id .. ' and ' .. tostring(addresses[place]) .. ' at ' .. place)
        addresses[place], item.storage = item.id, address
        return address
    end
    local function picker(settingId, label, group, list, visible, title, default, description)
        return row({id = settingId, label = text(label), group = group, type = 'enum', values = list,
            default = default == nil and (list[1].key or list[1].value) or default, visible = visible,
            style = title and 'title' or nil, description = description})
    end
    -- A template's description as one line for the side panel, or nil.
    local function described(template, limit)
        local value = template.description
        return type(value) == 'string' and value:find('%S')
            and value:gsub('%c', ' '):match('^%s*(.-)%s*$'):sub(1, limit) or nil
    end
    -- A generated group is headed by its label and shown only by its visibility rule.
    local function group(identity, label, visible, style, publicId)
        local groupId = namedId(publicId, {'group', identity})
        if not groups[groupId] then
            groups[groupId] = true
            groupSections[groupId] = {id = groupId, label = text(label), visible = visible,
                style = style ~= 'category' and style or nil}
            groupOrder[#groupOrder + 1] = groupId
        end
        return groupId
    end
    -- root: the module folder of the template declaring it, for listed choices.
    local function field(settingId, source, groupId, root)
        local item = {id = settingId, label = source.label, group = groupId, default = source.default,
            description = source.description, style = source.style,
            type = source.type == 'navigation' and 'enum' or source.type}
        -- Default widgets are left out.
        if source.widget ~= 'picker' and source.widget ~= 'slider' and source.widget ~= 'range' then
            item.widget = source.widget
        end
        if source.keyed then
            -- Fixed choices by key; ModCoreSettings lists each from entry's choices from the
            -- module's files every time the menu opens.
            item.values = {}
            for index, choice in ipairs(source.choices) do
                if choice.from then
                    assert(root, settingId .. ': listed choices need a template module')
                    item.values[index] = {from = choice.from, root = root}
                else
                    item.values[index] = U.copy(choice)
                end
            end
            item.dim = source.dim and U.copy(source.dim) or nil
        elseif source.type == 'enum' or source.type == 'navigation' then
            item.values = choices(source.values, source.labels, source.notes, source.sounds)
            item.dim = source.dim and U.copy(source.dim) or nil
            item.action = source.type == 'navigation' or nil
            item.link = source.linkProvider
        elseif source.type == 'range' then
            item.values = {min = U.copy(source.min), max = U.copy(source.max), step = source.step,
                suffix = source.suffix, delta = U.copy(source.delta)}
            -- The canonical '<low>|<high>' is what the config holds; menu data takes {low, high}.
            item._bounds = source.bounds
        else
            item.values = {min = source.min, max = source.max, step = source.step, suffix = source.suffix}
        end
        return item
    end
    local entries = {}; for _, entry in ipairs(registry.templates) do entries[#entries + 1] = entry end
    -- A category's templates show in registration order, independent of priority;
    -- entries without a registration index follow, by id.
    table.sort(entries, function(a, b)
        local x, y = a.order or math.huge, b.order or math.huge
        if x ~= y then return x < y end
        return a.id < b.id
    end)
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
            -- Templates with a uniqueBy key share one picker per key: one for 'category'
            -- and one per priority for 'priority'. The others get an Enabled toggle each.
            local byKey, keyOrder, hasMulti = {}, {}, false
            for _, entry in ipairs(available) do
                local unique = entry.unique
                if unique then
                    if not byKey[unique] then
                        byKey[unique] = {}
                        keyOrder[#keyOrder + 1] = unique
                    end
                    table.insert(byKey[unique], entry)
                else
                    hasMulti = true
                end
            end
            -- The category picker first, then priority pickers, lowest priority first.
            table.sort(keyOrder, function(a, b)
                if a == 'category' or b == 'category' then return a == 'category' end
                return byKey[a][1].priority < byKey[b][1].priority
            end)
            -- A slot category is shown only in its slot, through its own hidden page.
            local slot = registry.categories:getCategory(category).slot
            local slotIds = {}
            local function slotRow(visible)
                local item = rows[#rows]
                if item.action then return end
                -- Slots copy DMM's own row types only.
                assert(item.type ~= 'range', category .. ': slot row ' .. item.id .. ' cannot be a range')
                assert(not visible or not visible.field or slotIds[visible.field],
                    category .. ': slot row ' .. item.id .. ' depends on a row outside the slot')
                item._slot, slotIds[item.id] = {visible = visible}, true
            end
            local aggregateCategory = not slot
            for _, entry in ipairs(available) do
                if entry.template.menu.target == 'module' then aggregateCategory = false end
            end
            local prefix, suffix = assert(category:match('^([^.]+)%.([^.]+)$'))
            local aggregateGroup = title(prefix)
            if not aggregateGroups[aggregateGroup] then
                aggregateGroups[aggregateGroup] = true
                aggregateGroupOrder[#aggregateGroupOrder + 1] = aggregateGroup
            end
            local ownerPickers, categoryValues = {}, nil
            for _, unique in ipairs(keyOrder) do
                local members = byKey[unique]
                assert(#members <= 63, category .. ': more than 63 templates in one uniqueBy picker'
                    .. ' exceeds picker capacity including None')
                local values, list, byValue = {M.NONE}, {{key = M.NONE, label = 'None'}}, {}
                for _, entry in ipairs(members) do
                    local value = entry.id
                    assert(value ~= M.NONE, category .. ': template id ' .. M.NONE .. ' is reserved')
                    values[#values + 1] = value
                    -- Each template choice notes its module, which ModCoreSettings names, and
                    -- carries its description for the side panel while it is the choice.
                    list[#list + 1] = {key = value, label = text(entry.template.label),
                        module = entry.template.module, description = described(entry.template, 1024)}
                    byValue[value] = entry.id
                end
                local selector
                if unique == 'category' then
                    local selectorName = category == 'player.quickslots' and 'Template'
                        or publicName(category) .. 'Template'
                    selector = namedId(selectorName, {'selector', category})
                    picker(selector, title(suffix), aggregateGroup, list, nil, nil, nil,
                        'Only one template from this list can be active at a time. None turns them all off.')
                    storeAt(rows[#rows], 'Templates', publicName(category))
                    selectors[category] = {id = selector, byValue = byValue}
                    categoryValues = values
                else
                    local priority = members[1].priority
                    selector = namedId(publicName(category) .. publicName('Priority ' .. priority) .. 'Template',
                        {'selector', category, 'priority', priority})
                    picker(selector, title(suffix) .. ' (priority ' .. priority .. ')', aggregateGroup, list, nil,
                        nil, nil, 'Only one template from this list can be active at a time, alongside those'
                            .. ' chosen at other priorities. None turns this list off.')
                    storeAt(rows[#rows], 'Templates', publicName(category) .. publicName('Priority ' .. priority))
                end
                rows[#rows]._control = true
                if aggregateCategory then aggregateRows[#aggregateRows + 1] = rows[#rows] end
                if slot then slotRow() end
                ownerPickers[unique] = selector
                pickers[#pickers + 1] = {category = category, id = selector, byValue = byValue}
            end
            if hasMulti then multiSelectors[category] = {} end
            decoded[category] = {}
            local categoryGroups, staticSettings, staticFormats = Provider.normalizeCategory(
                registry.categories:getCategory(category).menu)
            local sharedFields, textIds = {}, {}
            categorySettings[category] = {fields=sharedFields, static=staticSettings, textIds=textIds}
            for name, default in pairs(staticSettings) do
                local settingId = namedId(publicName(category) .. publicName(name),
                    {'category_text', category, name})
                textIds[name] = settingId
                textSettings[settingId] = {default=default, format=staticFormats[name],
                    storage=storeAt({id=settingId}, category, publicName(name))}
            end
            -- Shared category fields show while any template is selected; with more than
            -- the category picker they always show.
            local selected = #keyOrder == 1 and categoryValues and not hasMulti
                and rule(ownerPickers.category, {table.unpack(categoryValues, 2)}) or nil
            for _, providerGroup in ipairs(categoryGroups) do
                local groupId = group(key({category, 'category_provider', providerGroup.id}),
                    providerGroup.label, selected, providerGroup.style,
                    publicName(category) .. publicName(providerGroup.id))
                for _, source in ipairs(providerGroup.fields) do
                    local settingId = namedId(publicName(category) .. publicName(source.id),
                        {'category_provider', category, source.id})
                    row(field(settingId, source, groupId))
                    storeAt(rows[#rows], category, publicName(source.id))
                    rows[#rows]._control = true
                    if aggregateCategory then aggregateRows[#aggregateRows + 1] = rows[#rows] end
                    if slot then slotRow(selected) end
                    if source.type ~= 'navigation' then sharedFields[source.id] = settingId end
                end
            end
            for _, entry in ipairs(available) do
                local template, identity = entry.template, entry.id
                currentOwner = identity
                local value = identity
                -- Generated ids name the module and the template: MCT_<Module>_<Template>_...
                local templateScope = (template.providerId and publicName(template.providerId) .. '_' or '')
                    .. publicName(template.localId or template.id)
                local scopePrefix = templateScope .. '_'
                local section = template.providerId and template.providerId .. '.' .. (template.localId or template.id)
                    or template.id
                local definition = {id=entry.id,scope=templateScope,fields={},enabled=template.menu.enabled}
                local providerGroups = template.groups
                definition.settings, definition.navigation = {}, {}
                local providerFieldIds = {}
                decoded[category][value] = definition
                local ownerSelector, ownerValue = ownerPickers[entry.unique], value
                local headingId
                if not entry.unique then
                    ownerSelector = namedId(templateScope .. '_Enabled', {'template_enabled', identity})
                    ownerValue = 1
                    -- The toggle stands in for its group's heading: one heading-styled row
                    -- names the template and turns it on or off.
                    headingId = group(key({identity, 'template_heading'}), template.label,
                        nil, 'none', templateScope)
                    -- Off unless the template declares defaultEnabled=true.
                    -- Its side panel describes the template.
                    picker(ownerSelector, template.label, headingId, choices({0, 1}, {'Disabled', 'Enabled'}), nil, nil,
                        template.defaultEnabled == true and 1 or 0,
                        described(template, 4096) or 'Turns this template on or off.')
                    definition.enabledId = ownerSelector
                    storeAt(rows[#rows], section, 'Enabled')
                    rows[#rows]._control, rows[#rows].style, rows[#rows].widget = true, 'category', 'switch'
                    if aggregateCategory then aggregateRows[#aggregateRows + 1] = rows[#rows] end
                    multiSelectors[category][#multiSelectors[category] + 1] = {
                        id=ownerSelector, value=value, definition=definition}
                    if slot then slotRow() end
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
                            providerGroup.label, groupVisible, providerGroup.style,
                            scopePrefix .. publicName(providerGroup.id))
                        -- Under a template's on/off heading row its groups are subgroups,
                        -- headed in ModCoreSettings' smaller subgroup style without a rule.
                        groupSections[groupId].within = headingId
                        local settingId = namedId(scopePrefix .. publicName(source.id),
                            {'provider', identity, source.id})
                        local item = field(settingId, source, groupId, moduleRoot(entry.location))
                        if providerGroup.variationSource then item.visible = owned end
                        if source.visibleWhen then
                            local sourceId = providerFieldIds[source.visibleWhen]
                            assert(sourceId, 'provider visibility source must precede dependent field: '
                                .. source.id)
                            item.visible = rule(sourceId, source.visibleValues)
                        end
                        item.visible = withPlayer(item.visible, source.visiblePlayer)
                        if source.labelWhen then
                            item.relabel = {field = assert(providerFieldIds[source.labelWhen],
                                'provider label source must precede dependent field: ' .. source.id),
                                values = U.copy(source.labelTexts)}
                        end
                        row(item)
                        storeAt(item, section, publicName(source.id))
                        -- Slot rows carry no group rules, so each takes the rule its group or
                        -- field would apply.
                        if slot then
                            slotRow(withPlayer(source.visibleWhen and item.visible or groupVisible,
                                source.visiblePlayer))
                        end
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
    -- ModCoreSettings takes a row's or group's rules under conditions.
    local function conditioned(out)
        if out.visible or out.relabel or out.dim then
            out.conditions = {visible = out.visible, label = out.relabel, dim = out.dim}
            out.visible, out.relabel, out.dim = nil, nil, nil
        end
        return out
    end
    local function plain(item)
        local out = {}
        for name, value in pairs(item) do
            if name:sub(1, 1) ~= '_' then out[name] = U.copy(value) end
        end
        if out.type == 'range' then out.default = Provider.rangePair(out.default) end
        return conditioned(out)
    end
    -- A page's menu data. Values are stored in configFile (the central config by default),
    -- relative to the page's config directory.
    local function providerMenu(providerName, selectedRows, aggregatePage, configFile)
        local titles = 0
        for _, item in ipairs(selectedRows) do
            if item.style == 'title' then titles = titles + 1 end
        end
        assert(titles <= 1, providerName .. ': only one title row per page')
        local used = {}
        for _, item in ipairs(selectedRows) do used[item.group] = true end
        local menu = {storage = {file = configFile or Layout.configFile, section = 'Templates'},
            groups = {}, fields = {}}
        -- Category groups head the aggregate's sections; other pages have one category.
        for _, groupId in ipairs(aggregateGroupOrder) do
            if used[groupId] then
                menu.groups[#menu.groups + 1] = {id = groupId, style = not aggregatePage and 'none' or nil}
            end
        end
        -- A subgroup goes in its heading group's groups, after that group's own rows.
        local listed = {}
        for _, groupId in ipairs(groupOrder) do
            if used[groupId] then
                local section = conditioned(U.copy(groupSections[groupId]))
                local outer = listed[section.within]
                section.within = nil
                if outer then
                    outer.groups = outer.groups or {}
                    outer.groups[#outer.groups + 1] = section
                else
                    menu.groups[#menu.groups + 1] = section
                end
                listed[groupId] = section
            end
        end
        assert(#selectedRows <= M.MAX_FIELDS, providerName .. ': page exceeds ' .. M.MAX_FIELDS .. ' settings')
        for _, item in ipairs(selectedRows) do
            local stored = plain(item)
            -- The aggregate lists several categories, so none takes the title row.
            if aggregatePage and stored.style == 'title' then stored.style = nil end
            menu.fields[#menu.fields + 1] = stored
        end
        return menu
    end
    local schema = {}
    for _, r in ipairs(rows) do schema[r.id] = r end
    -- A template reads a range as {low, high}; every other value as stored.
    local function exposed(settingId, value)
        local r = schema[settingId]
        if r and r.type == 'range' and type(value) == 'string' then return Provider.rangePair(value) end
        return value
    end
    local function makeDecoder(requiredRows, includedCategories, owned)
      return function(values)
        assert(type(values) == 'table', 'Apply values must be a table')
        local effective = {}
        for settingId, r in pairs(schema) do effective[settingId] = r.default end
        for _, r in ipairs(requiredRows) do
            local settingId = r.id
            local value = values[settingId]
            if value == nil and r.action then value = r.default end
            assert(value ~= nil, 'missing/invalid setting ' .. settingId)
            assert(M.accepts(r, value), 'invalid ' .. r.type .. ' ' .. settingId)
            effective[settingId] = value
        end
        -- Each included category decodes to its selected template ids: every picker's
        -- choice, then every enabled toggle. A category with a selection has its shared
        -- values checked; decodeState computes the settings themselves.
        local result = {}
        local function select(category, definition)
            local selections = result[category]
            if #selections == 0 then
                local shared, config = categorySettings[category], {}
                for name, default in pairs(shared.static) do
                    local supplied = values[shared.textIds[name]]
                    config[name] = supplied == nil and default or supplied
                end
                for name, settingId in pairs(shared.fields) do config[name] = effective[settingId] end
                Provider.validateCategory(registry.categories:getCategory(category).menu, config)
            end
            selections[#selections + 1] = {id = definition.id}
        end
        for _, selector in ipairs(pickers) do
            local category = selector.category
            if not includedCategories or includedCategories[category] then
                result[category] = result[category] or {}
                local definition = decoded[category][effective[selector.id]]
                if definition and (not owned or owned[definition.id]) then select(category, definition) end
            end
        end
        for category, templates in pairs(multiSelectors) do
            if not includedCategories or includedCategories[category] then
                result[category] = result[category] or {}
                for _, item in ipairs(templates) do
                    if (not owned or owned[item.definition.id]) and effective[item.id] == 1 then
                        select(category, item.definition)
                    end
                end
            end
        end
        return result
      end
    end
    local aggregateId = 'ModCoreTemplates'
    local aggregateMenu = providerMenu('ModCore Templates', aggregateRows, true)
    local allCategories = {}; for _, selector in ipairs(pickers) do allCategories[selector.category] = true end
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
                        header.style = 'title'
                        selected[#selected + 1] = header
                    else
                        selected[#selected + 1] = item
                    end
                end
            end
        end
        return selected
    end
    local categoryOwned, moduleOwned, moduleCategories, moduleRoots, modulePreviews = {}, {}, {}, {}, {}
    -- Modules whose templates all moved to a slot keep an entry that opens the slot.
    local slotModules = {}
    -- A template may give its module page a live preview: preview={background=<picture
    -- in the module folder>}; the first one declared names the background.
    local function declarePreview(module, template, parent, location)
        if type(template.preview) ~= 'table' or not parent or modulePreviews[module] then return end
        local background = template.preview.background
        assert(background == nil or type(background) == 'string' and background:match('^[%w_%-./]+$')
            and not background:find('..', 1, true), location .. ': invalid preview background')
        modulePreviews[module] = {background = background and parent .. '/' .. background or nil}
    end
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
                declarePreview(module, template, parent, entry.location)
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
            declarePreview(module, template, parent, entry.location)
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
            -- As on a module page: the category's pickers, then each template's groups under
            -- their own headings. The pickers share the unheaded group Slot (a host slot with
            -- slotLabel heads it with its own label); the templates' groups keep their labels
            -- and styles but no rules: each row carries its slot visibility, and a heading
            -- shows while any of its rows does.
            local menu = {storage = {file = Layout.configFile, section = 'Templates'},
                groups = {{id = 'Slot', style = 'none'}}, fields = {}}
            local aggregate, used, listed = {}, {}, {}
            for _, groupId in ipairs(aggregateGroupOrder) do aggregate[groupId] = true end
            for _, item in ipairs(selectedRows) do
                if not aggregate[item.group] then used[item.group] = true end
            end
            for _, groupId in ipairs(groupOrder) do
                if used[groupId] then
                    local section = U.copy(groupSections[groupId])
                    local outer = listed[section.within]
                    section.visible, section.within = nil, nil
                    section = conditioned(section)
                    if outer then
                        outer.groups = outer.groups or {}
                        outer.groups[#outer.groups + 1] = section
                    else
                        menu.groups[#menu.groups + 1] = section
                    end
                    listed[groupId] = section
                end
            end
            local selector = selectors[category] and selectors[category].id
            for _, item in ipairs(selectedRows) do
                local stored = plain(item)
                -- A slot row keeps its other rules and takes its slot's visibility.
                if aggregate[item.group] then stored.group, stored.style = 'Slot', nil end
                -- The category picker is the page's Template entry.
                if stored.id == selector then stored.label = 'Template' end
                local conditions = stored.conditions or {}
                conditions.visible = U.copy(item._slot.visible)
                stored.conditions = next(conditions) and conditions or nil
                menu.fields[#menu.fields + 1] = stored
            end
            assert(#menu.fields <= M.MAX_FIELDS,
                categoryLabels[category] .. ': slot page exceeds ' .. M.MAX_FIELDS .. ' settings')
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
        page.categories, page.owned = moduleCategories[module], moduleOwned[module]
        if modulePreviews[module] then page.menu.preview, page.preview = modulePreviews[module], true end
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
            if item.style == 'title' then
                item = U.copy(item)
                item.style = nil
            end
            if not item.action then selectedRows[#selectedRows + 1] = item end
        end
        local host = title(entry.slot:match('^[^:]+'))
        table.insert(selectedRows, 1, {id='MCT_MergedNotice', group=selectedRows[1].group,
            label='These settings have been merged into ' .. host .. ' and can also be edited there',
            description='Opens these settings on the ' .. host .. ' page.', type='enum', values={{value=0, label=host}}, default=0, action=true, widget='tabs', link=entry.slot,
            style='notice'})
        local page = {id=providerId, name=module, merged=entry.slot, moduleRoot=entry.root, rows=selectedRows,
            menu=providerMenu(module, selectedRows, false)}
        page.decode = makeDecoder(page.rows, entry.categories, entry.owned)
        -- Its preview shows the slot's templates the module owns.
        page.categories, page.owned = entry.categories, entry.owned
        if modulePreviews[module] then page.menu.preview, page.preview = modulePreviews[module], true end
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
                local definition = decoded[category][selection.id]
                if not definition.enabled then return end
                local own = {}
                for name, settingId in pairs(definition.settings) do own[name] = exposed(settingId, values[settingId]) end
                selections[selection.id] = own
            end
            for _, selection in ipairs(decodedSelections[category]) do selected(selection) end
            state[category] = {settings=effectiveCategory, selections=selections}
        end
        return state
    end
    return {menu = aggregateMenu,
        rows = rows, selectors = selectors, pickers = pickers, multiSelectors=multiSelectors, definitions = decoded,
        textSettings = textSettings, decodeState=decodeState, categorySettings=categorySettings,
        decode = decodeAll, aggregate=aggregate, pages=pages,
        pageByCategory=pageByCategory, pageByModule=pageByModule, pageBySlot=pageBySlot, providers=providers}
end

-- ModCoreSettings' limit on the fields of one published page.
M.MAX_FIELDS = 256
-- The key of a template picker's None choice. A loaded template's id holds an '_', so
-- none can take it; a template id 'None' is refused.
M.NONE = 'None'
-- A row's place in its config file: section and key, each spelled with letters, digits
-- and _ . : - only (others become _).
function M.address(section, name)
    local function spelled(value)
        local result = tostring(value):gsub('[^%w_.:-]', '_')
        return result
    end
    return {section = spelled(section), key = spelled(name)}
end
-- Where a row's value is read and written: its storage, else the page's [Templates] by id.
function M.placeOf(r)
    if r.storage then return r.storage.section, r.storage.key end
    return 'Templates', r.id
end

-- Whether a row is a keyed enum: its choices carry text keys, stored as text.
function M.keyed(r)
    local first = r.type == 'enum' and type(r.values) == 'table' and r.values[1]
    return type(first) == 'table' and (first.key ~= nil or first.from ~= nil)
end

-- Whether a row accepts a value: one of an enum's values, a whole number within an
-- integer's, or a range's canonical '<low>|<high>'.
function M.accepts(r, value)
    if r.type == 'range' then return type(value) == 'string' and Provider.rangeText(r._bounds, value) == value end
    if M.keyed(r) then
        -- A listed field takes any well-formed key: its choices change with the module's
        -- files, and the template falls back for one that is gone.
        local listed = false
        for _, choice in ipairs(r.values) do
            if choice.key == value then return true end
            if choice.from then listed = true end
        end
        return listed and From.validKey(value)
    end
    if type(value) ~= 'number' or value ~= value then return false end
    if r.type == 'integer' then return value >= r.values.min and value <= r.values.max and value % 1 == 0 end
    for _, choice in ipairs(r.values) do if choice.value == value then return true end end
    return false
end

return M
