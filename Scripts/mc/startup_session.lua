local Layout=require('mc.layout')
local Runtime=require('mc.runtime')
local MenuModel=require('mc.menu_model')
local Menu=require('mc.menu')
local MenuFiles=require('mc.menu_files')
local MenuController=require('mc.menu_controller')
local U=require('mc.util')
local M={}

-- The menu model, generated menu and runtime for these templates.
local function compile(options,categories,templates,locations,runtimeOptions)
    local model=MenuModel.build(categories,templates,locations)
    local menuOptions=U.copy(options.menu or {})
    if options.menuRoot then
        menuOptions.version,menuOptions.root=Layout.version(options.menuRoot),options.menuRoot
    end
    local menu=Menu.generate(model.registry,menuOptions)
    return model,menu,Runtime.new(options.host,model.categories,model.templates,options.state,runtimeOptions)
end

function M.validate(options,categories,templates,locations)
    compile(options,categories,U.copy(templates),locations)
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
    local model
    model,self.menu,self.runtime=compile(options,categories,templates,locations,{defer=options.defer,
        unavailable=options.unavailableSignals,awakeChanged=options.awakeChanged,layoutChanged=options.layoutChanged})
    self.categories,self.model=model.categories,model
    local savedValues=options.menuValues
    local configSources={}
    if options.menuRoot then
        -- Scripts/cache is not part of the release ZIP; create it before anything is
        -- written there (config, templates list, menu contribution).
        local prepared,why=pcall(Layout.prepare,options.menuRoot)
        if not prepared then pcall(options.host.onError,{stage='config',message=tostring(why)}) end
        -- One source per file, whichever pages show its rows: a category's rows in the
        -- central config, a template's in its own mod's config.ini (row._path).
        local paths=Layout.paths(options.menuRoot)
        configSources[1]={path=paths.config,rows={},textSettings=self.menu.textSettings}
        local byPath={[paths.config]=configSources[1]}
        for _,row in ipairs(self.menu.rows) do
            local path=row._path or paths.config
            if not byPath[path] then
                byPath[path]={path=path,rows={},textSettings={}}
                configSources[#configSources+1]=byPath[path]
            end
            local rows=byPath[path].rows
            rows[#rows+1]=row
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
    -- The Templates page lists every loaded template by module and category and marks the
    -- active ones.
    local onState
    if options.menuRoot then
        local path=Layout.paths(options.menuRoot).templates
        onState=function(state)
            require('safe_file').write(path,require('mc.templates_list').encode(model.registry.templates,state))
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
