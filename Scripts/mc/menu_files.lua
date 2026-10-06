local Layout = require('mc.layout')
local Provider = require('mc.provider_settings')
local M = {}

local function read(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local content = file:read('*a')
    file:close()
    return content
end

local function recover(path)
    local backup,temporary=path..'.mc.bak',path..'.mc.tmp'
    if read(backup)~=nil then
        if read(path)==nil then
            assert(os.rename(backup,path),'could not restore interrupted menu backup: '..path)
        else
            -- The replacement was published; only backup removal was interrupted.
            assert(os.remove(backup),'could not clear completed menu backup: '..backup)
        end
    end
    if read(temporary)~=nil then
        -- A temporary file was never published. Recreate it from current data.
        assert(os.remove(temporary),'could not clear interrupted menu temporary: '..temporary)
    end
end

local function writeChanged(path, content)
    recover(path)
    local old = read(path)
    if old == content then return false end
    local temporary = path .. '.mc.tmp'
    assert(not read(temporary), 'stale temporary menu file: ' .. temporary)
    local file = assert(io.open(temporary, 'wb'))
    assert(file:write(content))
    assert(file:close())
    local backup = path .. '.mc.bak'
    if old then
        assert(not read(backup), 'stale backup menu file: ' .. backup)
        local moved, why = os.rename(path, backup)
        if not moved then os.remove(temporary); error(why) end
    end
    local renamed, why = os.rename(temporary, path)
    if not renamed then
        if old then assert(os.rename(backup, path), 'could not restore previous menu file') end
        os.remove(temporary)
        error(why)
    end
    if old then assert(os.remove(backup)) end
    return true
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
    local paths = Layout.prepare(root)
    -- Reserve IDs durably before any manifest using them is published.
    writeChanged(paths.catalog, catalogSource(menu.catalog))
    -- A leftover mod_settings.ini would claim the ModCoreTemplates id in the menu
    -- and make ModCoreSettings skip every MCT page.
    for _, path in ipairs(paths.retired) do
        recover(path)
        if read(path) ~= nil then assert(os.remove(path), 'could not remove retired menu file: ' .. path) end
    end
end

local function accepted(row, value)
    if type(value) ~= 'number' or value ~= value then return false end
    if row.Type == 'integer' then
        return value % 1 == 0 and value >= row.Minimum and value <= row.Maximum
    end
    for candidate in row.PresetValues:gmatch('[^|]+') do
        if value == tonumber(candidate) then return true end
    end
    return false
end

local function validText(spec, value)
    return value ~= nil and (pcall(Provider.validateText, spec.format, value))
end

-- Configuration never prevents startup. A missing setting is added and an invalid one
-- is rewritten with its default, such as a selected template whose provider is gone.
-- A repeated key or Templates section keeps its first value.
local function ensureConfig(path, rows, textSettings, initialValues)
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
    for _, row in ipairs(rows) do owned[row.Id] = true end
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
    local function initial(id, fallback, valid)
        local value = initialValues and initialValues[id]
        if value ~= nil and valid(value) then return value end
        return fallback
    end
    for _, row in ipairs(rows) do
        if row.mcNavigation ~= 1 then
            local valid = function(value) return accepted(row, value) end
            local default = initial(row.Id, tonumber(row.Default), valid)
            assert(valid(default), 'invalid default setting ' .. row.Id)
            local index = present[row.Id]
            if not index then
                missing[#missing + 1] = row.Id .. '=' .. string.format('%.17g', default)
            else
                local raw = lines[index]:match('=%s*([^;#]+)')
                if not valid(raw and tonumber(raw:match('^%s*(.-)%s*$'))) then
                    lines[index] = row.Id .. '=' .. string.format('%.17g', default); repaired = true
                end
            end
        end
    end
    for settingId, spec in pairs(textSettings or {}) do
        local valid = function(value) return validText(spec, value) end
        local default = initial(settingId, spec.default, valid)
        Provider.validateText(spec.format, default)
        local index = present[settingId]
        if not index then
            missing[#missing + 1] = settingId .. '=' .. default
        else
            local raw = lines[index]:match('=%s*([^;#]*)')
            if not valid(raw and raw:match('^%s*(.-)%s*$')) then
                lines[index] = settingId .. '=' .. default; repaired = true
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
    for _, row in ipairs(rows) do known[row.Id] = row end
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
                    if value ~= nil and (row == true or row.mcNavigation == 1 or accepted(row, value)) then
                        values[key] = value
                    end
                end
            end
        end
    end
    return values
end

-- Set numeric keys in one section, adding the section when missing, or remove keys whose
-- change is false. Other lines, sections and line endings are kept. Returns whether the
-- file changed, or nil when it is missing, which is left alone.
local function editValues(path, changes, name)
    name = name or 'Templates'
    recover(path)
    local file = io.open(path, 'rb')
    if not file then return nil end
    local content = file:read('*a'); file:close()
    local eol = content:find('\r\n', 1, true) and '\r\n' or '\n'
    content = content:gsub('\r\n', '\n'):gsub('\r', '\n')
    local lines, out, pending, section, finish = {}, {}, {}, nil, nil
    for line in (content .. '\n'):gmatch('(.-)\n') do lines[#lines + 1] = line end
    if lines[#lines] == '' then table.remove(lines) end
    for key, value in pairs(changes) do if value ~= false then pending[key] = value end end
    local function value(number) return string.format('%.17g', number) end
    for _, line in ipairs(lines) do
        local heading = line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then
            if section == name then finish = #out end
            section = heading
            out[#out + 1] = line
        else
            local key = section == name and line:match('^%s*([^=;#]+)%s*=')
            key = key and key:match('^%s*(.-)%s*$')
            if key and changes[key] == false then
            elseif key and changes[key] ~= nil then
                out[#out + 1] = key .. '=' .. value(changes[key]); pending[key] = nil
            else out[#out + 1] = line end
        end
    end
    if section == name then finish = #out end
    local missing = {}
    for key, number in pairs(pending) do missing[#missing + 1] = key .. '=' .. value(number) end
    table.sort(missing)
    if #missing > 0 then
        if not finish then
            if #out > 0 and out[#out] ~= '' then out[#out + 1] = '' end
            out[#out + 1] = '[' .. name .. ']'; finish = #out
        end
        for index = #missing, 1, -1 do table.insert(out, finish + 1, missing[index]) end
    end
    return writeChanged(path, table.concat(out, eol) .. eol)
end

-- Raw key/value text of one section; empty when the file or section is missing.
local function readSection(path, name)
    recover(path)
    local values, section = {}, nil
    local file = io.open(path, 'rb')
    if not file then return values end
    local content = file:read('*a'); file:close()
    for line in (content:gsub('\r\n', '\n'):gsub('\r', '\n') .. '\n'):gmatch('(.-)\n') do
        local heading = line:match('^%s*%[([^%]]+)%]%s*$')
        if heading then section = heading
        elseif section == name then
            local key, value = line:match('^%s*([^=;#]+)%s*=%s*([^;#]*)')
            if key then values[key:match('^%s*(.-)%s*$')] = value:match('^%s*(.-)%s*$') end
        end
    end
    return values
end

M.ensureConfig = ensureConfig
M.readConfigValues = readConfigValues
M.editValues = editValues
M.readSection = readSection
M.accepted = accepted
return M
