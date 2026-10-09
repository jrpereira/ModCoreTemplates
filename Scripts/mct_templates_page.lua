-- ModCoreSettings page hooks for the Templates page. ModCoreSettings runs this in its own
-- Lua state on each menu build, so it reads what MCT last wrote to cache/templates.lua:
-- every loaded template, grouped by module, the active ones marked. It returns menu data;
-- ModCoreSettings names each module from its folder and builds the page.
local ACTIVE, INACTIVE = '✔  Active', '—'

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
    -- note (optional): shown small and muted under the value.
    local function display(group, label, value, note)
        fields[#fields + 1] = {id='MCT_Listed_' .. (#fields + 1), group=group, label=clean(label), default=0,
            readOnly=true, choices={{value=0, label=value, note=note and clean(note:sub(1, 64)) or nil}}}
    end
    local list = read(context.directory)
    if not list then
        groups[1] = {id='Templates', heading=false}
        display('Templates', 'Templates', 'Available once the game has loaded them')
        return {groups=groups, fields=fields}
    end
    -- Templates are chosen where their settings live; the first row opens that place.
    if type(list.slot) == 'string' and list.slot ~= '' then
        groups[1] = {id='Choose', heading=false}
        fields[1] = {id='MCT_Choose', group='Choose', label='Choose the quickslot template', default=0,
            tabs=true, link=clean(list.slot), choices={{value=0, label='Open'}}}
    end
    -- One group per module, in name order; MCT's own templates first.
    local own = context.directory:gsub('[/\\]+$', ''):match('([^/\\]+)$')
    local byModule, modules, names = {}, {}, {}
    for _, template in ipairs(list.templates) do
        local module = template.module ~= '' and template.module or own
        if not byModule[module] then
            byModule[module] = {}; modules[#modules + 1] = module
            names[module] = clean(context.moduleName and context.moduleName(module) or module)
        end
        table.insert(byModule[module], template)
    end
    table.sort(modules, function(a, b)
        if (a == own) ~= (b == own) then return a == own end
        return names[a]:lower() < names[b]:lower()
    end)
    for n, module in ipairs(modules) do
        local group = 'Module' .. n
        groups[#groups + 1] = {id=group, label=names[module]}
        for _, template in ipairs(byModule[module]) do
            display(group, template.name, template.active == true and ACTIVE or INACTIVE,
                template.category and categoryLabel(template.category) or nil)
        end
    end
    return {groups=groups, fields=fields}
end

return {contract=1, menu=menu}
