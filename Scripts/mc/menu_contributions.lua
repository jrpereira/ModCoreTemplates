-- Public client for contributing menu pages through ModCoreSettings.
-- Consumers may vendor this file unchanged. It only writes data files and one shared
-- variable per contributor; ModCoreSettings reads them while building the menu.
local M={version=1,contract=1}
local PREFIX='MCS_MenuContrib_v1_'
M.prefix,M.index=PREFIX,PREFIX..'index'
local MAX_PAGES,MAX_MANIFEST=256,262144
local PAGE_KEYS={id=true,name=true,author=true,version=true,description=true,manifest=true,
    configDirectory=true,visible=true,under=true,attach=true,group=true}
local DESCRIPTOR_KEYS={id=true,name=true,author=true,version=true,description=true,manifestFile=true,
    configDirectory=true,visible=true,under=true,attach=true,group=true}

function M.hex(value)
    return (value:gsub('.',function(c) return string.format('%02x',c:byte()) end))
end

local function line(value,limit,name)
    assert(type(value)=='string' and value~='' and #value<=limit and not value:find('%c'),
        'invalid '..name)
end
local function optional(value,limit,name)
    if value~=nil then line(value,limit,name) end
end
local function absolute(value)
    return value:match('^/') or value:match('^%a:[/\\]') or value:match('^[/\\][/\\]')
end

