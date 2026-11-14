-- Public helpers available to templates loaded in MCT's Lua state.
local Objects = require('mc.objects')
local TemplateDefaults=require('mc.template_defaults')

local modules = {objects = Objects}
local templateRegistrar

local function load(name)
    assert(type(name) == 'string', 'MC helper name required')
    if name == 'objects' then return Objects end
    if name == 'widget' then
        if not modules.widget then modules.widget = require('mc.widget') end
        return modules.widget
    end
    error('unknown MC helper: ' .. name, 2)
end

-- The sibling file a call names: 'x.lua' as given, or a stem 'x' as 'mc_x.lua', in
-- the folder of the file that called template or registerTemplate.
local function siblingPath(name, label)
    assert(type(name) == 'string', 'MC template name required')
    local filename
    if name:sub(-4) == '.lua' then
        assert(name:match('^[%w_%-]+%.lua$'),
            'MC template filename must be a simple Lua filename')
        filename = name
    else
        assert(name:match('^[%w_%-]+$'),
            'MC template name must be a simple file stem')
        filename = 'mc_' .. name .. '.lua'
    end
    -- Level 3: the caller of template or registerTemplate.
    local caller = assert(debug.getinfo(3, 'S'), 'MC template caller unavailable')
    local source = assert(caller.source:match('^@(.+)$'),
        label .. ' must be called from a Lua file')
    local folder = assert(source:match('^(.*)[/\\][^/\\]+$'),
        'MC template caller has no directory')
    return folder .. '/' .. filename
end

local function template(name, defaults)
    local path = siblingPath(name, 'MC.template')
    local chunk = assert(loadfile(path, 't'))
    local value = chunk()
    assert(type(value) == 'table', path .. ': expected a template table')
    return TemplateDefaults.apply(value,defaults)
end

local function registerTemplate(name,...)
    assert(select('#',...)==0,'MC.registerTemplate metadata belongs in the template or module manifest')
    local path = siblingPath(name, 'MC.registerTemplate')
    assert(type(templateRegistrar)=='function','MCT template registration is unavailable')
    return templateRegistrar(path)
end

local function setTemplateRegistrar(registrar)
    assert(type(registrar)=='function','MC template registrar must be a function')
    templateRegistrar=registrar
end

return setmetatable({load=load,template=template,registerTemplate=registerTemplate,
    _setTemplateRegistrar=setTemplateRegistrar}, {
    __index = Objects,
    __call = function(_, name) return load(name) end,
})
