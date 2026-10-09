local Layout = require('mc.layout')
local Menu = require('mc.menu')
local Provider = require('mc.provider_settings')
local SafeFile = require('mc.safe_file')
local M = {}

local function read(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local content = file:read('*a')
    file:close()
    return content
end

local recover = SafeFile.recover

local function writeChanged(path, content)
    recover(path)
    if read(path) == content then return false end
    return SafeFile.write(path, content)
end

local function catalogSource(catalog)
    local lines = {'return {version=1,next=' .. catalog.next .. ',entries={'}
    local keys = {}
    for key in pairs(catalog.entries) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        lines[#lines + 1] = string.format('[%q]=%d,', key, catalog.entries[key])
    end
    lines[#lines + 1] = '},names={'
    keys = {}
    for key in pairs(catalog.names or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        lines[#lines + 1] = string.format('[%q]=%q,', key, catalog.names[key])
    end
    lines[#lines + 1] = '}}\n'
    return table.concat(lines, '\n')
end

function M.readCatalog(root)
    local path = Layout.prepare(root).catalog
    recover(path)
    return read(path) and assert(loadfile(path, 't', {}))() or nil
end

function M.publish(root, menu)
    -- Reserve IDs durably before any manifest using them is published.
    writeChanged(Layout.prepare(root).catalog, catalogSource(menu.catalog))
end

local accepted = Menu.accepts

-- Replace a setting line's value, keeping any trailing ; or # comment.
local function setLine(line, key, value)
    local comment = line and line:match('=[^;#]-(%s*[;#].*)$') or ''
    return key .. '=' .. value .. comment
end

local function validText(spec, value)
    return value ~= nil and (pcall(Provider.validateText, spec.format, value))
end

-- Configuration never prevents startup. A missing setting is added and an invalid one
-- is rewritten with its default, such as a selected template whose provider is gone.
-- A repeated key or Templates section keeps its first value.
local function ensureConfig(path, rows, textSettings)
    recover(path)
    local file = io.open(path, 'rb')
    local existed = file ~= nil
    local content = file and file:read('*a') or ''
    if file then file:close() end
    content = content:gsub('\r\n', '\n'):gsub('\r', '\n')
    local lines = {}; for line in (content .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = line end
    if lines[#lines] == '' then table.remove(lines) end
    local section, first, finish, present = nil, nil, nil, {}
    -- Keys this config owns. Unknown or legacy keys are ignored, even when repeated.
    local owned = {}
    for _, row in ipairs(rows) do owned[row.id] = true end
    for settingId in pairs(textSettings or {}) do owned[settingId] = true end
    for index, line in ipairs(lines) do
        local heading = line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then
            if section == 'Templates' and first and not finish then finish = index end
            section = heading
            if heading == 'Templates' then first = first or index end
        elseif section == 'Templates' then
            local setting = line:match('^%s*([^=;#]+)%s*=')
            if setting then
                setting = setting:match('^%s*(.-)%s*$')
                if owned[setting] and not present[setting] then present[setting] = index end
            end
        end
    end
    if first and not finish then finish = #lines + 1 end
    local missing, repaired = {}, false
    for _, row in ipairs(rows) do
        if not row.action then
            local default = row.default
            assert(accepted(row, default), 'invalid default setting ' .. row.id)
            local index = present[row.id]
            if not index then
                missing[#missing + 1] = row.id .. '=' .. string.format('%.17g', default)
            else
                local raw = lines[index]:match('=%s*([^;#]+)')
                if not accepted(row, raw and tonumber(raw:match('^%s*(.-)%s*$'))) then
                    lines[index] = setLine(lines[index], row.id, string.format('%.17g', default)); repaired = true
                end
            end
        end
    end
    for settingId, spec in pairs(textSettings or {}) do
        local default = spec.default
        Provider.validateText(spec.format, default)
        local index = present[settingId]
        if not index then
            missing[#missing + 1] = settingId .. '=' .. default
        else
            local raw = lines[index]:match('=%s*([^;#]*)')
            if not validText(spec, raw and raw:match('^%s*(.-)%s*$')) then
                lines[index] = setLine(lines[index], settingId, default); repaired = true
            end
        end
    end
    table.sort(missing)
    if #missing == 0 and existed and not repaired then return false end
    if not first then
        if #lines > 0 and lines[#lines] ~= '' then lines[#lines + 1] = '' end
        lines[#lines + 1] = '[Templates]'
        for _, line in ipairs(missing) do lines[#lines + 1] = line end
    else
        for index = #missing, 1, -1 do table.insert(lines, finish, missing[index]) end
    end
    local output = table.concat(lines, '\n') .. '\n'
    return writeChanged(path, output)
end
local function readConfigValues(path, textSettings, rows)
    recover(path)
    local file = assert(io.open(path, 'rb'), 'missing installed config: ' .. path)
    local content = file:read('*a'); file:close()
    -- Invalid values are left out so their defaults apply; a repeated key keeps its first value.
    local values, section, seen = {}, nil, {}
    local known = {}
    for _, row in ipairs(rows) do known[row.id] = row end
    for key in pairs(textSettings or {}) do known[key] = true end
    for line in (content:gsub('\r\n', '\n'):gsub('\r', '\n') .. '\n'):gmatch('(.-)\n') do
        local heading = line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then section = heading
        elseif section == 'Templates' then
            local key, value = line:match('^%s*([^=;#]+)%s*=%s*([^;#]*)')
            if key then key = key:match('^%s*(.-)%s*$') end
            if key and known[key] and not seen[key] then
                seen[key] = true
                value = value:match('^%s*(.-)%s*$')
                if textSettings and textSettings[key] then
                    local ok, text = pcall(Provider.validateText, textSettings[key].format, value)
                    if ok then values[key] = text end
                else
                    value = tonumber(value)
                    local row = known[key]
                    if value ~= nil and (row == true or row.action or accepted(row, value)) then
                        values[key] = value
                    end
                end
            end
        end
    end
    return values
end

M.ensureConfig = ensureConfig
M.readConfigValues = readConfigValues
return M