-- Structural validation shared by publishers and ModCoreSettings. Settings manifests are
-- checked by ModCoreSettings when it builds the menu.
local function check(contributor,contribution)
    line(contributor,128,'contributor id')
    assert(type(contribution)=='table' and type(contribution.pages)=='table','contribution needs pages')
    for key in pairs(contribution) do assert(key=='pages','unknown contribution field '..tostring(key)) end
    local pages=contribution.pages
    assert(#pages<=MAX_PAGES,'too many pages')
    for key in pairs(pages) do
        assert(math.type(key)=='integer' and key>=1 and key<=#pages,'pages must be a list')
    end
    local seen={}
    for n,page in ipairs(pages) do
        local where='page '..n
        assert(type(page)=='table',where..' must be a table')
        for key in pairs(page) do assert(PAGE_KEYS[key],where..': unknown field '..tostring(key)) end
        line(page.id,128,where..' id')
        assert(page.id==contributor or page.id:sub(1,#contributor+1)==contributor..'.',
            where..': id '..page.id..' is not owned by '..contributor)
        assert(not seen[page.id],'duplicate page id '..page.id)
        line(page.name,200,where..' name')
        optional(page.author,120,where..' author')
        optional(page.version,64,where..' version')
        assert(page.description==nil or (type(page.description)=='string' and #page.description<=4096
            and not page.description:find('%z')),'invalid '..where..' description')
        assert(page.visible==nil or type(page.visible)=='boolean','invalid '..where..' visible')
        assert(page.group==nil or page.group=='module','invalid '..where..' group')
        if page.manifest~=nil then
            assert(type(page.manifest)=='string' and #page.manifest<=MAX_MANIFEST
                and not page.manifest:find('%z'),'invalid '..where..' manifest')
            line(page.configDirectory,1024,where..' configDirectory')
            assert(absolute(page.configDirectory),where..': configDirectory must be absolute')
        else
            assert(page.configDirectory==nil,where..': configDirectory needs a manifest')
        end
        assert(page.under==nil or page.attach==nil,where..': under and attach are exclusive')
        if page.under~=nil then
            line(page.under,128,where..' under')
            assert(seen[page.under],where..': under must name an earlier page')
        end
        if page.attach~=nil then
            line(page.attach,200,where..' attach')
            assert(not page.attach:find('[/\\]'),where..': attach must be a folder name')
        end
        seen[page.id]=true
    end
    return true
end
M.check=check

function M.validate(contributor,contribution)
    local ok,err=pcall(check,contributor,contribution)
    return ok,not ok and tostring(err) or nil
end

local function escape(value)
    return (value:gsub('\\','\\\\'):gsub('\n','\\n'):gsub('\r','\\r'))
end
local function unescape(value)
    return (value:gsub('\\(.)',function(c)
        return assert(({n='\n',r='\r',['\\']='\\'})[c],'invalid escape')
    end))
end

function M.descriptorName(generation) return 'mcs_menu.'..generation..'.ini' end
function M.manifestName(generation,n) return 'mcs_menu.'..generation..'.'..n..'.ini' end

-- Returns descriptor text and the manifest files it names.
function M.encode(contributor,generation,contribution)
    check(contributor,contribution)
    local out={'[Contribution]','contract='..M.contract,'id='..contributor,'generation='..generation}
    local files={}
    for n,page in ipairs(contribution.pages) do
        out[#out+1]='[Page.'..n..']'
        for _,key in ipairs({'id','name','author','version','description','configDirectory','under','attach','group'}) do
            if page[key]~=nil then out[#out+1]=key..'='..escape(page[key]) end
        end
        if page.visible~=nil then out[#out+1]='visible='..(page.visible and '1' or '0') end
        if page.manifest then
            local name=M.manifestName(generation,#files+1)
            files[#files+1]={name=name,content=page.manifest}
            out[#out+1]='manifestFile='..name
        end
    end
    return table.concat(out,'\n')..'\n',files
end

-- Parses descriptor text. Manifest contents are filled in by the caller via read(name).
function M.decode(text,read)
    assert(type(text)=='string' and #text<=MAX_MANIFEST,'invalid descriptor')
    local header,pages,current={}, {}, nil
    for raw in (text..'\n'):gmatch('([^\n]*)\n') do
        local entry=raw:gsub('\r$','')
        if entry~='' then
            local section=entry:match('^%[([^%]]+)%]$')
            if section=='Contribution' then
                assert(current==nil and next(header)==nil,'misplaced Contribution section')
                current=header
            elseif section then
                local n=tonumber(section:match('^Page%.(%d+)$'))
                assert(n==#pages+1,'pages must be numbered in order')
                current={};pages[n]=current
            else
                local key,value=entry:match('^([%w]+)=(.*)$')
                assert(key and current,'invalid descriptor line')
                assert(current~=header or ({contract=1,id=1,generation=1})[key],'unknown header key '..key)
                assert(current==header or DESCRIPTOR_KEYS[key],'unknown page key '..key)
                assert(current[key]==nil,'duplicate key '..key)
                current[key]=unescape(value)
            end
        end
    end
    assert(tonumber(header.contract)==M.contract,'unsupported contract '..tostring(header.contract))
    local generation=tonumber(header.generation)
    assert(math.type(generation)=='integer' and generation>=1,'invalid generation')
    for _,page in ipairs(pages) do
        if page.visible~=nil then
            assert(page.visible=='0' or page.visible=='1','invalid visible')
            page.visible=page.visible=='1'
        end
        if page.manifestFile then
            assert(page.manifestFile==M.manifestName(generation,page.manifestFile:match('%.(%d+)%.ini$') or 0),
                'invalid manifest file')
            page.manifest=read(page.manifestFile)
            page.manifestFile=nil
        end
    end
    local contribution={pages=pages}
    check(header.id,contribution)
    return {id=header.id,generation=generation,pages=pages}
end

-- Parses a contributor variable: "<generation>\n<descriptor path>"; an empty path means withdrawn.
function M.slot(value)
    if type(value)~='string' then return nil end
    local generation,path=value:match('^(%d+)\n(.*)$')
    generation=tonumber(generation)
    if not generation then return nil end
    return generation,path
end

local function defaultRead(path)
    local file=io.open(path,'rb')
    if not file then return nil end
    local content=file:read('a')
    file:close()
    return content
end

local function defaultWrite(path,content)
    local file=assert(io.open(path,'wb'))
    local ok,err=file:write(content)
    file:close()
    assert(ok,err)
end

function M.publisher(shared,options)
    assert(shared and type(shared.GetSharedVariable)=='function'
        and type(shared.SetSharedVariable)=='function','shared variables unavailable')
    assert(type(options)=='table','publisher options required')
    local id,directory=options.id,options.directory
    line(id,128,'contributor id')
    line(directory,1024,'directory')
    assert(absolute(directory),'directory must be absolute')
    directory=directory:gsub('[/\\]+$','')
    local write,remove=options.write or defaultWrite,options.remove or os.remove
    local read=options.read or defaultRead
    local hexId=M.hex(id)
    local key=PREFIX..hexId
    local function join(name) return directory..'/'..name end
    -- Shared variables reset each game launch; the counter file keeps generations increasing
    -- so g-2 cleanup also reaches files left by an earlier launch.
    local counter=join('mcs_menu.generation')
    local last=math.tointeger(tonumber(read(counter) or '')) or 0
    if last<0 then last=0 end
    local function current() return (M.slot(shared:GetSharedVariable(key))) or 0 end
    local function cleanup(generation)
        if generation<1 then return end
        remove(join(M.descriptorName(generation)))
        local n=1
        while remove(join(M.manifestName(generation,n))) do n=n+1 end
    end
    local function register()
        local index=shared:GetSharedVariable(M.index)
        index=type(index)=='string' and index or ''
        for word in index:gmatch('%S+') do if word==hexId then return end end
        local updated=index=='' and hexId or index..' '..hexId
        shared:SetSharedVariable(M.index,updated)
        assert(shared:GetSharedVariable(M.index)==updated,'menu contribution index changed concurrently')
    end
    local self={}
    function self:publish(contribution)
        local generation=math.max(current(),last)+1
        local descriptor,files=M.encode(id,generation,contribution)
        for _,file in ipairs(files) do write(join(file.name),file.content) end
        local path=join(M.descriptorName(generation))
        write(path,descriptor)
        register()
        shared:SetSharedVariable(key,generation..'\n'..path)
        last=generation
        write(counter,tostring(generation))
        cleanup(generation-2)
        return generation
    end
    function self:withdraw()
        local generation=math.max(current(),last)
        if generation==0 then return end
        shared:SetSharedVariable(key,generation..'\n')
        cleanup(generation);cleanup(generation-1)
        last=generation
    end
    return self
end

return M
