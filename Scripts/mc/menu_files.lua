local Layout = require('mc.layout')
local Menu = require('mc.menu')
local Provider = require('mc.provider_settings')
local SafeFile = require('safe_file')
local Ini = require('mc_ini')
local M = {}

local read = SafeFile.read

local function writeChanged(path, content)
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
    return read(path) and assert(loadfile(path, 't', {}))() or nil
end

function M.publish(root, menu)
    -- Reserve IDs durably before any manifest using them is published.
    writeChanged(Layout.prepare(root).catalog, catalogSource(menu.catalog))
end

local accepted = Menu.accepts

local function validText(spec, value)
    return value ~= nil and (pcall(Provider.validateText, spec.format, value))
end

-- The first assignment of each owned key in [Templates]. Unknown or legacy keys are
-- ignored, even when repeated.
local function firstEntries(content, owned)
    local found = {}
    for _, entry in ipairs(Ini.entries(Ini.parse(content), 'Templates')) do
        if owned[entry.key] and not found[entry.key] then found[entry.key] = entry end
    end
    return found
end

-- Configuration never prevents startup. A missing setting is added and an invalid one
-- is rewritten with its default, such as a selected template whose provider is gone.
-- A repeated key or Templates section keeps its first value.
local function ensureConfig(path, rows, textSettings)
    local original = read(path)
    local owned = {}
    for _, row in ipairs(rows) do owned[row.id] = true end
    for settingId in pairs(textSettings or {}) do owned[settingId] = true end
    local present = firstEntries(original or '', owned)
    local changes, missing = {}, {}
    for _, row in ipairs(rows) do
        if not row.action then
            local default = string.format('%.17g', row.default)
            assert(accepted(row, row.default), 'invalid default setting ' .. row.id)
            local entry = present[row.id]
            if not entry then
                missing[#missing + 1] = {row.id, default}
            elseif not accepted(row, tonumber(entry.value)) then
                changes[#changes + 1] = {row.id, default}
            end
        end
    end
    for settingId, spec in pairs(textSettings or {}) do
        Provider.validateText(spec.format, spec.default)
        local entry = present[settingId]
        if not entry then
            missing[#missing + 1] = {settingId, spec.default}
        elseif not validText(spec, entry.value) then
            changes[#changes + 1] = {settingId, spec.default}
        end
    end
    table.sort(missing, function(a, b) return a[1] < b[1] end)
    if #missing == 0 and #changes == 0 and original then return false end
    local output = original or ''
    for _, change in ipairs(changes) do output = Ini.set(output, 'Templates', change[1], change[2]) end
    for _, change in ipairs(missing) do output = Ini.set(output, 'Templates', change[1], change[2]) end
    -- An existing config with nothing owned still gains its [Templates] section.
    if output == '' then output = '[Templates]\n' end
    return writeChanged(path, output)
end
local function readConfigValues(path, textSettings, rows)
    local content = assert(read(path), 'missing installed config: ' .. path)
    -- Invalid values are left out so their defaults apply; a repeated key keeps its first value.
    local known = {}
    for _, row in ipairs(rows) do known[row.id] = row end
    for key in pairs(textSettings or {}) do known[key] = true end
    local values = {}
    for key, entry in pairs(firstEntries(content, known)) do
        if textSettings and textSettings[key] then
            local ok, text = pcall(Provider.validateText, textSettings[key].format, entry.value)
            if ok then values[key] = text end
        else
            local value = tonumber(entry.value)
            local row = known[key]
            if value ~= nil and (row == true or row.action or accepted(row, value)) then
                values[key] = value
            end
        end
    end
    return values
end

M.ensureConfig = ensureConfig
M.readConfigValues = readConfigValues
return M
