-- One-shot orchestration after all provider modules have registered templates.
local Session=require('mc.startup_session')
local ModuleMetadata=require('mc.module_metadata')
local U=require('mc.util')
local M={}

-- Providers keep helpers beside their templates. Their folders are appended so a
-- provider module never shadows one of MCT's own.
function M.executeTemplate(path)
    local folder=assert(path:match('^(.*)[/\\][^/\\]+$'),path..': template has no directory')
    local entry=folder..'/?.lua'
    if not (';'..package.path..';'):find(';'..entry..';',1,true) then
        package.path=package.path..';'..entry
    end
    return assert(loadfile(path))()
end

function M.new(options)
    assert(type(options.categories)=='table','loaded categories required')
    assert(type(options.subscribeLoopStart)=='function','module-load barrier adapter required')
    local execute=options.execute or M.executeTemplate
    local self={phase='registering',runtime=nil,state=options.state}
    local files,seen={},{}
    local stopBarrier,session
    local providerCleanups={}
    local hostClosed=false
    local stateClosed=false
    local menuPublisher
    if options.menuShared then assert(options.menuRoot,'menu publishing requires menuRoot') end
    -- ModCoreSettings reads published pages from its own Lua state. Without them the
    -- templates still run on their saved settings, so a failure is only reported.
    local function publishMenu(menu)
        local Contribution=require('mc.menu_contribution')
        local SafeFile=require('mc.safe_file')
        -- The vendored client stays unchanged; MCT supplies crash-safe file access.
        -- Removing a retired generation file also removes its kept backup.
        menuPublisher=menuPublisher or require('mc.menu_contributions').publisher(options.menuShared,
            {id=Contribution.id,directory=require('mc.layout').paths(options.menuRoot).cache,
                read=SafeFile.read,write=SafeFile.write,
                remove=function(path) os.remove(path..'.old'); return os.remove(path) end})
        return menuPublisher:publish(Contribution.build(menu,options.menuRoot))
    end
    function self:registerTemplate(path)
        assert(self.phase=='registering','template registration closed at startup')
        assert(type(path)=='string' and path~='','template file required')
        local canonical=path:gsub('\\','/')
        if seen[canonical] then return false end
        files[#files+1],seen[canonical]=path,true
        return true
    end
    local function report(stage,message,path)
        pcall(options.host.onError,{stage=stage,message=tostring(message),provider=path})
    end
    local function releaseCleanups(cleanups)
        local errors={}
        for index=#cleanups,1,-1 do
            local ok,result,detail=pcall(cleanups[index])
            if ok and result~=false then table.remove(cleanups,index)
            else errors[#errors+1]=tostring(ok and detail or result) end
        end
        return errors
    end
    local function stopSession()
        local errors={}
        local function attempt(label,callback)
            local ok,result,detail=pcall(callback)
            if not ok or result==false then
                errors[#errors+1]=label..': '..tostring(ok and detail or result)
            end
        end
        if menuPublisher then attempt('menu pages',function() return menuPublisher:withdraw() end) end
        if session then attempt('session',function() return session:stop() end) end
        for _,why in ipairs(releaseCleanups(providerCleanups)) do
            errors[#errors+1]='provider cleanup: '..why
        end
        if options.closeHost and not hostClosed then
            attempt('host close',function()
                local result=options.closeHost()
                if result~=false then hostClosed=true end
                return result
            end)
        end
        if options.closeState and not stateClosed then
            attempt('control state',function()
                local result=options.closeState()
                if result~=false then stateClosed=true end
                return result
            end)
        end
        for _,why in ipairs(errors) do report('cleanup',why) end
        return #errors==0
    end
    function self:finishLoading()
        if self.phase~='registering' then return false end
        local ok,why=pcall(function()
            if options.collectTemplates then
                local registered=options.collectTemplates()
                assert(type(registered)=='table','collected templates must be a table')
                for _,path in ipairs(registered) do self:registerTemplate(path) end
            end
            self.phase='loading'
            if stopBarrier then stopBarrier();stopBarrier=nil end
            local templates,locations={},{}
            Session.validate(options,options.categories,{}, {})
            for _,path in ipairs(files) do
                local cleanups={}
                local loadedOK,loadedError=pcall(function()
                    local loaded=execute(path)
                    assert(type(loaded)=='table',path..': expected template definition')
                    local entries={}
                    if loaded.category then entries[1]=loaded
                    else
                        local count=U.array(loaded,path..': template list')
                        assert(count>0,path..': empty template list')
                        for index=1,count do entries[index]=loaded[index] end
                    end
                    for _,template in ipairs(entries) do
                        assert(type(template)=='table' and template.category,
                            path..': invalid template definition')
                        assert(template.loaded==nil or type(template.loaded)=='function',
                            path..': template.loaded must be a function')
                        ModuleMetadata.apply(template,path)
                    end
                    local function onCleanup(callback)
                        assert(type(callback)=='function',path..': cleanup callback must be a function')
                        cleanups[#cleanups+1]=callback
                    end
                    for _,template in ipairs(entries) do
                        if template.loaded then
                            local cleanup=template.loaded(onCleanup)
                            if type(cleanup)=='function' then onCleanup(cleanup) end
                        end
                    end
                    local proposed,proposedLocations={},{}
                    for index,template in ipairs(templates) do
                        proposed[index],proposedLocations[index]=template,locations[index]
                    end
                    for _,template in ipairs(entries) do
                        proposed[#proposed+1],proposedLocations[#proposedLocations+1]=template,path
                    end
                    Session.validate(options,options.categories,proposed,proposedLocations)
                    if options.events then
                        for _,template in ipairs(entries) do onCleanup(options.events:register(template)) end
                    end
                    templates,locations=proposed,proposedLocations
                end)
                if loadedOK then
                    for _,cleanup in ipairs(cleanups) do providerCleanups[#providerCleanups+1]=cleanup end
                else
                    report('provider',loadedError,path)
                    local cleanupErrors=releaseCleanups(cleanups)
                    for _,cleanup in ipairs(cleanups) do providerCleanups[#providerCleanups+1]=cleanup end
                    for _,error in ipairs(cleanupErrors) do report('cleanup',path..': '..error,path) end
                end
            end
            session=Session.new(options,options.categories,templates,locations,function(partial)
                session=partial
            end)
            self.menu,self.runtime=session.menu,session.runtime
            self.menuController=session.menuController
            -- Object notifications cover only categories with templates; they start
            -- before the runtime's first snapshot.
            if options.activateSource then options.activateSource(session.categories) end
            session:start()
            if options.menuShared then
                local published,why=pcall(publishMenu,session.menu)
                if not published then report('menu',why) end
            end
            self.phase='running'
            if options.log then
                require('mc_log').wrap(options.log).info(#templates,' templates from ',#files,' files running')
            end
        end)
        if not ok then
            self.phase='failed'
            stopSession()
            report('startup',why)
            return nil,why
        end
        return true
    end
    function self:stop()
        if stopBarrier then
            local ok,result=pcall(stopBarrier)
            if ok and result~=false then stopBarrier=nil
            else report('cleanup','module-load barrier: '..tostring(result)) end
        end
        stopSession()
        self.phase='stopped'
    end
    local stop=options.subscribeLoopStart(function() self:finishLoading() end)
    assert(type(stop)=='function','module-load barrier must return unsubscribe')
    if self.phase=='registering' then stopBarrier=stop else stop() end
    return self
end

return M
