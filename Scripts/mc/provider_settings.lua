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

function M.normalize(declaration)
    assert(type(declaration) == 'table', 'menu must be a table')
    allowed(declaration, {enabled=true,target=true,groups=true,fields=true}, 'menu')
    assert(type(declaration.enabled)=='boolean', 'menu.enabled must be boolean')
    assert(declaration.target == nil or declaration.target == 'templates' or declaration.target == 'module',
        'menu.target must be templates or module')
    local declaredGroups=declaration.groups or {}
    local declaredFields=declaration.fields or {}
    U.array(declaredGroups, 'settings.groups')
    U.array(declaredFields, 'settings.fields')
    local groups, byId, fields, headerPickers = {}, {}, {}, 0
    for index, source in ipairs(declaredGroups) do
        assert(type(source) == 'table', 'provider group must be a table')
        allowed(source, {id=true,label=true,level=true,order=true,heading=true}, 'provider group')
        identifier(source.id, 'provider group id'); text(source.label, 'provider group label'); level(source.level)
        assert(source.heading == nil or type(source.heading) == 'boolean',
            'provider group heading must be boolean')
        assert(not byId[source.id], 'duplicate provider group ' .. source.id)
        local g = {id=source.id,label=source.label,level=source.level or 4,heading=source.heading,
            order=order(source.order,index),index=index,fields={}}
        groups[#groups+1], byId[source.id] = g, g
    end
    for index, source in ipairs(declaredFields) do
        assert(type(source) == 'table', 'provider field must be a table')
        allowed(source, {id=true,label=true,group=true,type=true,order=true,default=true,values=true,
            labels=true,min=true,max=true,step=true,suffix=true,tab=true,level=true,description=true,
            after=true,visibleWhen=true,visibleValues=true,tabNavigation=true,
            linkProvider=true}, 'provider field')
        identifier(source.id, 'provider field id'); text(source.label, 'provider field label')
        level(source.level, source.type == 'picker' or source.type == 'navigation')
        if source.level == 1 then
            headerPickers = headerPickers + 1
            assert(headerPickers <= 1, 'only one level-1 picker per template')
        end
        assert(not fields[source.id], 'duplicate provider field ' .. source.id)
        fields[source.id] = source
        local group = assert(byId[source.group], 'undeclared provider group: ' .. tostring(source.group))
        local field = U.copy(source)
        field.order, field.index = order(source.order,index), index
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
        assert(field.after == nil, 'field.after is unsupported')
        assert(field.tab == nil or type(field.tab) == 'boolean', 'provider tab must be boolean')
        assert(field.tabNavigation == nil or (field.type == 'navigation'
            and field.tab == true and field.tabNavigation == 1),
            'tabNavigation=1 requires a navigation tab')
        if field.type == 'integer' then
            assert(field.values == nil and field.labels == nil and not field.tab, 'integer cannot declare choices/tabs')
            field.step = field.step or 1
            for _, name in ipairs({'min','max','step','default'}) do
                assert(finite(field[name]) and field[name] % 1 == 0, 'provider integer ' .. name .. ' required')
            end
            assert(field.min < field.max and field.step >= 1 and field.step <= field.max-field.min,
                'invalid provider integer range/step')
            assert(field.default >= field.min and field.default <= field.max, 'provider default outside range')
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
    for _, group in ipairs(groups) do
        for _, field in ipairs(group.fields) do
            if field.visibleWhen then
                assert(field.visibleWhen ~= field.id, 'provider field cannot hide itself')
                local source = fields[field.visibleWhen]
                assert(source and (source.type == 'picker' or source.type == 'navigation'),
                    'provider visibility source must be a picker in the same template')
                local count = U.array(field.visibleValues, 'provider visibility values')
                assert(count > 0, 'provider visibility values must not be empty')
                local choices, seen = {}, {}
                for _, value in ipairs(source.values) do choices[value] = true end
                for _, value in ipairs(field.visibleValues) do
                    assert(finite(value) and choices[value] and not seen[value],
                        'provider visibility value must be a distinct source choice')
                    seen[value] = true
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
    allowed(declaration, {groups=true,fields=true}, 'category settings')
    local declaredGroups = declaration.groups or {}
    local declaredFields = declaration.fields or {}
    U.array(declaredGroups, 'category settings.groups')
    U.array(declaredFields, 'category settings.fields')
    local groups = #declaredGroups > 0 and U.copy(declaredGroups)
        or {{id='Shared', label='Shared', level=4}}
    local defaultGroup = groups[1].id
    local numeric, static, formats, seen = {}, {}, {}, {}
    for _, source in ipairs(declaredFields) do
        assert(type(source) == 'table', 'category field must be a table')
        identifier(source.id, 'category field id')
        assert(not seen[source.id], 'duplicate category field ' .. source.id)
        seen[source.id] = true
        if source.type == 'text' then
            allowed(source, {id=true,type=true,default=true,order=true,format=true}, 'category text field')
            assert(type(source.default) == 'string', 'category text default must be a string')
            M.validateText(source.format, source.default)
            static[source.id] = source.default
            formats[source.id] = source.format or false
        else
            local field = U.copy(source)
            field.group = field.group or defaultGroup
            numeric[#numeric + 1] = field
        end
    end
    if #numeric == 0 then return {}, static, formats end
    return M.normalize({enabled=true,target='templates',groups=groups,fields=numeric}), static, formats
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
