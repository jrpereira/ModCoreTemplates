package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
-- Configuration never prevents startup: invalid saved values fall back to their defaults.
local MenuFiles=require('mc.menu_files')
local dir=(os.getenv('MCT_TEST_DIR') or os.getenv('TMPDIR') or '.'):gsub('/+$','')
local path=dir..'/mct_config_fallback_'..os.time()..'_'..math.random(1000000000)..'.ini'
local function write(content)
    local file=assert(io.open(path,'wb'));assert(file:write(content));assert(file:close())
end
local function read()
    local file=assert(io.open(path,'rb'));local content=file:read('*a');file:close();return content
end
local rows={{id='Template',choices={{value=0,label='None'},{value=3,label='Wheels'}},default=0},
    {id='Size',range={min=1,max=10},default=5}}
local text={Label={default='Wheel',format=nil}}

-- A selected template whose provider is gone, an out-of-range number and invalid text.
write('[Other]\nkeep=1\n[Templates]\nTemplate=7\nSize=99\nLabel=\n')
assert(MenuFiles.ensureConfig(path,rows,text)==true,'invalid values are rewritten')
local content=read()
assert(content:find('Template=0\n',1,true) and content:find('Size=5\n',1,true)
    and content:find('Label=Wheel\n',1,true) and content:find('[Other]\nkeep=1',1,true),content)
local values=MenuFiles.readConfigValues(path,text,rows)
assert(values.Template==0 and values.Size==5 and values.Label=='Wheel')
assert(MenuFiles.ensureConfig(path,rows,text)==false,'a repaired config is stable')

-- Rewritten values keep their inline comments.
write('[Templates]\nTemplate=7 ; chosen wheel\nSize=99# too big\nLabel=Wheel\n')
assert(MenuFiles.ensureConfig(path,rows,text)==true)
content=read()
assert(content:find('Template=0 ; chosen wheel\n',1,true) and content:find('Size=5# too big\n',1,true),content)

-- Repeated keys and sections keep the first value.
write('[Templates]\nTemplate=3\nTemplate=0\n[Templates]\nSize=2\nLabel=Mine\n')
assert(MenuFiles.ensureConfig(path,rows,text)==false)
values=MenuFiles.readConfigValues(path,text,rows)
assert(values.Template==3 and values.Size==2 and values.Label=='Mine')

-- Reading never raises on an invalid value; it is left out so its default applies.
write('[Templates]\nTemplate=7\nSize=x\n')
values=MenuFiles.readConfigValues(path,text,rows)
assert(values.Template==nil and values.Size==nil)

-- A missing config is created with the defaults.
os.remove(path)
assert(MenuFiles.ensureConfig(path,rows,text)==true)
values=MenuFiles.readConfigValues(path,text,rows)
assert(values.Template==0 and values.Size==5 and values.Label=='Wheel')
-- SafeFile keeps the replaced file as <path>.old.
os.remove(path)
os.remove(path..'.old')
print('PASS: invalid or repeated config values fall back without blocking startup')
