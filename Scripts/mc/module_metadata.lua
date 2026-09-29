local M={}

local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}

local function jsonString(content,key)
    local index=content:match('"'..key..'"%s*:%s*"()')
    assert(index,key..' missing from module manifest')
    local result={}
    while index<=#content do
        local char=content:sub(index,index)
        if char=='"' then return table.concat(result) end
        if char=='\\' then
            index=index+1
            local escaped=content:sub(index,index)
            if escaped=='u' then
                local hex=content:sub(index+1,index+4)
                assert(hex:match('^%x%x%x%x$'),'invalid JSON unicode escape')
                result[#result+1]=utf8.char(tonumber(hex,16))
                index=index+4
            else
                result[#result+1]=assert(escapes[escaped],'invalid JSON string escape')
            end
        else
            assert(char:byte()>=32,'invalid JSON control character')
            result[#result+1]=char
        end
        index=index+1
    end
    error('unterminated module manifest string')
end

local function moduleRoot(path)
    local normalized=path:gsub('\\','/')
    return normalized:match('^(.*)/Scripts/[^/]+%.lua$')
end

function M.read(path)
    local root=moduleRoot(path)
    if not root then return nil end
    local input=io.open(root..'/mod.json','rb')
    if not input then return nil end
    local content=input:read('*a');input:close()
    local metadata={
        module=jsonString(content,'id'),
        author=jsonString(content,'author'),
        version=jsonString(content,'version'),
    }
    for name,value in pairs(metadata) do
        assert(value~='' and #value<=128 and not value:find('[%c|;%[%]]'),
            'invalid module '..name)
    end
    return metadata,root
end

function M.apply(template,path)
    local metadata=M.read(path)
    if not metadata then return template end
    for name,value in pairs(metadata) do
        assert(template[name]==nil or template[name]==value,
            path..': template '..name..' conflicts with module manifest')
        template[name]=value
    end
    return template
end

return M
