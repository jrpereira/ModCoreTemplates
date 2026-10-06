package.path='./Scripts/?.lua;'..package.path
-- Configuration never prevents startup: invalid saved values fall back to their defaults.
local MenuFiles=require('mc.menu_files')
local dir=(os.getenv('TMPDIR') or '.'):gsub('/+$','')
local path=dir..'/mct_config_fallback_'..os.time()..'_'..math.random(1000000000)..'.ini'
local function write(content)
    local file=assert(io.open(path,'wb'));assert(file:write(content));assert(file:close())
end
local function read()
    local file=assert(io.open(path,'rb'));local content=file:read('*a');file:close();return content
end
local rows={{Id='Template',Type='picker',PresetValues='0|3',Default='0'},
    {Id='Size',Type='integer',Minimum=1,Maximum=10,Default='5'}}
local text={Label={default='Wheel',format=nil}}

-- A selected template whose provider is gone, an out-of-range number and invalid text.
write('[Other]\nkeep=1\n[Templates]\nTemplate=7\nSize=99\nLabel=\n')
assert(MenuFiles.ensureConfig(path,rows,text,nil)==true,'invalid values are rewritten')
local content=read()
assert(content:find('Template=0\n',1,true) and content:find('Size=5\n',1,true)
    and content:find('Label=Wheel\n',1,true) and content:find('[Other]\nkeep=1',1,true),content)
local values=MenuFiles.readConfigValues(path,text,rows)
assert(values.Template==0 and values.Size==5 and values.Label=='Wheel')
assert(MenuFiles.ensureConfig(path,rows,text,nil)==false,'a repaired config is stable')

-- Repeated keys and sections keep the first value.
write('[Templates]\nTemplate=3\nTemplate=0\n[Templates]\nSize=2\nLabel=Mine\n')
assert(MenuFiles.ensureConfig(path,rows,text,nil)==false)
values=MenuFiles.readConfigValues(path,text,rows)
assert(values.Template==3 and values.Size==2 and values.Label=='Mine')

-- Reading never raises on an invalid value; it is left out so its default applies.
write('[Templates]\nTemplate=7\nSize=x\n')
values=MenuFiles.readConfigValues(path,text,rows)
assert(values.Template==nil and values.Size==nil)

-- Invalid initial values from a legacy config are not copied.
os.remove(path)
assert(MenuFiles.ensureConfig(path,rows,text,{Template=7,Size=4})==true)
values=MenuFiles.readConfigValues(path,text,rows)
assert(values.Template==0 and values.Size==4)
os.remove(path)
print('PASS: invalid or repeated config values fall back without blocking startup')
