package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local Layout=require('mc.layout')
local root=assert(os.getenv('MCT_TEST_DIR') or os.getenv('TMPDIR'),'test directory required')..'/layout-'..os.time()

-- The first prepare creates the folders.
local paths=Layout.prepare(root)
local probe=assert(io.open(paths.cache..'/x','wb'),'cache folder created');probe:close();os.remove(paths.cache..'/x')

-- Existing folders never start a shell: on Windows that is a cmd.exe per call.
local execute=os.execute
os.execute=function() error('shell started for an existing folder') end
local ok,why=pcall(Layout.prepare,root)
os.execute=execute
assert(ok,why)
assert(io.open(paths.cache..'/.mct-probe','rb')==nil,'probe file removed')
print('PASS: existing layout folders are probed without a shell')
