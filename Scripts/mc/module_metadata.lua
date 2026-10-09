-- A template's module is the mod folder holding its provider file. ModCoreSettings reads
-- that folder's mod.json for the module's name, author, version and icon; MCT passes only
-- the folder on. A template registered from outside a mod folder keeps the module it
-- declares, if any.
local Menu = require('mc.menu')
local M = {}

function M.apply(template, path)
    local root = Menu.moduleRoot(path)
    template.module = root and root:match('([^/]+)$') or template.module
    return template
end

return M
