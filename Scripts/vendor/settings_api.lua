-- Vendored from ModCoreSettings (owner). Do not edit copies; change the source and re-vendor.
-- Public, game-agnostic client for durable DMM Apply notifications. Consumers copy this
-- file unchanged into their Scripts/vendor folder; the transport is private to DMM.
local M={version=1}
local subscriptions={}
local owner=tostring({}):gsub('%W','')
local prefix='DMM_SettingsApplied_v1_'

local function hex(value)
    assert(type(value)=='string' and #value>0 and #value<=128,'invalid provider Id')
    return (value:gsub('.',function(c) return string.format('%02x',c:byte()) end))
end
local function unhex(value)
    assert(#value>0 and #value<=256 and #value%2==0 and not value:find('[^%da-f]'),'invalid encoded Id')
    return (value:gsub('..',function(c) return string.char(tonumber(c,16)) end))
end
local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)<=1000000000
end
local function revision(payload)
    return type(payload)=='string' and tonumber(payload:match('^(%d+)\n')) or 0
end
local function read(providerId,payload)
    assert(type(payload)=='string' and #payload<=98304,'invalid settings notification')
    local rev=revision(payload)
    assert(rev and rev>=1 and rev<=9007199254740991,'invalid notification revision')
    local values,changes,count={},{},0
    for line in payload:sub(assert(payload:find('\n',1,true))+1):gmatch('[^\n]+') do
        local key,old,new=line:match('^(%x+) ([^ ]+) ([^ ]+)$')
        assert(key,'invalid settings notification row')
        key=unhex(key);old,new=tonumber(old),tonumber(new)
        assert(finite(old) and finite(new) and values[key]==nil,'invalid notification value')
        count=count+1;assert(count<=256,'too many notification values')
        values[key]=new
        if old~=new then changes[key]={old=old,new=new} end
    end
    assert(count>0,'empty settings notification')
    return {providerId=providerId,revision=rev,values=values,changes=changes}
end
local function setCallback(record,callback)
    local ticket={}
    record.callback,record.ticket=callback,ticket
    return function() if record.ticket==ticket then record.callback=nil end end
end

function M.subscribe(providerId,callback)
    assert(type(callback)=='function','settings callback must be a function')
    local command=prefix..hex(providerId)
    local existing=subscriptions[command]
    if existing then return setCallback(existing,callback) end
    assert(ModRef and type(RegisterConsoleCommandHandler)=='function','UE4SS notification API unavailable')
    local claim=command..'.owner'
    assert(ModRef:GetSharedVariable(claim)==nil,'this provider Id already has a subscriber; fully restart after script reloads')
    local record={callback=callback,last=revision(ModRef:GetSharedVariable(command..'.data')) or 0}
    ModRef:SetSharedVariable(claim,owner)
    local ok,result=pcall(RegisterConsoleCommandHandler,command,function()
        local success,message=pcall(function()
            local event=read(providerId,ModRef:GetSharedVariable(command..'.data'))
            if event.revision<=record.last then return end
            record.last=event.revision
            if record.callback then record.callback(event) end
        end)
        if not success then print('[ModCoreSettings API] callback failed for '..providerId..': '..tostring(message)..'\n') end
        return true
    end)
    if not ok or result==false then
        if ModRef:GetSharedVariable(claim)==owner then ModRef:SetSharedVariable(claim,nil) end
        error(tostring(ok and 'console command registration rejected' or result),0)
    end
    subscriptions[command]=record
    return setCallback(record,callback)
end

return M
