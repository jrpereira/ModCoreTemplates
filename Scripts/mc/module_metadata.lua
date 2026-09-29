local M={}

local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
local null={}
local function parse(content)
    local index,length=1,#content
    local function invalid(message)
        error('invalid module manifest JSON at byte '..index..': '..message,0)
    end
    local function space()
        while index<=length do
            local char=content:sub(index,index)
            if char~=' ' and char~='\t' and char~='\r' and char~='\n' then break end
            index=index+1
        end
    end
    local function stringValue()
        if content:sub(index,index)~='"' then invalid('expected string') end
        index=index+1
        local parts={}
        while index<=length do
            local char=content:sub(index,index)
            if char=='"' then
                index=index+1
                local value=table.concat(parts)
                if not utf8.len(value) then invalid('invalid UTF-8 string') end
                return value
            end
            if char=='\\' then
                index=index+1
                local escaped=content:sub(index,index)
                if escaped=='u' then
                    local hex=content:sub(index+1,index+4)
                    if not hex:match('^%x%x%x%x$') then invalid('invalid unicode escape') end
                    local code=tonumber(hex,16)
                    index=index+5
                    if code>=0xD800 and code<=0xDBFF then
                        if content:sub(index,index+1)~='\\u' then invalid('missing low surrogate') end
                        local lowHex=content:sub(index+2,index+5)
                        if not lowHex:match('^%x%x%x%x$') then invalid('invalid low surrogate') end
                        local low=tonumber(lowHex,16)
                        if low<0xDC00 or low>0xDFFF then invalid('invalid low surrogate') end
                        code=0x10000+(code-0xD800)*0x400+(low-0xDC00)
                        index=index+6
                    elseif code>=0xDC00 and code<=0xDFFF then invalid('unpaired low surrogate') end
                    parts[#parts+1]=utf8.char(code)
                else
                    local value=escapes[escaped]
                    if not value then invalid('invalid string escape') end
                    parts[#parts+1]=value
                    index=index+1
                end
            else
                if char:byte()<32 then invalid('control character in string') end
                parts[#parts+1]=char
                index=index+1
            end
        end
        invalid('unterminated string')
    end
    local function numberValue()
        local start=index
        if content:sub(index,index)=='-' then index=index+1 end
        local first=content:sub(index,index)
        if first=='0' then index=index+1
        elseif first:match('^[1-9]$') then
            repeat index=index+1 until not content:sub(index,index):match('^%d$')
        else invalid('invalid number') end
        if content:sub(index,index)=='.' then
            index=index+1
            if not content:sub(index,index):match('^%d$') then invalid('invalid fraction') end
            repeat index=index+1 until not content:sub(index,index):match('^%d$')
        end
        if content:sub(index,index):match('^[eE]$') then
            index=index+1
            if content:sub(index,index):match('^[+-]$') then index=index+1 end
            if not content:sub(index,index):match('^%d$') then invalid('invalid exponent') end
            repeat index=index+1 until not content:sub(index,index):match('^%d$')
        end
        return tonumber(content:sub(start,index-1))
    end
    local value
    value=function(depth)
        if depth>64 then invalid('nesting too deep') end
        space()
        local char=content:sub(index,index)
        if char=='"' then return stringValue() end
        if char=='{' then
            index=index+1;space()
            local result={}
            if content:sub(index,index)=='}' then index=index+1;return result end
            while true do
                local key=stringValue();space()
                if content:sub(index,index)~=':' then invalid('expected colon') end
                index=index+1
                if result[key]~=nil then invalid('duplicate key') end
                result[key]=value(depth+1)
                space()
                local delimiter=content:sub(index,index);index=index+1
                if delimiter=='}' then return result end
                if delimiter~=',' then invalid('expected comma or object end') end
                space()
            end
        end
        if char=='[' then
            index=index+1;space()
            local result={}
            if content:sub(index,index)==']' then index=index+1;return result end
            while true do
                result[#result+1]=value(depth+1)
                space()
                local delimiter=content:sub(index,index);index=index+1
                if delimiter==']' then return result end
                if delimiter~=',' then invalid('expected comma or array end') end
            end
        end
        if char=='-' or char:match('^%d$') then return numberValue() end
        for literal,result in pairs({['true']=true,['false']=false,['null']=null}) do
            if content:sub(index,index+#literal-1)==literal then index=index+#literal;return result end
        end
        invalid('expected value')
    end
    local result=value(0)
    space()
    if index<=length then invalid('trailing content') end
    if type(result)~='table' or result==null then invalid('expected top-level object') end
    return result
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
    local manifest=parse(content)
    local metadata={module=manifest.id}
    if manifest.author~=nil then metadata.author=manifest.author end
    if manifest.version~=nil then metadata.version=manifest.version end
    for name,value in pairs(metadata) do
        assert(type(value)=='string' and value~='' and #value<=128 and not value:find('[%c|;%[%]]'),
            'invalid module '..name)
    end
    assert(metadata.module~=nil,'module id missing from module manifest')
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
