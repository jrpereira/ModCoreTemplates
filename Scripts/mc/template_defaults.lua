local U = require('mc.util')
local M = {}
local base = {settings={}, enabled=true, menu={}, variations={}, menuTarget='module'}

function M.apply(template, defaults)
    assert(type(template)=='table','MC template definition must be a table')
    assert(defaults==nil or type(defaults)=='table','MC template defaults must be a table')
    local result=U.copy(base)
    for key,value in pairs(defaults or {}) do result[key]=U.copy(value) end
    for key,value in pairs(template) do result[key]=U.copy(value) end
    return result
end

return M
