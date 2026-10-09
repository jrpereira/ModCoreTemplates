-- The loaded templates and which are active, written for the Templates page. MCT's own
-- Lua state writes it after each commit; ModCoreSettings' state reads it through the
-- page's hooks file (Scripts/mct_templates_page.lua) on each menu build.
local M = {version=1}

-- templates: the registry's {id, template={name, category, module}} entries.
-- state: menu.decodeState's result; a template is active when its category selects it.
-- slot (optional): the address where templates are chosen.
function M.encode(templates, state, slot)
    local out = {'return {version=' .. M.version .. ',slot=' .. string.format('%q', slot or '') .. ',templates={'}
    for _, entry in ipairs(templates) do
        local template = entry.template
        local category = state[template.category]
        local active = category ~= nil and category.selections[entry.id] ~= nil
        out[#out + 1] = string.format('{name=%q,module=%q,category=%q,active=%s},', tostring(template.name),
            tostring(template.module or ''), tostring(template.category), tostring(active))
    end
    out[#out + 1] = '}}'
    return table.concat(out, '\n') .. '\n'
end

return M
