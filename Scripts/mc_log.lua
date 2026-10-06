-- Leveled logging shared by the ModCore modules. ModCoreSettings holds the source; other
-- mods vendor this file unchanged into their own Scripts folder.
--
--   local log=require('mc_log').new({name='ModCoreControls',path=root..'/log_level.txt'})
--   log.debug('mapped ',count,' keys')   -- written only at DEBUG or TRACE
--   log.warn('config unavailable: ',why)
--
-- Levels, lowest first: TRACE, DEBUG, INFO, WARN, ERROR, CRITICAL. A message is written
-- when its level is at or above the module's level, read once from the file at `path`:
-- one level name, any case. A missing, empty or unknown level means WARN; logging never
-- prevents startup. Arguments are converted and joined only when the message is written.
local M={version=1,default='WARN',levels={'TRACE','DEBUG','INFO','WARN','ERROR','CRITICAL'}}
local rank={}
for index,name in ipairs(M.levels) do rank[name]=index end

-- The level a text names, or nil.
function M.parse(text)
    local name=type(text)=='string' and text:match('^%s*(%a+)%s*$')
    name=name and name:upper()
    return rank[name] and name or nil
end

-- The level a file names; the file's text when it names none; nil when it is missing.
local function read(path)
    local ok,file=pcall(io.open,path,'rb')
    if not ok or not file then return nil end
    local read,text=pcall(file.read,file,256)
    pcall(file.close,file)
    if not read then return nil end
    return M.parse(text),text
end

-- options: name (message prefix), level (a level name, overrides the file), path (level
-- file), write (function(line); defaults to print).
function M.new(options)
    options=options or {}
    local prefix='['..tostring(options.name or 'ModCore')..'] '
    local write=options.write or function(line) print(line..'\n') end
    local level,unknown=M.parse(options.level),nil
    if not level and options.path then
        local text
        level,text=read(options.path)
        if not level and text and text:match('%S') then unknown=text:match('^%s*(.-)%s*$') end
    end
    level=level or M.default
    local threshold=rank[level]
    local logger={level=level}
    local function emit(name,...)
        local parts={}
        for index=1,select('#',...) do parts[index]=tostring((select(index,...))) end
        -- A failing writer never breaks the caller.
        pcall(write,prefix..name..' '..table.concat(parts))
    end
    for index,name in ipairs(M.levels) do
        logger[name:lower()]=function(first,...)
            if index<threshold then return end
            -- Accept log:warn(...) as well as log.warn(...).
            if first==logger then emit(name,...) else emit(name,first,...) end
        end
    end
    -- Whether a level is written, for work worth skipping when it is not.
    function logger.enabled(first,second)
        local name=first==logger and second or first
        return (rank[tostring(name):upper()] or 0)>=threshold
    end
    if unknown then logger.warn('unknown log level "',unknown,'"; using ',M.default) end
    return logger
end

-- A logger from a plain function(message), as older callers and tests pass; every level
-- is forwarded. Loggers pass through unchanged.
function M.wrap(value)
    if type(value)=='table' and type(value.warn)=='function' then return value end
    local write=type(value)=='function' and value or function() end
    local logger={level='TRACE'}
    for _,name in ipairs(M.levels) do
        logger[name:lower()]=function(first,...)
            local parts={}
            local args=first==logger and {...} or {first,...}
            local count=first==logger and select('#',...) or select('#',...)+1
            for index=1,count do parts[index]=tostring(args[index]) end
            pcall(write,table.concat(parts))
        end
    end
    function logger.enabled() return true end
    return logger
end

return M
