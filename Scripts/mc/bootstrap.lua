-- One-shot orchestration after all provider modules have registered templates.
local Session=require('mc.startup_session')
local ModuleMetadata=require('mc.module_metadata')
local U=require('mc.util')
local M={}

function M.new(options)
    assert(type(options.categories)=='table','loaded categories required')
    assert(type(options.subscribeLoopStart)=='function','module-load barrier adapter required')
    local execute=options.execute or function(path) return assert(loadfile(path))() end
    local self={phase='registering',runtime=nil}
    local files,seen={},{}
    local stopBarrier,session
    local menuHandoff
    if options.menuShared then
        assert(options.menuRoot,'cross-state menu handoff requires menuRoot')
        menuHandoff=require('mc.menu_handoff').publisher(options.menuShared)
        menuHandoff:begin()
    end
    function self:registerTemplate(path)
        assert(self.phase=='registering','template registration closed at startup')
        assert(type(path)=='string' and path~='','template file required')
        local canonical=path:gsub('\\','/')
        if seen[canonical] then return false end
        files[#files+1],seen[canonical]=path,true
        return true
    end
    local function closeHost()
        if options.closeHost then pcall(options.closeHost) end
    end
    local function stopSession()
        if menuHandoff then menuHandoff:stop() end
        if session then session:stop() end
        closeHost()
    end
    function self:finishLoading()
        if self.phase~='registering' then return false end
        local ok,why=pcall(function()
            self.phase='loading'
            if stopBarrier then stopBarrier();stopBarrier=nil end
            local templates,locations={},{}
            local function include(template,path)
                assert(type(template)=='table' and template.category,
                    path..': invalid template definition')
                assert(template.loaded==nil or type(template.loaded)=='function',
                    path..': template.loaded must be a function')
                if template.loaded then template.loaded() end
                templates[#templates+1],locations[#locations+1]=template,path
            end
            for _,path in ipairs(files) do
                local loaded=execute(path)
                assert(type(loaded)=='table',path..': expected template definition')
                if loaded.category then
                    ModuleMetadata.apply(loaded,path)
                    include(loaded,path)
                else
                    local count=U.array(loaded,path..': template list')
                    assert(count>0,path..': empty template list')
                    for index=1,count do
                        ModuleMetadata.apply(loaded[index],path)
                        include(loaded[index],path)
                    end
                end
            end
            session=Session.new(options,options.categories,templates,locations)
            self.menu,self.runtime=session.menu,session.runtime
            self.menuController,self.extension=session.menuController,session.extension
            session:start()
            if menuHandoff then menuHandoff:ready() end
            self.phase='running'
        end)
        if not ok then
            self.phase='failed'
            stopSession()
            pcall(options.host.onError,{stage='startup',message=tostring(why)})
            return nil,why
        end
        return true
    end
    function self:stop()
        if stopBarrier then stopBarrier();stopBarrier=nil end
        stopSession()
        self.phase='stopped'
    end
    local stop=options.subscribeLoopStart(function() self:finishLoading() end)
    assert(type(stop)=='function','module-load barrier must return unsubscribe')
    if self.phase=='registering' then stopBarrier=stop else stop() end
    return self
end

return M
