-- Vendored from ModCoreSettings (owner). Do not edit copies; change the source and re-vendor.
-- Leveled logging shared by the ModCore modules. Mods copy this file unchanged into their
-- own Scripts/vendor folder.
--
--   local log=require('mc_log').new({name='ModCoreControls'})
--   log.debug('mapped ',count,' keys')   -- written only at DEBUG or TRACE
--   log.warn('config unavailable: ',why)
--
-- With the UE4SS Lua Log Bridge installed, new returns the bridge's logger for the name
-- (UE4SSLuaLogBridge().Register(name)); its levels are set per mod and category in the
-- bridge's config.ini or the ModCore Settings menu. Without it, lines at WARN and above go
-- to UE4SS.log through print. Either way the calls, log.level, log.enabled and the line
-- format, "[Name] LEVEL message", are the same.
--
-- Levels, lowest first: TRACE, DEBUG, INFO, WARN, ERROR, CRITICAL. Arguments are converted
-- and joined only when the message is written; logging never prevents startup.
local M={version=2,default='WARN',levels={'TRACE','DEBUG','INFO','WARN','ERROR','CRITICAL'}}
local rank={}
for index,name in ipairs(M.levels) do rank[name]=index end

-- The level a text names, or nil.
function M.parse(text)
    local name=type(text)=='string' and text:match('^%s*(%a+)%s*$')
    name=name and name:upper()
    return rank[name] and name or nil
end

-- The bridge's logger for options, or nil and why when the bridge is present but refuses;
-- nil alone without the bridge.
local function bridged(name,options)
    local Bridge=UE4SSLuaLogBridge
    if Bridge==nil then return nil end
    local ok,logs=pcall(Bridge)
    if not ok or type(logs)~='table' then return nil,tostring(logs) end
    local settings={level=M.parse(options.level),categories=options.categories}
    local registered,logger,code,message=pcall(function() return logs.Register(name,settings) end)
    if not registered then return nil,tostring(logger) end
    if logger==nil then return nil,tostring(message or code) end
    return logger
end

-- options: name (message prefix and the bridge's module name), level (a level name; the
-- module's level when the bridge's settings name none), categories (a list, registered
-- with the bridge), write (function(line): a plain logger writing there, without the
-- bridge; defaults to print). A path option, once a level file, is ignored.
function M.new(options)
    options=options or {}
    local name=tostring(options.name or 'ModCore')
    local unavailable
    if not options.write then
        local logger,why=bridged(name,options)
        if logger then return logger end
        unavailable=why
    end
    local prefix='['..name..'] '
    local write=options.write or function(line) print(line..'\n') end
    local level=M.parse(options.level) or M.default
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
    if unavailable then logger.warn('UE4SS Lua Log Bridge unavailable (',unavailable,'); writing ',level,' and above') end
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
