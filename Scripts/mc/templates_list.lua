-- The loaded templates and which are active, written for the Templates page. MCT's own
-- Lua state writes it after each commit; ModCoreSettings' state reads it through the
-- page's hooks file (Scripts/mct_templates_page.lua) on each menu build.
local M = {version=1}

-- templates: the registry's {id, template={label, category, module}} entries.
-- state: menu.decodeState's result; a template is active when its category selects it.
function M.encode(templates, state)
    local out = {'return {version=' .. M.version .. ',templates={'}
    for _, entry in ipairs(templates) do
        local template = entry.template
        local category = state[template.category]
        local active = category ~= nil and category.selections[entry.id] ~= nil
        out[#out + 1] = string.format('{label=%q,module=%q,category=%q,active=%s},', tostring(template.label),
            tostring(template.module or ''), tostring(template.category), tostring(active))
    end
    out[#out + 1] = '}}'
    return table.concat(out, '\n') .. '\n'
end

return M
