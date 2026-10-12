-- Vendored from ModCoreSettings (owner). Do not edit copies; change the source and re-vendor.
-- INI text as ModCore modules and DMM read it: [Section] headers, key=value lines, ';' and
-- '#' comment lines. Parsing records byte offsets, so an edit splices the original text and
-- every other byte, line ending and comment stays as it was. Policies (repeated keys, which
-- lines are errors, inline comments in values) belong to the caller.
local M={version=1}
local function trim(s) return (s or ''):match('^%s*(.-)%s*$') end
M.trim=trim

-- Returns doc:
--   text      the parsed text
--   newline   '\r\n' when the text uses it anywhere, else '\n'
--   lines     each line: text (without its line ending), start (byte offset), finish (the
--             offset after its line ending); a text ending in a line ending has no empty
--             last line
--   sections  in order; sections[1] is the global section (name '', no header) holding the
--             lines before the first header. Each: name (between the brackets, untrimmed),
--             header (its line number, nil for the global section), last (its last line
--             number, 0 when the text is empty), finish (the byte offset where the next
--             header starts, or #text+1), entries
--   entries   each key=value line in order: key (trimmed), raw (everything after the first
--             '='), value (raw up to a ';' or '#', trimmed), line, section, and valueFirst,
--             valueLast (the byte range of value; valueLast=valueFirst-1 when empty)
--   malformed line numbers that are neither blank, a comment, a header nor key=value
function M.parse(text)
    assert(type(text)=='string','INI text required')
    local doc={text=text,newline=text:find('\r\n',1,true) and '\r\n' or '\n',lines={},malformed={}}
    local current={name='',entries={},last=0,finish=#text+1}
    doc.sections={current}
    local start=1
    while start<=#text do
        local stop=text:find('\n',start,true)
        local finish=stop and stop+1 or #text+1
        local line=text:sub(start,(stop or #text+1)-1):gsub('\r$','')
        local n=#doc.lines+1
        doc.lines[n]={text=line,start=start,finish=finish}
        local clean=trim(line)
        local name=clean:match('^%[([^%]]+)%]$')
        if name then
            current.finish=start
            current={name=name,header=n,entries={},last=n,finish=#text+1}
            doc.sections[#doc.sections+1]=current
        else
            current.last=n
            if clean~='' and not clean:match('^[;#]') then
                local prefix,key,raw=line:match('^(%s*)([^=]-)%s*=(.*)$')
                if key and trim(key)~='' then
                    local before,value=raw:match('^(%s*)([^;#]*)')
                    value=value:gsub('%s+$','')
                    local first=start+#line-#raw+#before
                    current.entries[#current.entries+1]={key=trim(key),raw=raw,value=value,line=n,
                        section=current,valueFirst=first,valueLast=first+#value-1}
                else
                    doc.malformed[#doc.malformed+1]=n
                end
            end
        end
        start=finish
    end
    return doc
end

-- Every section with this name, in order.
function M.sections(doc,name)
    local out={}
    for _,section in ipairs(doc.sections) do
        if section.name==name then out[#out+1]=section end
    end
    return out
end

-- Every entry of the named sections, in order; with key, only that key's.
function M.entries(doc,name,key)
    local out={}
    for _,section in ipairs(M.sections(doc,name)) do
        for _,entry in ipairs(section.entries) do
            if key==nil or entry.key==key then out[#out+1]=entry end
        end
    end
    return out
end

-- The offset after a section's last non-blank line: where an added key goes.
local function append(doc,section)
    for n=section.last,section.header or 1,-1 do
        local line=doc.lines[n]
        if line and trim(line.text)~='' then return line.finish,line end
    end
    if section.header then return doc.lines[section.header].finish,doc.lines[section.header] end
    return 1
end

-- text with key set to value in the first section named section (name '' for the global
-- section). The first assignment of key in any section of that name is changed in place,
-- keeping its spacing and trailing comment; otherwise the key is added after the section's
-- last non-blank line, or a new section is appended. value must fit on one line and hold no
-- ';' or '#', which the value reader would cut.
function M.set(text,section,key,value)
    value=tostring(value)
    assert(not value:find('[\r\n;#]'),'INI value cannot hold a line break, ; or #')
    assert(type(key)=='string' and key==trim(key) and key~='' and not key:find('[\r\n=%[%];#]'),'invalid INI key')
    local doc=M.parse(text or '')
    text=doc.text
    local entry=M.entries(doc,section,key)[1]
    if entry then return text:sub(1,entry.valueFirst-1)..value..text:sub(entry.valueLast+1) end
    local nl=doc.newline
    local target=M.sections(doc,section)[1]
    if target then
        local at,line=append(doc,target)
        local insert=key..'='..value..nl
        -- The last line of a text without a final line ending gets one first.
        if line and line.finish==#text+1 and not text:find('\n$') then insert=nl..insert end
        return text:sub(1,at-1)..insert..text:sub(at)
    end
    assert(type(section)=='string' and section~='' and not section:find('[\r\n%]]'),'invalid INI section')
    if text~='' and not text:find('\n$') then text=text..nl end
    if text~='' and not text:find('\n%s*\n$') and not text:find('^%s*\n$') then text=text..nl end
    return text..'['..section..']'..nl..key..'='..value..nl
end

return M
