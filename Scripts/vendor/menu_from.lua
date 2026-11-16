-- Vendored from ModCoreSettings (owner). Do not edit copies; change the source and re-vendor.
-- Listed choices for keyed pickers: a menu-data enum may hold {from=<list file>, root=<mod folder>}
-- entries among its keyed choices. Each build runs the list file and splices the choices it
-- returns in that entry's place, so files a mod adds while the game runs appear the next time
-- the menu opens.
--
-- A list file lives at <root>/Scripts/<from> and returns a function:
--     return function(context)          -- context.directory: the mod folder
--         local names = context.files('sounds')   -- file names in <root>/sounds, unordered
--         return {{key='bell', label='Bell', note=, sound=}, ...}   -- in display order;
--         -- sound: a /Game/ event, 'none', or a WAV file in the mod ('sounds/bell.wav')
--     end
-- It runs as pure Lua 5.4: only the standard string, table, math and utf8 libraries and the
-- base functions that touch nothing outside it. context.files(subfolder) gives the names
-- directly inside <root>/<subfolder>: {} for a missing folder, nil and why on failure.
--
-- Rules, per field:
--   * A fixed choice wins over a listed one with its key, wherever it stands; between list
--     files, the first wins. Choices with invalid keys or text are skipped.
--   * A list that fails or comes back empty keeps its last good result, if any.
--   * A default no choice offers is shown as the first choice; with fewer than two choices it
--     is added as a placeholder, labelled as last listed or by its key. A field still left
--     with fewer than two choices is left off the page for that build, with every rule that
--     names it.
-- Every problem is reported once per list file and reason.
local M={version=1}

local MAX_CHOICES,MAX_TABS=64,8

local function validKey(value)
    return type(value)=='string' and #value>=1 and #value<=128 and value:match('^[%w_.-]+$')~=nil
        and tonumber(value)==nil
end
M.validKey=validKey
local function validText(value,limit)
    return type(value)=='string' and value~='' and #value<=(limit or 4096)
        and not value:find('[%c|;%[%]]') and not value:match('^%s') and not value:match('%s$')
end
-- A relative path inside a folder: no root, no drive, no '..', no empty segment.
local function relative(path)
    if type(path)~='string' or path=='' or #path>256 or path:find('\\',1,true)
        or path:match('^/') or path:match('^%a:') then return false end
    for segment in (path..'/'):gmatch('(.-)/') do
        if segment=='' or segment=='.' or segment=='..' or not segment:match('^[%w_.%- ]+$') then return false end
    end
    return true
end
M.relative=relative

-- Whether an enum's values hold a from entry.
function M.listed(values)
    if type(values)~='table' then return false end
    for _,choice in ipairs(values) do
        if type(choice)=='table' and choice.from~=nil then return true end
    end
    return false
end

-- A from entry, checked: {from=<path ending .lua>, root=<mod folder>}.
function M.entry(choice,where)
    for name in pairs(choice) do
        assert(name=='from' or name=='root',where..': unknown field '..tostring(name))
    end
    assert(relative(choice.from) and choice.from:match('%.lua$'),where..': invalid from')
    assert(type(choice.root)=='string' and choice.root~='' and #choice.root<=1024
        and not choice.root:find('%c') and not choice.root:find('%.%.'),where..': invalid root')
    return choice
end

local SAFE={'assert','error','ipairs','next','pairs','pcall','rawequal','rawget','rawlen','select',
    'tonumber','tostring','type','xpcall'}
local function sandbox()
    local env={}
    for _,name in ipairs(SAFE) do env[name]=_G[name] end
    for _,name in ipairs({'string','table','math','utf8'}) do
        local copy={}
        for key,value in pairs(_G[name]) do copy[key]=value end
        env[name]=copy
    end
    env._G=env
    return env
end

