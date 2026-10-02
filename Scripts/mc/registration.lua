-- Cross-state template registration and installation of the public client.
local M={}
local prefix='MCT.TemplateRegistration.v1.'

local function check(shared)
    assert(shared and type(shared.GetSharedVariable)=='function'
        and type(shared.SetSharedVariable)=='function','UE4SS shared variables unavailable')
end

local function integer(value)
    return type(value)=='number' and value>=0 and value%1==0 and value<9007199254740991
end

local function read(path)
    local file=assert(io.open(path,'rb'))
    local value=file:read('*a')
    file:close()
    return value
end

function M.install(clientPath,sharedPath)
    local client=read(clientPath)
    local current
    local existing=io.open(sharedPath,'rb')
    if existing then current=existing:read('*a');existing:close() end
    if current==client then return false end
    local target=assert(io.open(sharedPath,'wb'))
    local ok,why=target:write(client)
    local closed,closeWhy=target:close()
    assert(ok,why);assert(closed,closeWhy)
    return true
end

function M.publisher(shared,modsRoot)
    check(shared)
    assert(type(modsRoot)=='string' and modsRoot~='','Mods root required')
    local allowed=modsRoot:gsub('\\','/'):gsub('/+$','')..'/'
    local generation,collected
    local self={}
    function self:begin()
        local previous=shared:GetSharedVariable(prefix..'generation') or 0
        assert(integer(previous),'invalid template registration generation')
        generation=previous+1
        shared:SetSharedVariable(prefix..'generation',generation)
        shared:SetSharedVariable(prefix..generation..'.count',0)
        shared:SetSharedVariable(prefix..'active',generation)
        return generation
    end
    function self:collect()
        assert(generation and not collected,'template registrations already collected')
        assert(shared:GetSharedVariable(prefix..'active')==generation,
            'template registration generation was superseded')
        shared:SetSharedVariable(prefix..'active',false)
        local count=shared:GetSharedVariable(prefix..generation..'.count')
        assert(integer(count) and count<=4096,'invalid template registration count')
        local paths={}
        for index=1,count do
            local path=shared:GetSharedVariable(prefix..generation..'.item.'..index)
            assert(type(path)=='string' and #path>0 and #path<=4096,
                'invalid registered template path')
            local canonical=path:gsub('\\','/')
            assert(canonical:sub(1,#allowed)==allowed
                and canonical:match('/Scripts/[%w_%-]+%.lua$'),
                'registered template is outside a mod Scripts directory: '..canonical)
            paths[#paths+1]=path
        end
        collected=true
        return paths
    end
    function self:stop()
        if generation and shared:GetSharedVariable(prefix..'active')==generation then
            shared:SetSharedVariable(prefix..'active',false)
        end
    end
    return self
end

return M
