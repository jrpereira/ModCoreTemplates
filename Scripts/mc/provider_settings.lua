local U = require('mc.util')
local Contributions = require('menu_contributions')
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

-- A choice is its label, or a ModCoreSettings menu-data choice without its value:
-- {label=,note=,sound=}. Notes and sounds come back keyed by value.
local function choiceDomain(source, where)
    assert(type(source) == 'table', where .. ': values must be a named domain or table')
    local values, labels, notes, sounds = {}, {}, nil, nil
    local byValue = {}
    for value, choice in pairs(source) do
        assert(finite(value), where .. ': picker keys must be finite numbers')
        if type(choice) == 'table' then
            allowed(choice, {label=true,note=true,sound=true}, where .. ' choice ' .. tostring(value))
            if choice.note ~= nil then
                notes = notes or {}
                notes[value] = text(choice.note, where .. ' note')
            end
            if choice.sound ~= nil then
                sounds = sounds or {}
                sounds[value] = choice.sound
            end
            choice = choice.label
        end
        byValue[value] = text(choice, where .. ' label')
        values[#values + 1] = value
    end
    table.sort(values)
    assert(#values >= 2 and #values <= 64, where .. ': picker requires 2..64 choices')
    for index, value in ipairs(values) do labels[index] = byValue[value] end
    return {type='enum',values=values,labels=labels,notes=notes,sounds=sounds}
end

-- A range is a low and a high value on one track: ModCoreSettings' range editor. It stores
-- '<low>|<high>' and templates read it as {low, high}. At most this many steps.
local RANGE_STEPS = 40

-- A range's bounds, checked: min and max are an edge or {low marker's, high marker's};
-- delta is the smallest and largest high-low, {min, max} or one number for both.
function M.rangeBounds(source, where)
    where = where or 'range'
    local function pair(value, name)
        if type(value) == 'number' then return value, value end
        assert(type(value) == 'table' and (#value == 1 or #value == 2) and finite(value[1])
            and (value[2] == nil or finite(value[2])), where .. ': invalid range ' .. name)
        return value[1], value[2]
    end
    local lowMin, highMin = pair(source.min, 'min')
    local lowMax, highMax = pair(source.max, 'max')
    highMin, lowMax = highMin or lowMin, lowMax or highMax
    local step = source.step or 1
    local deltaMin, deltaMax = 0, highMax - lowMin
    if source.delta ~= nil then
        deltaMin, deltaMax = pair(source.delta, 'delta')
        deltaMax = deltaMax or highMax - lowMin
    end
    for _, value in ipairs({lowMin, highMin, lowMax, highMax, step, deltaMin, deltaMax}) do
        assert(value % 1 == 0, where .. ': range values must be whole')
    end
    local count = (highMax - lowMin) / step
    assert(lowMin < highMax and step >= 1 and count % 1 == 0 and count <= RANGE_STEPS,
        where .. ': range step must divide max-min into 1..' .. RANGE_STEPS .. ' steps')
    assert(lowMin <= highMin and lowMax <= highMax and lowMin <= lowMax and highMin <= highMax,
        where .. ': each marker needs min <= max, and the low marker\'s bounds <= the high marker\'s')
    for _, value in ipairs({highMin - lowMin, lowMax - lowMin, deltaMin, deltaMax}) do
        assert(value % step == 0, where .. ': range bounds and delta must be on the step')
    end
    assert(0 <= deltaMin and deltaMin <= deltaMax and deltaMax <= highMax - lowMin,
        where .. ': range delta must run 0 <= min <= max <= max-min')
    -- The closest the markers can be is HighMin-LowMax apart, when the zones are separate.
    assert(math.max(0, highMin - lowMax) <= deltaMax, where .. ': range bounds and delta leave no value')
    return {lowMin=lowMin,lowMax=lowMax,highMin=highMin,highMax=highMax,step=step,
        deltaMin=deltaMin,deltaMax=deltaMax}
end

-- The canonical '<low>|<high>' for a range value ('<low>|<high>' or {low, high}), or nil
-- when the bounds cannot hold it.
function M.rangeText(bounds, value)
    local a, b
    if type(value) == 'string' then
        a, b = value:match('^%s*([^|]-)%s*|%s*([^|]-)%s*$')
        a, b = tonumber(a), tonumber(b)
    elseif type(value) == 'table' and next(value, 2) == nil then
        a, b = value[1], value[2]
    end
    if not (finite(a) and finite(b)) then return nil end
    if (a - bounds.lowMin) % bounds.step ~= 0 or (b - bounds.lowMin) % bounds.step ~= 0 then return nil end
    if a < bounds.lowMin or a > bounds.lowMax or b < bounds.highMin or b > bounds.highMax then return nil end
    if b - a < bounds.deltaMin or b - a > bounds.deltaMax then return nil end
    return string.format('%d|%d', a, b)
end

-- {low, high} from a canonical range value.
function M.rangePair(value)
    local low, high = value:match('^(-?%d+)|(-?%d+)$')
    return {tonumber(low), tonumber(high)}
end

-- A field's domain from its values, and its declared type when it has one. A range is
-- always declared; otherwise a min/max table is an integer and a label map an enum.
local function valueDomain(source, declared, where)
    assert(declared == nil or declared == 'integer' or declared == 'enum' or declared == 'range',
        where .. ': type is integer, enum or range')
    local domain
    if declared == 'range' then
        assert(type(source) == 'table', where .. ': a range needs values')
        allowed(source, {min=true,max=true,step=true,suffix=true,delta=true}, where .. ' range')
        domain = {type='range',min=source.min,max=source.max,step=source.step,suffix=source.suffix,delta=source.delta}
    elseif type(source) == 'string' then
        local named = assert(domains[source], where .. ': unknown value type ' .. source)
        domain = {type='integer',min=named.min,max=named.max,step=named.step,suffix=named.suffix}
    else
        assert(type(source) == 'table', where .. ': values must be a named domain or table')
        if source.min ~= nil or source.max ~= nil or source.step ~= nil then
            assert(source.delta == nil and type(source.min) ~= 'table' and type(source.max) ~= 'table',
                where .. ': delta and min/max pairs need type=\'range\'')
            allowed(source, {min=true,max=true,step=true,suffix=true}, where .. ' integer')
            domain = {type='integer',min=source.min,max=source.max,step=source.step,suffix=source.suffix}
        else
            domain = choiceDomain(source, where)
        end
    end
    assert(declared == nil or declared == domain.type, where .. ': type ' .. tostring(declared)
        .. ' does not match its values (' .. domain.type .. ')')
    return domain
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
-- conditions take ModCoreSettings' menu-data shapes: visible={field=,values={...},
-- playerExists=}, label={field=,values={[value]='text'}} (a key may list values) and
-- dim={value,...}.
local function conditions(field, source, parent, pickers, branch)
    if source.conditions == nil then return end
    local where = 'template field ' .. field.id .. ' conditions'
    assert(type(source.conditions) == 'table', where .. ' must be a table')
    allowed(source.conditions, {visible=true,label=true,dim=true}, where)
    local function sourceField(rule, name)
        if parent == '' then
            text(rule.field, where .. '.' .. name .. '.field')
            assert(rule.field:sub(1,1) ~= '.', where .. '.' .. name .. '.field must be absolute')
        end
        local id = resolveId(parent, rule.field, where .. '.' .. name .. '.field')
        assert(pickers[id], where .. '.' .. name .. '.field must name a picker declared earlier')
        return id
    end
    local visible = source.conditions.visible
    if visible ~= nil then
        assert(type(visible) == 'table', where .. '.visible must be a table')
        allowed(visible, {field=true,values=true,playerExists=true}, where .. '.visible')
        assert((visible.field == nil) == (visible.values == nil),
            where .. '.visible: field and values go together')
        assert(visible.field ~= nil or visible.playerExists ~= nil,
            where .. '.visible needs a field or playerExists')
        assert(visible.playerExists == nil or type(visible.playerExists) == 'boolean',
            where .. '.visible.playerExists must be boolean')
        if visible.field ~= nil then
            local id = sourceField(visible, 'visible')
            assert(not branch or pickers[id] == branch,
                where .. '.visible.field must name a picker in the same variation branch')
            U.array(visible.values, where .. '.visible.values')
            field.visibleWhen, field.visibleValues = id, U.copy(visible.values)
        end
        field.visiblePlayer = visible.playerExists
    end
    local label = source.conditions.label
    if label ~= nil then
        assert(type(label) == 'table', where .. '.label must be a table')
        allowed(label, {field=true,values=true}, where .. '.label')
        field.labelWhen = sourceField(label, 'label')
        field.labelTexts = Contributions.unfold(label.values, where .. '.label.values')
    end
    if source.conditions.dim ~= nil then
        U.array(source.conditions.dim, where .. '.dim')
        field.dim = U.copy(source.conditions.dim)
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
            id=variationIds[name],label=title(name),type='enum',values=domain.values,
            labels=domain.labels,default=source.default,
            description=source.description,
        }
    end
    -- Variations lead the menu in their own group, when the template declares any.
    -- Standalone group ids count the Template group's position even when it is absent,
    -- so generated ids do not depend on whether a template declares variations.
    local groups, absentTemplate = {}, 1
    if #variationFields > 0 then
        groups[1], absentTemplate = {id='Template',label='Template',style='none',fields=variationFields}, 0
    end
    local groupIds, fieldIds, pickers = {Template=true}, {}, {}
    for _, field in ipairs(variationFields) do
        fieldIds[field.id] = true
        if field.type == 'enum' then pickers[field.id] = true end
    end
    for _, sourceGroup in ipairs(menu) do
        assert(type(sourceGroup) == 'table', 'template menu entry must be a table')
        if sourceGroup.fields == nil then
            allowed(sourceGroup, {id=true,label=true,type=true,values=true,default=true,widget=true,
                style=true,description=true,conditions=true}, 'template field')
            text(sourceGroup.id, 'template field id')
            assert(sourceGroup.id:sub(1,1) ~= '.', 'standalone template field id must be absolute')
            local id = resolveId('', sourceGroup.id, 'template field id')
            assert(not fieldIds[id], 'duplicate template field ' .. id)
            fieldIds[id] = true
            text(sourceGroup.label, 'template field label')
            local domain = valueDomain(sourceGroup.values, sourceGroup.type, 'template field ' .. id)
            local field = {id=id,label=sourceGroup.label,type=domain.type,values=domain.values,
                labels=domain.labels,notes=domain.notes,sounds=domain.sounds,min=domain.min,
                max=domain.max,step=domain.step,delta=domain.delta,suffix=domain.suffix,
                default=sourceGroup.default,widget=sourceGroup.widget,style=sourceGroup.style,
                description=sourceGroup.description}
            conditions(field, sourceGroup, '', pickers)
            if field.type == 'enum' then pickers[id] = true end
            local groupId = 'Standalone' .. tostring(#groups + absentTemplate)
            assert(not groupIds[groupId], 'reserved template menu id collision ' .. groupId)
            groupIds[groupId] = true
            groups[#groups + 1] = {id=groupId,label=sourceGroup.label,style='none',fields={field}}
        else
            allowed(sourceGroup, {id=true,label=true,style=true,variation=true,fields=true},
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
            local group = {id=groupId,label=sourceGroup.label,style=sourceGroup.style,fields={}}
            if variationName then
                group.variationSource = variationIds[variationName]
                group.variationValues = {variationValue}
            end
            for _, source in ipairs(sourceGroup.fields) do
                assert(type(source) == 'table', 'template field must be a table')
                allowed(source, {id=true,label=true,type=true,values=true,default=true,widget=true,
                    style=true,description=true,conditions=true}, 'template field')
                local id = resolveId(groupId, source.id, 'template field id')
                assert(not fieldIds[id], 'duplicate template field ' .. id)
                fieldIds[id] = true
                text(source.label, 'template field label')
                local domain = valueDomain(source.values, source.type, 'template field ' .. id)
                local field = {id=id,label=source.label,type=domain.type,values=domain.values,
                    labels=domain.labels,notes=domain.notes,sounds=domain.sounds,min=domain.min,
                    max=domain.max,step=domain.step,delta=domain.delta,suffix=domain.suffix,
                    default=source.default,widget=source.widget,style=source.style,
                    description=source.description}
                local branch = variationName and variationName .. '=' .. tostring(variationValue)
                conditions(field, source, groupId, pickers, branch)
                if field.type == 'enum' then pickers[id] = branch or true end
                group.fields[#group.fields + 1] = field
            end
            groups[#groups + 1] = group
        end
    end
    local declaration = {enabled=true,target='module',groups=groups}
    return declaration, M.normalize(declaration)
end

-- The widgets each type shows as; the first is its default. navigation is an enum row
-- that is never stored.
local WIDGETS = {enum={'picker','tabs','cycler','switch'},integer={'slider'},range={'range'}}
WIDGETS.navigation = WIDGETS.enum
local function widgetOf(field)
    local list = assert(WIDGETS[field.type], 'unsupported provider field type: ' .. tostring(field.type))
    local widget = field.widget or list[1]
    for _, name in ipairs(list) do if name == widget then return widget end end
    error('provider ' .. field.type .. ' takes no ' .. tostring(widget) .. ' widget')
end
local function choice(type) return type == 'enum' or type == 'navigation' end

function M.normalize(declaration)
    assert(type(declaration) == 'table', 'menu must be a table')
    allowed(declaration, {enabled=true,target=true,groups=true}, 'menu')
    assert(type(declaration.enabled)=='boolean', 'menu.enabled must be boolean')
    assert(declaration.target == nil or declaration.target == 'templates' or declaration.target == 'module',
        'menu.target must be templates or module')
    local declaredGroups=declaration.groups or {}
    U.array(declaredGroups, 'settings.groups')
    local groups, byId, fields, titles = {}, {}, {}, 0
    for groupIndex, sourceGroup in ipairs(declaredGroups) do
        assert(type(sourceGroup) == 'table', 'provider group must be a table')
        allowed(sourceGroup, {id=true,label=true,order=true,style=true,fields=true,
            variationSource=true,variationValues=true},
            'provider group')
        identifier(sourceGroup.id, 'provider group id')
        text(sourceGroup.label, 'provider group label')
        assert(sourceGroup.style == nil or sourceGroup.style == 'category' or sourceGroup.style == 'none',
            'provider group style is category or none')
        assert(not byId[sourceGroup.id], 'duplicate provider group ' .. sourceGroup.id)
        local group = {id=sourceGroup.id,label=sourceGroup.label,style=sourceGroup.style,
            order=order(sourceGroup.order,groupIndex),index=groupIndex,
            fields={},variationSource=sourceGroup.variationSource,
            variationValues=sourceGroup.variationValues}
        groups[#groups+1], byId[sourceGroup.id] = group, group
        U.array(sourceGroup.fields, 'provider group fields')
        for fieldIndex, source in ipairs(sourceGroup.fields) do
            assert(type(source) == 'table', 'provider field must be a table')
            allowed(source, {id=true,label=true,type=true,order=true,default=true,values=true,
                labels=true,notes=true,sounds=true,min=true,max=true,step=true,delta=true,
                suffix=true,widget=true,style=true,description=true,visibleWhen=true,visibleValues=true,
                visiblePlayer=true,labelWhen=true,labelTexts=true,dim=true,linkProvider=true}, 'provider field')
            identifier(source.id, 'provider field id'); text(source.label, 'provider field label')
            assert(not fields[source.id], 'duplicate provider field ' .. source.id)
            local field = U.copy(source)
            fields[source.id] = field
            field.group = group.id
            field.order, field.index = order(source.order,fieldIndex), fieldIndex
            field.widget = widgetOf(field)
            if field.style ~= nil then
                assert(field.style == 'title' or field.style == 'category' or field.style == 'notice',
                    'provider field style is title, category or notice')
                if field.style == 'title' then
                    assert(choice(field.type), 'a title row is an enum')
                    titles = titles + 1
                    assert(titles <= 1, 'only one title row per template')
                end
            end
            if field.description ~= nil then text(field.description, 'provider description') end
            if field.linkProvider ~= nil then
                assert(field.type == 'navigation', 'linkProvider requires a navigation field')
                text(field.linkProvider, 'provider link target')
                assert(#field.linkProvider <= 128 and field.linkProvider:match('^[%w_.:-]+$'),
                    'invalid provider link target')
            end
            if field.suffix ~= nil then
                text(field.suffix, 'provider suffix')
                assert(#field.suffix <= 8, 'provider suffix is at most 8 characters')
            end
            if field.visibleWhen ~= nil then identifier(field.visibleWhen, 'provider visibility source') end
            assert((field.visibleWhen == nil) == (field.visibleValues == nil),
                'provider visibility requires both visibleWhen and visibleValues')
            assert(field.visiblePlayer == nil or type(field.visiblePlayer) == 'boolean',
                'provider visiblePlayer must be boolean')
            if field.labelWhen ~= nil then
                identifier(field.labelWhen, 'provider label source')
                assert(type(field.labelTexts) == 'table' and next(field.labelTexts) ~= nil,
                    'provider label texts required')
                for _, label in pairs(field.labelTexts) do text(label, 'provider label text') end
            end
            assert((field.labelWhen == nil) == (field.labelTexts == nil),
                'provider label requires labelWhen and labelTexts')
            assert(field.type == 'range' or field.delta == nil, 'only a range declares delta')
            if field.type == 'range' then
                assert(field.notes == nil and field.sounds == nil and field.dim == nil and field.values == nil
                    and field.labels == nil, 'a range cannot declare choices, notes, sounds or dim')
                field.bounds = M.rangeBounds(field, 'provider range ' .. field.id)
                field.default = M.rangeText(field.bounds, field.default)
                assert(field.default, 'provider range default must be {low, high} within the range')
            elseif field.type == 'integer' then
                assert(field.notes == nil and field.sounds == nil and field.dim == nil,
                    'integer cannot declare notes, sounds or dim')
                assert(field.values == nil and field.labels == nil, 'integer cannot declare choices')
                field.step = field.step or 1
                for _, name in ipairs({'min','max','step','default'}) do
                    assert(finite(field[name]) and field[name] % 1 == 0,
                        'provider integer ' .. name .. ' required')
                end
                assert(field.min < field.max and field.step >= 1 and field.step <= field.max-field.min,
                    'invalid provider integer range/step')
                assert(field.default >= field.min and field.default <= field.max,
                    'provider default outside range')
            else
                assert(field.min == nil and field.max == nil and field.step == nil and field.suffix == nil,
                    'an enum cannot declare an integer range/suffix')
                local count = U.array(field.values, 'provider enum values')
                assert(count >= 2 and count <= 64 and U.array(field.labels, 'provider enum labels') == count,
                    'provider enum requires 2..64 matching choices')
                assert(field.widget ~= 'tabs' or count <= 8, 'provider tabs support at most 8 choices')
                local seen = {}
                for i, value in ipairs(field.values) do
                    assert(finite(value) and not seen[value], 'invalid/duplicate provider choice')
                    seen[value] = true; text(field.labels[i], 'provider choice label')
                end
                assert(field.widget ~= 'switch' or count == 2 and seen[0] and seen[1],
                    'a provider switch takes the values 0 and 1')
                assert(finite(field.default) and seen[field.default], 'provider default must match a choice')
                for name, map in pairs({notes=field.notes, sounds=field.sounds}) do
                    assert(map == nil or type(map) == 'table', 'provider ' .. name .. ' must be a table')
                    for value, entry in pairs(map or {}) do
                        assert(seen[value], 'provider ' .. name .. ' key must be a choice')
                        if name == 'notes' then
                            assert(#text(entry, 'provider choice note') <= 64, 'provider choice note too long')
                        else
                            assert(type(entry) == 'string' and #entry <= 256
                                and (entry == 'none' or entry:match('^/Game/[%w_/%.%-]+$')),
                                'provider choice sound must be a /Game/ event path or none')
                        end
                    end
                end
                for _, value in ipairs(field.dim and field.dim or {}) do
                    assert(seen[value], 'provider dim value must be a choice')
                end
            end
            group.fields[#group.fields+1] = field
        end
    end
    for _, group in ipairs(groups) do
        if group.variationSource then
            identifier(group.variationSource, 'group variation source')
            local source = fields[group.variationSource]
            assert(source and source.type == 'enum', 'group variation source must be an enum')
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
            local labelValues
            if field.labelTexts then
                labelValues = {}
                for value in pairs(field.labelTexts) do labelValues[#labelValues + 1] = value end
                table.sort(labelValues)
            end
            for _, rule in ipairs({{field.visibleWhen, field.visibleValues, 'visibility'},
                {field.labelWhen, labelValues, 'label'}}) do
                local sourceId, matched, kind = rule[1], rule[2], rule[3]
                if sourceId then
                    assert(sourceId ~= field.id, 'provider field cannot depend on itself')
                    local source = fields[sourceId]
                    assert(source and choice(source.type),
                        'provider ' .. kind .. ' source must be an enum in the same template')
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

-- Category settings are shared by every template in that category. The menu
-- edits numeric fields; text values can be edited in config.ini.
function M.normalizeCategory(declaration)
    if declaration == nil then return {}, {}, {} end
    assert(type(declaration) == 'table', 'category settings must be a table')
    allowed(declaration, {groups=true}, 'category settings')
    local declaredGroups = declaration.groups or {}
    U.array(declaredGroups, 'category settings.groups')
    local numericGroups, static, formats, seen, groupIds = {}, {}, {}, {}, {}
    for _, sourceGroup in ipairs(declaredGroups) do
        assert(type(sourceGroup) == 'table', 'category group must be a table')
        allowed(sourceGroup, {id=true,label=true,order=true,style=true,fields=true},
            'category group')
        identifier(sourceGroup.id, 'category group id')
        text(sourceGroup.label, 'category group label')
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
                assert(source.type ~= 'range', 'category settings take no range: ' .. source.id)
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
