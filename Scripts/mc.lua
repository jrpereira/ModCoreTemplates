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

local function template(name, defaults)
    assert(type(name) == 'string', 'MC template filename required')
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
    local caller = assert(debug.getinfo(2, 'S'), 'MC template caller unavailable')
    local source = assert(caller.source:match('^@(.+)$'),
        'MC.template must be called from a Lua file')
    local folder = assert(source:match('^(.*)[/\\][^/\\]+$'),
        'MC template caller has no directory')
    local path = folder .. '/' .. filename
    local chunk = assert(loadfile(path, 't'))
    local value = chunk()
    assert(type(value) == 'table', path .. ': expected a template table')
    return TemplateDefaults.apply(value,defaults)
end

local function registerTemplate(name,...)
    assert(type(name)=='string','MC template name required')
    assert(select('#',...)==0,'MC.registerTemplate metadata belongs in the template or module manifest')
    local filename
    if name:sub(-4)=='.lua' then
        assert(name:match('^[%w_%-]+%.lua$'),
            'MC template filename must be a simple Lua filename')
        filename=name
    else
        assert(name:match('^[%w_%-]+$'),'MC template name must be a simple file stem')
        filename='mc_'..name..'.lua'
    end
    local caller=assert(debug.getinfo(2,'S'),'MC template registrar unavailable')
    local source=assert(caller.source:match('^@(.+)$'),
        'MC.registerTemplate must be called from a Lua file')
    local folder=assert(source:match('^(.*)[/\\][^/\\]+$'),
        'MC template registrar has no directory')
    assert(type(templateRegistrar)=='function','MCT template registration is unavailable')
    return templateRegistrar(folder..'/'..filename)
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
