local U = require('mc.util')
local M = {}
local function finite(v) return type(v) == 'number' and v == v and math.abs(v) <= 1000000000 end
local function text(v, where)
    U.text(v, where)
    assert(#v <= 4096 and not v:find('[%c|;%[%]]') and not v:match('^%s') and not v:match('%s$'),
        where .. ': unsupported metadata text')
    return v
end
local function identifier(v, where)
    text(v, where)
    assert(#v <= 128 and v:match('^[%a_][%w_]*$'), where .. ': invalid stable identifier')
end
local function level(v, picker)
    assert(v == nil or (finite(v) and v % 1 == 0
        and (v == 0 or (picker and v == 1) or (v >= 2 and v <= 6))),
        'provider level must be 0 or 2..6; level 1 requires a picker')
end
local function allowed(value, names, where)
    for name in pairs(value) do assert(names[name], where .. ': unsupported property ' .. tostring(name)) end
end
local function order(value, index)
    assert(value == nil or finite(value), 'provider order must be finite')
    return value or index
end
local function sort(a, b)
    if a.order == b.order then return a.index < b.index end
    return a.order < b.order
end

local domains = {
    percent = {min=0,max=100,step=1,suffix='%'},
}

local function title(value)
    return value:gsub('_', ' '):gsub('(%a)([%w_]*)', function(a, b) return a:upper() .. b end)
end

local function choiceDomain(source, where)
    assert(type(source) == 'table', where .. ': values must be a named domain or table')
    local values, labels = {}, {}
    for value, label in pairs(source) do
        assert(finite(value), where .. ': picker keys must be finite numbers')
        text(label, where .. ' label')
        values[#values + 1] = value
    end
    table.sort(values)
    assert(#values >= 2 and #values <= 64, where .. ': picker requires 2..64 choices')
    for index, value in ipairs(values) do labels[index] = source[value] end
    return {type='picker',values=values,labels=labels}
end

local function valueDomain(source, where)
    if type(source) == 'string' then
        local domain = assert(domains[source], where .. ': unknown value type ' .. source)
        return {type='integer',min=domain.min,max=domain.max,step=domain.step,suffix=domain.suffix}
    end
    assert(type(source) == 'table', where .. ': values must be a named domain or table')
    if source.min ~= nil or source.max ~= nil or source.step ~= nil then
        allowed(source, {min=true,max=true,step=true,suffix=true}, where .. ' range')
        return {type='integer',min=source.min,max=source.max,step=source.step,suffix=source.suffix}
    end
    return choiceDomain(source, where)
end

local function resolveId(parent, value, where)
    text(value, where)
    if value:sub(1,1) == '.' then
        assert(#value > 1, where .. ': empty relative id')
        value = parent .. value:sub(2)
    end
    identifier(value, where)
    return value
end

-- Field conditions name a picker declared earlier in the same template, so every
-- generated row names a row that precedes it. A slot row carries one visibility
-- condition, so a field in a variation branch inherits that branch through a
-- source in the same branch.
local function conditions(field, source, parent, pickers, branch)
    if source.conditions == nil then return end
    local where = 'template field ' .. field.id .. ' conditions'
    assert(type(source.conditions) == 'table', where .. ' must be a table')
    allowed(source.conditions, {visible=true,label=true}, where)
    local function condition(name, extra)
        local rule = source.conditions[name]
        if rule == nil then return end
        assert(type(rule) == 'table', where .. '.' .. name .. ' must be a table')
        allowed(rule, {field=true,match=true,text=extra}, where .. '.' .. name)
        if parent == '' then
            text(rule.field, where .. '.' .. name .. '.field')
            assert(rule.field:sub(1,1) ~= '.', where .. '.' .. name .. '.field must be absolute')
        end
        local id = resolveId(parent, rule.field, where .. '.' .. name .. '.field')
        assert(pickers[id], where .. '.' .. name .. '.field must name a picker declared earlier')
        U.array(rule.match, where .. '.' .. name .. '.match')
        return id, U.copy(rule.match), rule
    end
    local id, match = condition('visible')
    if id then
        assert(not branch or pickers[id] == branch,
            where .. '.visible.field must name a picker in the same variation branch')
        field.visibleWhen, field.visibleValues = id, match
    end
    local rule
    id, match, rule = condition('label', true)
    if id then
        field.labelWhen, field.labelValues = id, match
        field.labelText = text(rule.text, where .. '.label.text')
    end
end

-- Compile the concise public template schema into the strict intermediary schema.
function M.template(menu, variations)
    menu, variations = menu or {}, variations or {}
    U.array(menu, 'template menu')
    assert(type(variations) == 'table', 'template variations must be a table')
    local variationNames, variationFields, variationIds, variationChoices = {}, {}, {}, {}
    local resolvedVariationIds = {}
    for name, source in pairs(variations) do
        identifier(name, 'variation id')
        assert(type(source) == 'table', 'variation must be a table')
        allowed(source, {description=true,values=true,default=true}, 'variation')
        local domain = choiceDomain(source.values, 'variation ' .. name)
        assert(finite(source.default), 'variation default is required')
        local found = false
        for _, value in ipairs(domain.values) do if value == source.default then found = true end end
        assert(found, 'variation default must match a choice')
        if source.description ~= nil then text(source.description, 'variation description') end
        variationNames[#variationNames + 1] = name
        variationChoices[name] = domain.values
        local id = title(name):gsub('%s+', '')
        assert(not resolvedVariationIds[id], 'duplicate/reserved resolved variation id ' .. id)
        resolvedVariationIds[id], variationIds[name] = true, id
    end
    table.sort(variationNames)
    for _, name in ipairs(variationNames) do
        local source = variations[name]
        local domain = choiceDomain(source.values, 'variation ' .. name)
        variationFields[#variationFields + 1] = {
            id=variationIds[name],label=title(name),type='picker',values=domain.values,
            labels=domain.labels,default=source.default,
            description=source.description,
        }
    end
    -- Variations lead the menu in their own group, when the template declares any.
    -- Standalone group ids count the Template group's position even when it is absent,
    -- so generated ids do not depend on whether a template declares variations.
    local groups, absentTemplate = {}, 1
    if #variationFields > 0 then
        groups[1], absentTemplate = {id='Template',label='Template',heading=false,fields=variationFields}, 0
    end
    local groupIds, fieldIds, pickers = {Template=true}, {}, {}
    for _, field in ipairs(variationFields) do
        fieldIds[field.id] = true
        if field.type == 'picker' then pickers[field.id] = true end
    end
    for _, sourceGroup in ipairs(menu) do
        assert(type(sourceGroup) == 'table', 'template menu entry must be a table')
        if sourceGroup.fields == nil then
            allowed(sourceGroup, {id=true,label=true,values=true,default=true,tab=true,level=true,
                description=true,conditions=true}, 'template field')
            text(sourceGroup.id, 'template field id')
            assert(sourceGroup.id:sub(1,1) ~= '.', 'standalone template field id must be absolute')
            local id = resolveId('', sourceGroup.id, 'template field id')
            assert(not fieldIds[id], 'duplicate template field ' .. id)
            fieldIds[id] = true
            text(sourceGroup.label, 'template field label')
            local domain = valueDomain(sourceGroup.values, 'template field ' .. id)
            local field = {id=id,label=sourceGroup.label,type=domain.type,values=domain.values,
                labels=domain.labels,min=domain.min,max=domain.max,step=domain.step,
                suffix=domain.suffix,default=sourceGroup.default,tab=sourceGroup.tab,
                level=sourceGroup.level,description=sourceGroup.description}
            conditions(field, sourceGroup, '', pickers)
            if field.type == 'picker' then pickers[id] = true end
            local groupId = 'Standalone' .. tostring(#groups + absentTemplate)
            assert(not groupIds[groupId], 'reserved template menu id collision ' .. groupId)
            groupIds[groupId] = true
            groups[#groups + 1] = {id=groupId,label=sourceGroup.label,heading=false,fields={field}}
        else
            allowed(sourceGroup, {id=true,label=true,level=true,heading=true,variation=true,fields=true},
                'template menu entry')
            text(sourceGroup.id, 'template menu id')
            text(sourceGroup.label, 'template menu label')
            U.array(sourceGroup.fields, 'template menu fields')
            local variationName, variationValue
            if sourceGroup.variation ~= nil then
                assert(type(sourceGroup.variation) == 'table', 'menu variation must be a table')
                for candidate, value in pairs(sourceGroup.variation) do
                    assert(variationName == nil, 'menu entry must reference exactly one variation')
                    variationName, variationValue = candidate, value
                end
                assert(variationName ~= nil and variationIds[variationName],
                    'menu entry references an unknown variation')
                local found = false
                for _, value in ipairs(variationChoices[variationName]) do
                    if value == variationValue then found = true end
                end
                assert(found, 'menu entry variation value is not declared')
            end
            if sourceGroup.id:sub(1,1) == '.' then
                assert(variationName, 'relative template menu id requires a variation parent')
            end
            local groupId = resolveId(variationName and variationIds[variationName] or '',
                sourceGroup.id, 'template menu id')
            assert(not groupIds[groupId], 'duplicate/reserved template menu id ' .. groupId)
            groupIds[groupId] = true
            local group = {id=groupId,label=sourceGroup.label,level=sourceGroup.level,
                heading=sourceGroup.heading,fields={}}
            if variationName then
                group.variationSource = variationIds[variationName]
                group.variationValues = {variationValue}
            end
            for _, source in ipairs(sourceGroup.fields) do
                assert(type(source) == 'table', 'template field must be a table')
                allowed(source, {id=true,label=true,values=true,default=true,tab=true,level=true,
                    description=true,conditions=true}, 'template field')
                local id = resolveId(groupId, source.id, 'template field id')
                assert(not fieldIds[id], 'duplicate template field ' .. id)
                fieldIds[id] = true
                text(source.label, 'template field label')
                local domain = valueDomain(source.values, 'template field ' .. id)
                local field = {id=id,label=source.label,type=domain.type,values=domain.values,
                    labels=domain.labels,min=domain.min,max=domain.max,step=domain.step,
                    suffix=domain.suffix,default=source.default,tab=source.tab,level=source.level,
                    description=source.description}
                local branch = variationName and variationName .. '=' .. tostring(variationValue)
                conditions(field, source, groupId, pickers, branch)
                if field.type == 'picker' then pickers[id] = branch or true end
                group.fields[#group.fields + 1] = field
            end
            groups[#groups + 1] = group
        end
    end
    local declaration = {enabled=true,target='module',groups=groups}
    return declaration, M.normalize(declaration)
end

function M.normalize(declaration)
    assert(type(declaration) == 'table', 'menu must be a table')
    allowed(declaration, {enabled=true,target=true,groups=true}, 'menu')
    assert(type(declaration.enabled)=='boolean', 'menu.enabled must be boolean')
    assert(declaration.target == nil or declaration.target == 'templates' or declaration.target == 'module',
        'menu.target must be templates or module')
    local declaredGroups=declaration.groups or {}
    U.array(declaredGroups, 'settings.groups')
    local groups, byId, fields, headerPickers = {}, {}, {}, 0
    for groupIndex, sourceGroup in ipairs(declaredGroups) do
        assert(type(sourceGroup) == 'table', 'provider group must be a table')
        allowed(sourceGroup, {id=true,label=true,level=true,order=true,heading=true,fields=true,
            variationSource=true,variationValues=true},
            'provider group')
        identifier(sourceGroup.id, 'provider group id')
        text(sourceGroup.label, 'provider group label')
        level(sourceGroup.level)
        assert(sourceGroup.heading == nil or type(sourceGroup.heading) == 'boolean',
            'provider group heading must be boolean')
        assert(not byId[sourceGroup.id], 'duplicate provider group ' .. sourceGroup.id)
        local group = {id=sourceGroup.id,label=sourceGroup.label,level=sourceGroup.level,
            heading=sourceGroup.heading,order=order(sourceGroup.order,groupIndex),index=groupIndex,
            fields={},variationSource=sourceGroup.variationSource,
            variationValues=sourceGroup.variationValues}
        groups[#groups+1], byId[sourceGroup.id] = group, group
        U.array(sourceGroup.fields, 'provider group fields')
        for fieldIndex, source in ipairs(sourceGroup.fields) do
            assert(type(source) == 'table', 'provider field must be a table')
            allowed(source, {id=true,label=true,type=true,order=true,default=true,values=true,
                labels=true,min=true,max=true,step=true,suffix=true,tab=true,level=true,description=true,
                visibleWhen=true,visibleValues=true,labelWhen=true,labelValues=true,
                labelText=true,tabNavigation=true,linkProvider=true}, 'provider field')
            identifier(source.id, 'provider field id'); text(source.label, 'provider field label')
            level(source.level, source.type == 'picker' or source.type == 'navigation')
            if source.level == 1 then
                headerPickers = headerPickers + 1
                assert(headerPickers <= 1, 'only one level-1 picker per template')
            end
            assert(not fields[source.id], 'duplicate provider field ' .. source.id)
            local field = U.copy(source)
            fields[source.id] = field
            field.group = group.id
            field.order, field.index = order(source.order,fieldIndex), fieldIndex
            if field.description ~= nil then text(field.description, 'provider description') end
            if field.linkProvider ~= nil then
                assert(field.type == 'navigation', 'linkProvider requires a navigation field')
                text(field.linkProvider, 'provider link target')
                assert(#field.linkProvider <= 128 and field.linkProvider:match('^[%w_.:-]+$'),
                    'invalid provider link target')
            end
            if field.suffix ~= nil then text(field.suffix, 'provider suffix') end
            if field.visibleWhen ~= nil then identifier(field.visibleWhen, 'provider visibility source') end
            assert((field.visibleWhen == nil) == (field.visibleValues == nil),
                'provider visibility requires both visibleWhen and visibleValues')
            if field.labelWhen ~= nil then
                identifier(field.labelWhen, 'provider label source')
                text(field.labelText, 'provider label text')
            end
            assert((field.labelWhen == nil) == (field.labelValues == nil)
                and (field.labelWhen == nil) == (field.labelText == nil),
                'provider label requires labelWhen, labelValues and labelText')
            assert(field.tab == nil or type(field.tab) == 'boolean', 'provider tab must be boolean')
            assert(field.tabNavigation == nil or (field.type == 'navigation'
                and field.tab == true and field.tabNavigation == 1),
                'tabNavigation=1 requires a navigation tab')
            if field.type == 'integer' then
                assert(field.values == nil and field.labels == nil and not field.tab,
                    'integer cannot declare choices/tabs')
                field.step = field.step or 1
                for _, name in ipairs({'min','max','step','default'}) do
                    assert(finite(field[name]) and field[name] % 1 == 0,
                        'provider integer ' .. name .. ' required')
                end
                assert(field.min < field.max and field.step >= 1 and field.step <= field.max-field.min,
                    'invalid provider integer range/step')
                assert(field.default >= field.min and field.default <= field.max,
                    'provider default outside range')
            elseif field.type == 'picker' or field.type == 'navigation' then
                assert(field.min == nil and field.max == nil and field.step == nil and field.suffix == nil,
                    'picker cannot declare integer range/suffix')
                local count = U.array(field.values, 'provider picker values')
                assert(count >= 2 and count <= 64 and U.array(field.labels, 'provider picker labels') == count,
                    'provider picker requires 2..64 matching choices')
                assert(not field.tab or count <= 8, 'provider tabs support at most 8 choices')
                local seen = {}
                for i, value in ipairs(field.values) do
                    assert(finite(value) and not seen[value], 'invalid/duplicate provider choice')
                    seen[value] = true; text(field.labels[i], 'provider choice label')
                end
                assert(finite(field.default) and seen[field.default], 'provider default must match a choice')
            else error('unsupported provider field type: ' .. tostring(field.type)) end
            group.fields[#group.fields+1] = field
        end
    end
    for _, group in ipairs(groups) do
        if group.variationSource then
            identifier(group.variationSource, 'group variation source')
            local source = fields[group.variationSource]
            assert(source and source.type == 'picker', 'group variation source must be a picker')
            assert(U.array(group.variationValues, 'group variation values') > 0,
                'group variation values must not be empty')
            local choices = {}
            for _, value in ipairs(source.values) do choices[value] = true end
            for _, value in ipairs(group.variationValues) do
                assert(choices[value], 'group variation value must be a source choice')
            end
        else
            assert(group.variationValues == nil, 'group variation values require a source')
        end
        for _, field in ipairs(group.fields) do
            for _, rule in ipairs({{field.visibleWhen, field.visibleValues, 'visibility'},
                {field.labelWhen, field.labelValues, 'label'}}) do
                local sourceId, matched, kind = rule[1], rule[2], rule[3]
                if sourceId then
                    assert(sourceId ~= field.id, 'provider field cannot depend on itself')
                    local source = fields[sourceId]
                    assert(source and (source.type == 'picker' or source.type == 'navigation'),
                        'provider ' .. kind .. ' source must be a picker in the same template')
                    local count = U.array(matched, 'provider ' .. kind .. ' values')
                    assert(count > 0, 'provider ' .. kind .. ' values must not be empty')
                    local choices, seen = {}, {}
                    for _, value in ipairs(source.values) do choices[value] = true end
                    for _, value in ipairs(matched) do
                        assert(finite(value) and choices[value] and not seen[value],
                            'provider ' .. kind .. ' value must be a distinct source choice')
                        seen[value] = true
                    end
                end
            end
        end
    end
    table.sort(groups, sort)
    for _, group in ipairs(groups) do
        assert(#group.fields > 0, 'empty provider group: ' .. group.id)
        table.sort(group.fields, sort)
    end
    return groups
end

function M.validate(declaration, committed)
    local expected = {}
    for _, group in ipairs(M.normalize(declaration)) do
        for _, field in ipairs(group.fields) do
            if field.type ~= 'navigation' then
                expected[field.id] = true
                local value = committed[field.id]
                assert(finite(value), 'missing/invalid provider setting ' .. field.id)
                if field.type == 'integer' then
                    assert(value % 1 == 0 and value >= field.min and value <= field.max,
                        'provider setting outside range ' .. field.id)
                else
                    local found = false
                    for _, candidate in ipairs(field.values) do if value == candidate then found = true end end
                    assert(found, 'invalid provider choice ' .. field.id)
                end
            end
        end
    end
    if next(expected)==nil and committed==nil then return nil end
    assert(type(committed) == 'table', 'committed settings are required')
    for name in pairs(committed) do
        assert(expected[name], 'unknown provider setting ' .. tostring(name))
    end
    return committed
end

-- Category settings are shared by every template in that category. DMM can
-- edit numeric fields; text values can be edited in config.ini.
function M.normalizeCategory(declaration)
    if declaration == nil then return {}, {}, {} end
    assert(type(declaration) == 'table', 'category settings must be a table')
    allowed(declaration, {groups=true}, 'category settings')
    local declaredGroups = declaration.groups or {}
    U.array(declaredGroups, 'category settings.groups')
    local numericGroups, static, formats, seen, groupIds = {}, {}, {}, {}, {}
    for _, sourceGroup in ipairs(declaredGroups) do
        assert(type(sourceGroup) == 'table', 'category group must be a table')
        allowed(sourceGroup, {id=true,label=true,level=true,order=true,heading=true,fields=true},
            'category group')
        identifier(sourceGroup.id, 'category group id')
        text(sourceGroup.label, 'category group label')
        level(sourceGroup.level)
        assert(sourceGroup.heading == nil or type(sourceGroup.heading) == 'boolean',
            'category group heading must be boolean')
        assert(not groupIds[sourceGroup.id], 'duplicate category group ' .. sourceGroup.id)
        groupIds[sourceGroup.id] = true
        U.array(sourceGroup.fields, 'category group fields')
        local numericGroup = U.copy(sourceGroup)
        numericGroup.fields = {}
        for _, source in ipairs(sourceGroup.fields) do
            assert(type(source) == 'table', 'category field must be a table')
            identifier(source.id, 'category field id')
            assert(not seen[source.id], 'duplicate category field ' .. source.id)
            seen[source.id] = true
            if source.type == 'text' then
                allowed(source, {id=true,type=true,default=true,order=true,format=true},
                    'category text field')
                assert(type(source.default) == 'string', 'category text default must be a string')
                M.validateText(source.format, source.default)
                static[source.id] = source.default
                formats[source.id] = source.format or false
            else
                numericGroup.fields[#numericGroup.fields + 1] = U.copy(source)
            end
        end
        if #numericGroup.fields > 0 then numericGroups[#numericGroups + 1] = numericGroup end
    end
    if #numericGroups == 0 then return {}, static, formats end
    return M.normalize({enabled=true,target='templates',groups=numericGroups}), static, formats
end

function M.validateText(format, value)
    assert(type(value) == 'string' and #value > 0 and #value <= 4096
        and not value:find('[%c;#]'), 'invalid category text setting')
    assert(format == nil or format == false, 'unsupported category text format')
    return value
end

function M.validateCategory(declaration, committed)
    local groups, static, formats = M.normalizeCategory(declaration)
    local expected = {}
    for _, group in ipairs(groups) do
        for _, field in ipairs(group.fields) do
            if field.type ~= 'navigation' then
                expected[field.id] = true
                local value = type(committed) == 'table' and committed[field.id]
                assert(finite(value), 'missing/invalid category setting ' .. field.id)
                if field.type == 'integer' then
                    assert(value % 1 == 0 and value >= field.min and value <= field.max,
                        'category setting outside range ' .. field.id)
                else
                    local found = false
                    for _, candidate in ipairs(field.values) do if value == candidate then found = true end end
                    assert(found, 'invalid category choice ' .. field.id)
                end
            end
        end
    end
    for name, default in pairs(static) do
        expected[name] = true
        assert(type(committed) == 'table', 'missing category text setting ' .. name)
        M.validateText(formats[name], committed[name])
    end
    if next(expected) == nil and committed == nil then return nil end
    assert(type(committed) == 'table', 'committed category settings are required')
    for name in pairs(committed) do assert(expected[name], 'unknown category setting ' .. tostring(name)) end
    return committed
end


return M
