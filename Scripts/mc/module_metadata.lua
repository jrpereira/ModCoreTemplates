-- A template's module is the mod folder holding its provider file. ModCoreSettings reads
-- that folder's mod.json for the module's name, author, version and icon; MCT passes only
-- the folder on. A template registered from outside a mod folder keeps the module it
-- declares, if any.
--
-- providerId is the module's id, which ModCoreSettings owns: moduleId(folder) asks it, and
-- the folder name stands in when it has none. Generated setting ids include it.
--
-- Template ids are unique within a module only, so a template from a mod folder takes
-- its module's id as prefix: template.id becomes '<providerId>_<id>' and template.localId
-- keeps the id the provider declared.
local Menu = require('mc.menu')
local M = {}

function M.apply(template, path, moduleId)
    local root = Menu.moduleRoot(path)
    local folder = root and root:match('([^/]+)$')
    template.module = folder or template.module
    if folder then
        -- localId is set only here, so a table seen before keeps its declared id.
        local localId = template.localId or template.id
        assert(type(localId) == 'string' and localId:match('^%a[%w_.]*$'),
            'template.id is required: a letter, then letters, digits, _ or .')
        template.providerId = moduleId and moduleId(folder) or folder
        template.localId, template.id = localId, template.providerId .. '_' .. localId
    end
    return template
end

return M
