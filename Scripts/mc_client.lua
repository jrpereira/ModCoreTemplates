-- Public MCT client installed as Mods/shared/mc.lua.
-- This file must stay dependency-free because every provider loads it in its own Lua state.
local M={version=1}
local prefix='MCT.TemplateRegistration.v1.'

local function integer(value)
    return type(value)=='number' and value>=0 and value%1==0 and value<9007199254740991
end

function M.addTemplate(name,...)
    assert(type(name)=='string','MC template name required')
    assert(select('#',...)==0,'MC.addTemplate metadata belongs in the template or module manifest')
    local filename
    if name:sub(-4)=='.lua' then
        assert(name:match('^[%w_%-]+%.lua$'),'MC template filename must be a simple Lua filename')
        filename=name
    else
        assert(name:match('^[%w_%-]+$'),'MC template name must be a simple file stem')
        filename='mc_'..name..'.lua'
    end
    local caller=assert(debug.getinfo(2,'S'),'MC template registrar unavailable')
    local source=assert(caller.source:match('^@(.+)$'),'MC.addTemplate must be called from a Lua file')
    local folder=assert(source:match('^(.*)[/\\][^/\\]+$'),'MC template registrar has no directory')
    assert(ModRef and type(ModRef.GetSharedVariable)=='function'
        and type(ModRef.SetSharedVariable)=='function','MCT template registration transport unavailable')
    local generation=ModRef:GetSharedVariable(prefix..'active')
    assert(integer(generation) and generation>0,'MCT template registration is not open')
    local count=ModRef:GetSharedVariable(prefix..generation..'.count') or 0
    assert(integer(count) and count<4096,'invalid MCT template registration count')
    local index=count+1
    ModRef:SetSharedVariable(prefix..generation..'.item.'..index,folder..'/'..filename)
    ModRef:SetSharedVariable(prefix..generation..'.count',index)
    return true
end

return M
