package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local Files=require('mc.menu_files')
local base=assert(os.getenv('MCT_TEST_DIR'),'MCT_TEST_DIR required')..'/transaction.ini'
local row={id='X',range={min=0,max=10},default=1}
local function write(path,value)
    local file=assert(io.open(path,'wb'))
    assert(file:write(value));assert(file:close())
end
local function read(path)
    local file=io.open(path,'rb')
    if not file then return nil end
    local result=file:read('*a');file:close();return result
end
write(base,'[Templates]\nX=8\n')
assert(Files.ensureConfig(base,{row},{})==false)
assert(Files.readConfigValues(base,{}, {row}).X==8)

local extra={id='Y',range={min=0,max=10},default=2}
local new,old=base..'.new',base..'.old'
local originalRename,originalRemove,originalOpen=os.rename,os.remove,io.open
-- A successful write keeps the previous version as <path>.old.
assert(Files.ensureConfig(base,{row,extra},{})==true)
assert(read(old)=='[Templates]\nX=8\n' and read(new)==nil)
assert(Files.readConfigValues(base,{}, {row,extra}).Y==2)
write(base,'[Templates]\nX=8\n')
-- Write or close failures leave the original and clear the replacement.
for _,failure in ipairs({'write','close'}) do
    io.open=function(path,mode)
        local file=originalOpen(path,mode)
        if path~=new or mode~='wb' then return file end
        return {
            write=function(_,value)
                if failure=='write' then return nil,'injected write failure' end
                return file:write(value)
            end,
            close=function()
                local result=file:close()
                if failure=='close' then return nil,'injected close failure' end
                return result
            end,
        }
    end
    assert(not pcall(Files.ensureConfig,base,{row,extra},{}))
    io.open=originalOpen
    assert(Files.readConfigValues(base,{}, {row}).X==8)
    assert(read(new)==nil)
end
-- Failure moving the original to the backup leaves it in place.
os.rename=function(from,to)
    if from==base and to==old then return nil,'injected backup rename failure' end
    return originalRename(from,to)
end
assert(not pcall(Files.ensureConfig,base,{row,extra},{}))
os.rename=originalRename
assert(Files.readConfigValues(base,{}, {row}).X==8 and read(new)==nil)

-- Failure publishing the replacement rolls back to the original.
os.rename=function(from,to)
    if from==new and to==base then return nil,'injected publish rename failure' end
    return originalRename(from,to)
end
assert(not pcall(Files.ensureConfig,base,{row,extra},{}))
os.rename=originalRename
assert(Files.readConfigValues(base,{}, {row}).X==8 and read(new)==nil)

-- If clearing the failed replacement also fails, the next read discards it.
os.rename=function(from,to)
    if from==new and to==base then return nil,'injected publish rename failure' end
    return originalRename(from,to)
end
os.remove=function(path)
    if path==new then return nil,'injected replacement removal failure' end
    return originalRemove(path)
end
assert(not pcall(Files.ensureConfig,base,{row,extra},{}))
os.rename,os.remove=originalRename,originalRemove
assert(read(new)~=nil)
assert(Files.readConfigValues(base,{}, {row}).X==8 and read(new)==nil)

-- Crash after moving the original out publishes the complete replacement.
originalRemove(base)
write(old,'[Templates]\nX=8\n')
write(new,'[Templates]\nX=6\n')
assert(Files.readConfigValues(base,{}, {row}).X==6)
assert(read(new)==nil and read(old)=='[Templates]\nX=8\n')

-- A removed config with only a backup is not resurrected.
originalRemove(base)
assert(Files.ensureConfig(base,{row},{})==true)
assert(Files.readConfigValues(base,{}, {row}).X==1, 'defaults, not the backup')
print('PASS: interrupted menu writes recover original or published config')
