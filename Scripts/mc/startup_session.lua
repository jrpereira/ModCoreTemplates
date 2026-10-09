local Layout=require('mc.layout')
local Runtime=require('mc.runtime')
local MenuModel=require('mc.menu_model')
local Menu=require('mc.menu')
local MenuFiles=require('mc.menu_files')
local MenuController=require('mc.menu_controller')
local U=require('mc.util')
local M={}

function M.validate(options,categories,templates,locations)
    local model=MenuModel.build(categories,U.copy(templates),locations)
    local menuOptions=U.copy(options.menu or {})
    if options.menuRoot then
        menuOptions.catalog=MenuFiles.readCatalog(options.menuRoot)
        menuOptions.version=Layout.version(options.menuRoot)
    end
    Menu.generate(model.registry,menuOptions)
    Runtime.new(options.host,model.categories,model.templates,options.state)
end

function M.new(options,categories,templates,locations,own)
    assert(not options.settingsApi or (not options.categorySettings and not options.selections),
        'use menuValues/config for menu-controlled startup selections')
    local self={}
    function self:stop()
        local errors={}
        for _,component in ipairs({'menuController','runtime'}) do
            local resource=self[component]
            if resource then
                local ok,result,detail=pcall(resource.stop,resource)
                if not ok or result==false then
                    errors[#errors+1]=component..': '..tostring(ok and detail or result)
                end
            end
        end
        if #errors>0 then return false,table.concat(errors,'; ') end
        return true
    end
    if own then own(self) end
    local model=MenuModel.build(categories,templates,locations)
    local menuOptions=U.copy(options.menu or {})
    if options.menuRoot then
        menuOptions.catalog=MenuFiles.readCatalog(options.menuRoot)
        menuOptions.version=Layout.version(options.menuRoot)
    end
    self.menu=Menu.generate(model.registry,menuOptions)
    self.categories=model.categories
    self.runtime=Runtime.new(options.host,model.categories,model.templates,options.state,{defer=options.defer})
    local savedValues=options.menuValues
    local configSources={}
    if options.menuRoot then
        local paths=Layout.paths(options.menuRoot)
        MenuFiles.publish(options.menuRoot,self.menu)
        local centralRows,seen={},{}
        local function include(rows)
            for _,row in ipairs(rows) do
                if not seen[row.id] then seen[row.id]=true;centralRows[#centralRows+1]=row end
            end
        end
        include(self.menu.aggregate.rows)
        for _,page in ipairs(self.menu.pages) do
            if page.category or page.slot then include(page.rows) end
        end
        configSources[1]={path=paths.config,rows=centralRows,textSettings=self.menu.textSettings}
        for _,page in ipairs(self.menu.pages) do
            if page.module then
                configSources[#configSources+1]={
                    path=assert(page.configPath,page.module..': config path unavailable'),
                    rows=page.rows,textSettings={}}
            end
        end
        -- Configuration never prevents startup: a config that cannot be prepared or read
        -- is reported, and its settings run on their defaults.
        for _,source in ipairs(configSources) do
            local ok,why=pcall(MenuFiles.ensureConfig,source.path,source.rows,source.textSettings)
            if not ok then pcall(options.host.onError,{stage='config',message=tostring(why)}) end
        end
    end
    local function readValues()
        local values={}
        for _,source in ipairs(configSources) do
            local ok,read=pcall(MenuFiles.readConfigValues,source.path,source.textSettings,source.rows)
            if ok then for id,value in pairs(read) do values[id]=value end
            else pcall(options.host.onError,{stage='config',message=tostring(read)}) end
        end
        return values
    end
    if options.menuRoot then savedValues=readValues() end
    -- The Templates page lists every loaded template and marks the active ones.
    local onState
    if options.menuRoot then
        local path,slot=Layout.paths(options.menuRoot).templates,nil
        for _,page in ipairs(self.menu.pages) do slot=slot or page.slot end
        onState=function(state)
            require('mc.safe_file').write(path,require('mc.templates_list').encode(model.registry.templates,state,slot))
        end
    end
    self.menuController=MenuController.new(self.menu,self.runtime,
        {values=savedValues,readValues=readValues,onError=options.host.onError,onState=onState})
    if options.settingsApi then self.menuController:bind(options.settingsApi,options.queue) end
    for category,settings in pairs(options.categorySettings or {}) do
        self.runtime:setCategorySettings(category,settings)
    end
    for category,selections in pairs(options.selections or {}) do
        self.runtime:select(category,selections)
    end
    function self:start()
        self.runtime:start()
        assert(self.runtime.phase=='running','lifecycle subscription failed')
    end
    return self
end

return M
