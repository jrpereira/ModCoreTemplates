-- ModCoreSettings page hooks for the Templates page. ModCoreSettings runs this in its own
-- Lua state on each menu build, so it reads what MCT last wrote to cache/templates.lua:
-- one group per category with templates, a subgroup per module supplying them, each
-- template marked when active. It returns menu data; ModCoreSettings builds the page, and
-- MCT publishes its rows into ModCore Settings' Templates tab (settings:templates).
-- Menu text cannot be empty or space-edged, so a blank value is a no-break space.
local ACTIVE, BLANK = 'Active', '\u{A0}'

local function read(directory)
    local path = directory:gsub('[/\\]+$', '') .. '/Scripts/cache/templates.lua'
    local chunk = loadfile(path, 't', {})
    if not chunk then return nil end
    local ok, list = pcall(chunk)
    return ok and type(list) == 'table' and type(list.templates) == 'table' and list or nil
end

-- Menu text has no separators, controls or edge spaces.
local function clean(value)
    local text = tostring(value):gsub('[|;%[%]%c]', ' '):match('^%s*(.-)%s*$')
    return text ~= '' and text or '?'
end

-- 'player.quickslots' reads 'Player Quickslots'.
local function categoryLabel(category)
    return (clean(category):gsub('[._]', ' '):gsub('(%a)(%w*)', function(first, rest)
        return first:upper() .. rest
    end))
end

local function menu(context)
    local groups, fields = {}, {}
    local function display(id, group, label, value)
        fields[#fields + 1] = {id=id, group=group, label=clean(label), default=0, readOnly=true,
            choices={{value=0, label=value}}}
    end
    local list = read(context.directory)
    if not list then
        groups[1] = {id='Templates', heading=false}
        display('MCT_Listed_None', 'Templates', 'Templates', 'Available once the game has loaded them')
        return {groups=groups, fields=fields}
    end
    -- One group per category with templates, in name order; in it, one subgroup per module
    -- supplying them, MCT's own first, then by the module's name; templates in load order.
    local own = context.directory:gsub('[/\\]+$', ''):match('([^/\\]+)$')
    local byCategory, used = {}, {}
    -- A row's id is its template's place in the list.
    for index, template in ipairs(list.templates) do
        template.listed = 'MCT_Listed_' .. index
        local category = tostring(template.category)
        if not byCategory[category] then byCategory[category] = {modules={}, byModule={}}; used[#used + 1] = category end
        local entry = byCategory[category]
        local module = template.module ~= '' and template.module or own
        if not entry.byModule[module] then entry.byModule[module] = {}; entry.modules[#entry.modules + 1] = module end
        table.insert(entry.byModule[module], template)
    end
    table.sort(used)
    local names = {}
    local function name(module)
        names[module] = names[module] or clean(context.moduleName and context.moduleName(module) or module)
        return names[module]
    end
    for n, category in ipairs(used) do
        local entry, subgroups = byCategory[category], {}
        groups[#groups + 1] = {id='Category' .. n, label=categoryLabel(category), groups=subgroups}
        table.sort(entry.modules, function(a, b)
            if (a == own) ~= (b == own) then return a == own end
            return name(a):lower() < name(b):lower()
        end)
        for m, module in ipairs(entry.modules) do
            local group = 'Category' .. n .. '_' .. m
            subgroups[#subgroups + 1] = {id=group, label=name(module)}
            for _, template in ipairs(entry.byModule[module]) do
                display(template.listed, group, template.name, template.active == true and ACTIVE or BLANK)
            end
        end
    end
    return {groups=groups, fields=fields}
end

return {contract=1, menu=menu}
