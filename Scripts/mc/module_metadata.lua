-- A template's module is the mod folder holding its provider file. ModCoreSettings reads
-- that folder's mod.json for the module's name, author, version and icon; MCT passes only
-- the folder on. A template registered from outside a mod folder keeps the module it
-- declares, if any.
--
-- providerId is the module's id, which ModCoreSettings owns: moduleId(folder) asks it, and
-- the folder name stands in when it has none. Generated setting ids include it.
local Menu = require('mc.menu')
local M = {}

function M.apply(template, path, moduleId)
    local root = Menu.moduleRoot(path)
    local folder = root and root:match('([^/]+)$')
    template.module = folder or template.module
    if folder then template.providerId = moduleId and moduleId(folder) or folder end
    return template
end

return M