-- options:
--   files(root, subfolder) -> names | {} | nil, why   the host's folder listing
--   load(path, env) -> chunk | nil, why             loadfile by default
--   report(event, detail)                           a problem, once per list file and reason
-- Returns expand(menu): menu itself when it holds no from entry, else a copy with every
-- from entry resolved. Keeps the last good result of each list file between builds.
function M.expander(options)
    options=options or {}
    local files=assert(options.files,'menu_from needs files')
    local load=options.load or function(path,env) return loadfile(path,'t',env) end
    local report=options.report or function() end
    local good,labels,reported={},{},{}
    local function once(id,why)
        local detail=id..': '..tostring(why)
        if reported[detail] then return end
        reported[detail]=true
        pcall(report,'MENU_LIST_FAILED',detail)
    end
    -- One list file's choices, checked, or nil and why.
    local function run(entry)
        local root=entry.root:gsub('[/\\]+$','')
        local chunk,why=load(root..'/Scripts/'..entry.from,sandbox())
        if not chunk then return nil,why end
        local ok,list=pcall(chunk)
        if not ok then return nil,list end
        if type(list)~='function' then return nil,'list file must return a function' end
        local context={directory=root,files=function(subfolder)
            assert(relative(subfolder),'invalid subfolder '..tostring(subfolder))
            return files(root,subfolder)
        end}
        local result
        ok,result,why=pcall(list,context)
        if not ok then return nil,result end
        if result==nil then return nil,why or 'no choices' end
        if type(result)~='table' then return nil,'list must return a table' end
        local out={}
        for index,choice in ipairs(result) do
            local valid=type(choice)=='table' and validKey(choice.key) and validText(choice.label)
                and (choice.note==nil or validText(choice.note,64))
                and (choice.sound==nil or type(choice.sound)=='string')
            if valid then
                for name in pairs(choice) do
                    if name~='key' and name~='label' and name~='note' and name~='sound' then valid=false end
                end
            end
            -- A sound that is a file in the mod's folder ('sounds/x.wav') becomes its full
            -- path, played on a change of choice like a game event.
            local sound=choice.sound
            if valid and sound and sound~='none' and not sound:match('^/Game/') then
                sound=relative(sound) and sound:lower():match('%.wav$') and root..'/'..sound or nil
            end
            if valid then out[#out+1]={key=choice.key,label=choice.label,note=choice.note,sound=sound}
            else once(entry.root..'/Scripts/'..entry.from,'choice '..index..' skipped') end
        end
        return out
    end
    local function resolve(entry)
        local id=entry.root..'/Scripts/'..entry.from
        local list,why=run(entry)
        if list and #list>0 then
            good[id]=list
            for _,choice in ipairs(list) do labels[choice.key]=choice.label end
            return list
        end
        once(id,list and 'no choices' or why)
        return good[id] or {}
    end
    -- A field's values with its from entries spliced in, its default and whether it stays.
    local function field(source)
        local fixed={}
        for _,choice in ipairs(source.values) do
            if type(choice)=='table' and choice.key~=nil then fixed[choice.key]=true end
        end
        local out,seen={},{}
        local function add(choice)
            if seen[choice.key] then return end
            seen[choice.key]=true
            out[#out+1]=choice
        end
        for _,choice in ipairs(source.values) do
            if type(choice)=='table' and choice.from~=nil then
                for _,listed in ipairs(resolve(choice)) do
                    if not fixed[listed.key] then add(listed) end
                end
            else
                add(choice)
            end
        end
        local limit=source.widget=='tabs' and MAX_TABS or MAX_CHOICES
        for index=#out,limit+1,-1 do out[index]=nil end
        local default=source.default
        if not seen[default] then
            if #out<2 and validKey(default) then
                out[#out+1]={key=default,label=labels[default] or default}
            elseif out[1] then
                default=out[1].key
            end
        end
        if #out<2 then return nil end
        return out,default
    end
    return function(menu)
        if type(menu)~='table' or type(menu.fields)~='table' then return menu end
        local any=false
        for _,source in ipairs(menu.fields) do
            if type(source)=='table' and M.listed(source.values) then any=true;break end
        end
        if not any then return menu end
        local copy={}
        for key,value in pairs(menu) do copy[key]=value end
        copy.fields={}
        local dropped={}
        for _,source in ipairs(menu.fields) do
            if type(source)=='table' and M.listed(source.values) then
                local values,default=field(source)
                if values then
                    local resolved={}
                    for key,value in pairs(source) do resolved[key]=value end
                    resolved.values,resolved.default=values,default
                    copy.fields[#copy.fields+1]=resolved
                else
                    dropped[source.id]=true
                    once(tostring(source.id),'fewer than two choices; left off the page')
                end
            else
                copy.fields[#copy.fields+1]=source
            end
        end
        if next(dropped)==nil then return copy end
        -- Rules that name a dropped field go with it.
        local function strip(item)
            local conditions=item.conditions
            if type(conditions)~='table' then return item end
            local kept,changed={},false
            for name,rule in pairs(conditions) do
                if type(rule)=='table' and dropped[rule.field] then
                    changed=true
                    if name=='visible' and rule.playerExists~=nil then kept[name]={playerExists=rule.playerExists} end
                else kept[name]=rule end
            end
            if not changed then return item end
            local out={}
            for key,value in pairs(item) do out[key]=value end
            out.conditions=next(kept) and kept or nil
            return out
        end
        for index,item in ipairs(copy.fields) do copy.fields[index]=strip(item) end
        if type(menu.groups)=='table' then
            local function groups(list)
                local out={}
                for index,group in ipairs(list) do
                    out[index]=strip(group)
                    if type(group.groups)=='table' then
                        if out[index]==group then
                            local own={}
                            for key,value in pairs(group) do own[key]=value end
                            out[index]=own
                        end
                        out[index].groups=groups(group.groups)
                    end
                end
                return out
            end
            copy.groups=groups(menu.groups)
        end
        return copy
    end
end

-- A host listing through UE4SS's directory tree: the names directly inside
-- <mods>/<mod folder>/<subfolder>, the mod folder being root's last segment.
function M.gameFiles(iterate)
    return function(root,subfolder)
        local name=root:gsub('[/\\]+$',''):match('([^/\\]+)$')
        if not name then return nil,'mod folder unknown' end
        local ok,tree=pcall(iterate)
        if not ok or type(tree)~='table' then return nil,'directory listing failed: '..tostring(tree) end
        local node=tree.Game
        for _,step in ipairs({'Binaries','Win64','ue4ss','Mods',name}) do
            node=type(node)=='table' and node[step] or nil
        end
        if type(node)~='table' then return nil,'mod folder '..name..' not found' end
        for segment in (subfolder..'/'):gmatch('(.-)/') do
            node=type(node)=='table' and node[segment] or nil
        end
        if type(node)~='table' then return {} end
        local names={}
        for _,file in pairs(node.__files or {}) do
            if type(file)=='table' and type(file.__name)=='string' then names[#names+1]=file.__name end
        end
        return names
    end
end

return M
