-- The settings reference tool regenerates the fixture's committed SETTINGS.md and
-- MOD_SETTINGS.txt unchanged, and --check fails when one is out of date.
local lua = arg[-1]
local fixture = 'tests/fixtures/SettingsExample'
local function check()
    return os.execute(lua .. ' tools/settings_reference.lua ' .. fixture .. ' --check 2>/dev/null')
end
assert(check(), 'fixture settings reference is out of date; regenerate it')
local path = fixture .. '/MOD_SETTINGS.txt'
local file = assert(io.open(path, 'rb'))
local original = file:read('a')
file:close()
file = assert(io.open(path, 'wb'))
file:write(original .. 'stale\n')
file:close()
local stale = check()
file = assert(io.open(path, 'wb'))
file:write(original)
file:close()
assert(not stale, '--check accepted a stale MOD_SETTINGS.txt')
print('PASS: settings reference')
