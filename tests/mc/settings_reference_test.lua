-- The settings reference tool regenerates the fixture's committed SETTINGS.md and
-- MOD_SETTINGS.txt unchanged, and --check fails when one is out of date. The stale case
-- runs on a copy, so the tracked fixture is never written.
local lua = arg[-1]
local fixture = 'tests/fixtures/SettingsExample'
local function check(folder)
    return os.execute(lua .. ' tools/settings_reference.lua "' .. folder .. '" --check 2>/dev/null')
end
assert(check(fixture), 'fixture settings reference is out of date; regenerate it')
-- The copy keeps the folder name, which generated setting ids include.
local base = assert(os.getenv('MCT_TEST_DIR'), 'MCT_TEST_DIR required') .. '/settings-reference'
local copy = base .. '/SettingsExample'
assert(os.execute('rm -rf "' .. base .. '" && mkdir -p "' .. base .. '" && cp -R "' .. fixture .. '" "' .. base .. '/"'))
assert(check(copy), 'an unchanged copy passes --check')
local file = assert(io.open(copy .. '/MOD_SETTINGS.txt', 'ab'))
file:write('stale\n')
file:close()
assert(not check(copy), '--check accepted a stale MOD_SETTINGS.txt')
print('PASS: settings reference')
