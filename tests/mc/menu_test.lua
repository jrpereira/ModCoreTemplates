package.path = './Scripts/?.lua;' .. package.path
local Model = require('mc.menu_model')
local Menu = require('mc.menu')
local Runtime = require('mc.runtime')
local Controller = require('mc.menu_controller')
local Files = require('mc.menu_files')
local Extension = require('mc.dmm_extension')
local Bootstrap = require('mc.bootstrap')
local Layout = require('mc.layout')
local U = require('mc.util')
local Choices = dofile(assert(os.getenv('MCT_DMM_CHOICES'), 'MCT_DMM_CHOICES required'))
local Presentation = dofile(assert(os.getenv('MCT_PRESENTATION'), 'MCT_PRESENTATION required'))
local testRoot = assert(os.getenv('MCT_TEST_DIR'), 'MCT_TEST_DIR required')
local passed = 0
local function test(name, body)
    local ok, why = pcall(body)
    assert(ok, name .. ': ' .. tostring(why))
    passed = passed + 1
end
local function field(id, default)
    return {id=id, label=id, values={min=0,max=100,step=1}, default=default}
end
local function categoryField(id,default)
    return {id=id,label=id,type='integer',min=0,max=100,step=1,default=default}
end
local function fixture(single, alphaTarget, betaTarget, locationBase)
    local calls, errors = {}, {}
    local category = {name='player.quickslots', single=single, objects={root={source='lookup',object='switcher'}},
        settings={constant=false}, menu={groups={{id='Layout', label='Layout',
            fields={categoryField('Size', 10), categoryField('Opacity', 50)}}}}}
    local function template(id, target)
        local t = {id=id, name=id, category=category.name, objects={'root'},managed=false,
            menuTarget=target,menu={{id='Layout',label='Layout',fields={field('Size',20)}}}}
        for _, operation in ipairs({'attach','update','detach'}) do
            t[operation] = function(object, params)
                assert(params.screen.width==1920 and params.screen.top==1080)
                calls[#calls+1] = {id=id,operation=operation,settings=U.copy(params.settings),object=object}
            end
        end
        return t
    end
    local a,b = template('Alpha',alphaTarget or 'templates'), template('Beta',betaTarget)
    b.author='Example Author'
    locationBase = locationBase or '/Mods'
    local locations = {locationBase..'/Alpha/Scripts/templates/template.lua',
        locationBase..'/Beta/Scripts/templates/template.lua'}
    local model = Model.build({category}, {a,b}, locations)
    local menu = Menu.generate(model.registry)
    local object = {id='instance:1'}
    local host = {valid=function(o) return o==object end, identity=function(o) return o.id end,
        ready=function() return true end, parent=function() return nil end,
        watch=function() end,
        screen=function() return {width=1920,height=1080,left=0,center=960,right=1920,
            bottom=0,middle=540,top=1080} end,
        matches=function(_,s) return s.object=='switcher' end, find=function() return {object} end,
        subscribe=function() return function() end end, onError=function(e) errors[#errors+1]=e end}
    local runtime = Runtime.new(host,model.categories,model.templates)
    local controller = Controller.new(menu,runtime)
    runtime:start()
    local definitions = {}
    for _, definition in pairs(menu.definitions[category.name]) do definitions[definition.id]=definition end
    local function choose(values, id, enabled)
        if single then
            local selector=menu.selectors[category.name]
            for value, identity in pairs(selector.byValue) do
                if identity==id then values[selector.id]=enabled and value or 0 end
            end
        else
            for _, item in ipairs(menu.multiSelectors[category.name]) do
                if item.definition.id==id then values[item.id]=enabled and 1 or 0 end
            end
        end
    end
    return {menu=menu, model=model, runtime=runtime, controller=controller, calls=calls, errors=errors,
        a=a,b=b,category=category,host=host,locations=locations,definitions=definitions,choose=choose}
end
local function event(f, page, revision, edits)
    local values=f.controller:values()
    if edits then edits(values) end
    return {providerId=page.id,revision=revision,values=values}
end

test('copied manifests parse with actual DMM and ModCoreSettings', function()
    local f=fixture(true)
    assert(#f.menu.pages==2)
    for _,provider in pairs(f.menu.providers) do
        local choices=Choices.parse(provider.manifest)
        Presentation.parse(provider.manifest,choices)
        local model=Choices.open({id=provider.id,choices=choices,testOnly=true})
        assert(not model.error,model.error)
        assert(#choices==#provider.rows)
    end
    assert(f.menu.pageByCategory['player.quickslots'] and f.menu.pageByModule.Beta)
    assert(f.b.menuTarget=='module', 'omitted menu target defaults to the module page')
    assert(f.menu.pageByModule.Beta.author=='Example Author')
    assert(f.menu.pageByModule.Beta.moduleRoot=='/Mods/Beta')
    for _,choice in ipairs(Choices.parse(f.menu.pageByModule.Beta.manifest)) do
        if choice.file then assert(choice.file=='config.ini') end
    end
end)

test('module-target templates do not add controls to the MCT aggregate page', function()
    local mixed=fixture(true)
    assert(#mixed.menu.aggregate.rows==0)
    assert(#mixed.menu.pageByModule.Beta.rows>0)
    local moduleOnly=fixture(true,'module','module')
    assert(#moduleOnly.menu.aggregate.rows==0 and #moduleOnly.menu.pages==2)
    assert(moduleOnly.menu.pageByModule.Alpha and moduleOnly.menu.pageByModule.Beta)
    local extension=Extension.new(testRoot,moduleOnly.menu)
    local api={choices=Choices,pages={build=function(_,providers) return providers end}}
    extension.install(api)
    local providers={{id='ModCoreTemplates',name='ModCore Templates',testOnly=false},
        {id='detected:ue4ss:alpha',name='Alpha',testOnly=false,noSettings=true},
        {id='detected:ue4ss:beta',name='Beta',testOnly=false,noSettings=true}}
    api.pages.build({},providers,{},{})
    assert(#providers==2)
    for _,provider in ipairs(providers) do
        assert(provider.id~='ModCoreTemplates' and provider.settingsCount>0)
        assert(provider.path=='/Mods/'..provider.name..'/enabled.txt')
    end
end)

test('Apply activates and updates with merged settings, without navigation metadata', function()
    local f=fixture(true)
    local page=f.menu.pageByCategory['player.quickslots']
    f.controller:apply(event(f,page,1,function(values) f.choose(values,'Alpha',true) end))
    assert(#f.calls==1 and f.calls[1].operation=='attach')
    assert(f.calls[1].settings.Size==20 and f.calls[1].settings.Opacity==50 and f.calls[1].settings.constant==false)
    assert(f.calls[1].settings.Tab==nil and f.calls[1].settings.target==nil)
    f.controller:apply(event(f,page,2,function(values) values[f.definitions.Alpha.settings.Size]=70 end))
    assert(#f.calls==2 and f.calls[2].operation=='update' and f.calls[2].settings.Size==70)
end)

test('category and template edits produce one coherent update per object', function()
    local f=fixture(true)
    local page=f.menu.pageByCategory['player.quickslots']
    f.controller:apply(event(f,page,1,function(v) f.choose(v,'Alpha',true) end))
    f.controller:apply(event(f,page,2,function(v)
        v[f.definitions.Alpha.settings.Size]=80
        v[f.menu.categorySettings['player.quickslots'].fields.Opacity]=60
        v[f.menu.categorySettings['player.quickslots'].fields.Size]=90
    end))
    assert(#f.calls==2 and f.calls[2].settings.Size==80 and f.calls[2].settings.Opacity==60)
end)

test('aggregate Apply preserves template values from other pages', function()
    local f=fixture(true,'templates','templates')
    local page=f.menu.pageByCategory['player.quickslots']
    f.controller:apply(event(f,page,1,function(v) f.choose(v,'Alpha',true); v[f.definitions.Alpha.settings.Size]=77 end))
    f.controller:apply(event(f,f.menu.aggregate,1,function(v)
        v[f.definitions.Alpha.settings.Size]=20 -- not owned by this aggregate page
        v[f.menu.categorySettings['player.quickslots'].fields.Opacity]=25
    end))
    assert(f.calls[#f.calls].settings.Size==77 and f.calls[#f.calls].settings.Opacity==25)
end)

test('module pages cannot overwrite other templates through hidden rows', function()
    local f=fixture(false)
    local page=f.menu.pageByCategory['player.quickslots']
    f.controller:apply(event(f,page,1,function(v) f.choose(v,'Alpha',true); v[f.definitions.Alpha.settings.Size]=77 end))
    f.controller:apply(event(f,f.menu.pageByModule.Beta,1,function(v)
        f.choose(v,'Beta',true)
        v[f.definitions.Beta.settings.Size]=88
        v[f.definitions.Alpha.settings.Size]=11
    end))
    local values=f.controller:values()
    assert(values[f.definitions.Alpha.settings.Size]==77 and values[f.definitions.Beta.settings.Size]==88)
    assert(f.runtime:attachments('Alpha')['instance:1'] and f.runtime:attachments('Beta')['instance:1'])
end)

test('revision replay and unchanged commits cause no extra callbacks', function()
    local f=fixture(true)
    local page=f.menu.pageByCategory['player.quickslots']
    local first=event(f,page,1,function(v) f.choose(v,'Alpha',true) end)
    assert(f.controller:apply(first)); assert(not f.controller:apply(first))
    f.controller:apply(event(f,page,2))
    assert(#f.calls==1)
end)

test('invalid Apply rejects atomically without consuming revision', function()
    local f=fixture(true)
    local page=f.menu.pageByCategory['player.quickslots']
    local bad=event(f,page,1,function(v) f.choose(v,'Alpha',true); v[f.definitions.Alpha.settings.Size]=999 end)
    assert(not pcall(f.controller.apply,f.controller,bad) and #f.calls==0)
    assert(f.controller:apply(event(f,page,1,function(v) f.choose(v,'Alpha',true) end)))
    assert(#f.calls==1)
end)

test('template switch detaches with old settings before attaching new selection', function()
    local f=fixture(true)
    f.controller:apply(event(f,f.menu.pageByCategory['player.quickslots'],1,function(v)
        f.choose(v,'Alpha',true); v[f.definitions.Alpha.settings.Size]=77
    end))
    f.controller:apply(event(f,f.menu.pageByModule.Beta,1,function(v) f.choose(v,'Beta',true) end))
    assert(f.calls[2].operation=='detach' and f.calls[2].settings.Size==77)
    assert(f.calls[3].operation=='attach' and f.calls[3].id=='Beta')
end)

test('identity catalog preserves existing template choice and field IDs', function()
    local f=fixture(true)
    local rebuilt=Menu.generate(f.model.registry,{catalog=f.menu.catalog})
    assert(rebuilt.selectors['player.quickslots'].id==f.menu.selectors['player.quickslots'].id)
    for value,definition in pairs(f.menu.definitions['player.quickslots']) do
        assert(rebuilt.definitions['player.quickslots'][value].settings.Size==definition.settings.Size)
    end
end)

test('menu metadata in runtime settings is rejected', function()
    local template={name='Old',category='player.quickslots',
        settings={target='module',fields={categoryField('Size',42)}},
        attach=function() end,update=function() end,detach=function() end}
    local ok,why=pcall(Model.build,{{name='player.quickslots'}},{template},{'fixture.lua'})
    assert(not ok and tostring(why):find('template.menu',1,true))
end)

test('DMM extension adds pages once and replaces module placeholder', function()
    local f=fixture(true)
    local extension=Extension.new(testRoot,f.menu)
    local api={choices=Choices,pages={build=function(_,providers) return providers end}}
    assert(extension.install(api)==nil and extension.install(api)==false)
    local providers={{id='ModCoreTemplates',name='ModCore Templates',testOnly=false},
        {id='detected:ue4ss:beta',name='Beta',testOnly=false,noSettings=true}}
    api.pages.build({},providers,{},{}); api.pages.build({},providers,{},{})
    assert(#providers==3)
    local seen={}
    for _,p in ipairs(providers) do assert(not seen[p.id]); seen[p.id]=true end
    assert(seen['ModCoreTemplates.module.Beta'])
    for _,provider in ipairs(providers) do
        if provider.id=='ModCoreTemplates.module.Beta' then assert(provider.author=='Example Author') end
    end
end)

test('provider link opens the existing page without saving a second value', function()
    local f=fixture(true)
    local linkId=f.definitions.Beta.navigation.ControlLayoutLink
    local row
    for _,candidate in ipairs(f.menu.rows) do if candidate.Id==linkId then row=candidate end end
    assert(row and row.mcNavigation==1 and row.mcLinkProvider=='ModCoreControls')
    local extension=Extension.new(testRoot,f.menu)
    local page
    local api={choices=Choices,pages={build=function(_,providers)
        page={rows={},controlStatus={},transitions={}}
        for index in ipairs(providers) do page.rows[index]={providerIndex=index} end
        page.controls={show=function(self,index)
            self.active=index
            self.model={saved=0,dirtyValue=false,
                set=function(model) model.saved=model.saved+1 end,
                dirty=function(model) return model.dirtyValue end}
        end,tick=function(_,activate) activate() end}
        function page:showDetail(index)
            self.transitions[#self.transitions + 1] = 'detail:' .. providers[self.rows[index].providerIndex].id
            self.opened=providers[self.rows[index].providerIndex].id
            self.controls:show(self.rows[index].providerIndex)
        end
        function page:showBrowser()
            self.transitions[#self.transitions + 1] = 'browser'
            self.controls.model:restore()
        end
        return page
    end}}
    extension.install(api)
    local providers={{id='ModCoreTemplates',name='ModCore Templates',testOnly=false},
        {id='ModCoreControls',name='ModCore Controls',testOnly=false}}
    local view=api.pages.build({},providers,{},
        {setText=function(widget,value) widget.text=value end})
    local betaIndex,linkIndex
    for index,provider in ipairs(providers) do
        if provider.id=='ModCoreTemplates.module.Beta' then
            betaIndex=index
            for settingIndex,choice in ipairs(provider.choices) do
                if choice.id==linkId then
                    assert(choice.mcLinkProvider=='ModCoreControls')
                    linkIndex=settingIndex
                end
            end
        end
    end
    assert(betaIndex and linkIndex)
    view:showDetail(betaIndex)
    local model=view.controls.model
    function model:restore() self.restored=(self.restored or 0)+1 end
    assert(view.controls:tick(function() model:set(linkIndex,0) end)==true)
    assert(view.opened=='ModCoreControls' and model.saved==0 and model.restored==1)
    assert(view.transitions[#view.transitions-1]=='browser'
        and view.transitions[#view.transitions]=='detail:ModCoreControls',
        'provider link must tear down its source detail before opening its target')
    local transitionCount=#view.transitions
    assert(view.controls:tick(function() end)~=true and #view.transitions==transitionCount,
        'provider link must not repeat after the target page opens')
    view:showDetail(betaIndex)
    model=view.controls.model;model.dirtyValue=true
    function model:restore() self.restored=(self.restored or 0)+1 end
    assert(view.controls:tick(function() model:set(linkIndex,0) end)==true)
    assert(view.opened=='ModCoreTemplates.module.Beta' and model.saved==0 and not model.restored)
    assert(view.controlStatus.text:find('Apply or discard',1,true))
end)

test('published menus and catalog can be reloaded; user config is preserved', function()
    local f=fixture(true)
    local config=Layout.prepare(testRoot).config
    local out=assert(io.open(config,'w')); out:write('[Other]\nKeep=42\n[Templates]\nUnknown=55\n'); out:close()
    Files.publish(testRoot,f.menu)
    assert(Files.ensureConfig(config,f.menu.rows,f.menu.textSettings))
    assert(not Files.ensureConfig(config,f.menu.rows,f.menu.textSettings))
    local catalog=Files.readCatalog(testRoot)
    assert(catalog.next==f.menu.catalog.next)
    local values=Files.readConfigValues(config,f.menu.textSettings,f.menu.rows)
    assert(values[f.definitions.Alpha.settings.Size]==20)
    local input=assert(io.open(config)); local content=input:read('*a'); input:close()
    assert(content:find('Keep=42',1,true) and content:find('Unknown=55',1,true))
    local savedPages=assert(loadfile(Layout.paths(testRoot).pages))().pages
    assert(#savedPages==2 and savedPages[2].author=='Example Author')
end)

test('queued Apply is ignored after unsubscribe', function()
    local f=fixture(true)
    local callbacks,tasks,stopped={},{},0
    f.controller:bind({subscribe=function(id,cb) callbacks[id]=cb; return function() stopped=stopped+1 end end},
        function(fn) tasks[#tasks+1]=fn end)
    local page=f.menu.pageByCategory['player.quickslots']
    callbacks[page.id](event(f,page,1,function(v) f.choose(v,'Alpha',true) end))
    assert(#f.calls==0 and #tasks==1)
    f.controller:stop(); tasks[1]()
    assert(#f.calls==0 and stopped==3)
end)

test('partial subscription failure releases earlier subscriptions', function()
    local f=fixture(true)
    local count,stopped=0,0
    local ok=pcall(f.controller.bind,f.controller,{subscribe=function()
        count=count+1
        if count==2 then error('subscribe failed') end
        return function() stopped=stopped+1 end
    end},function(fn) fn() end)
    assert(not ok and stopped==1)
end)

test('bootstrap generates menus at barrier and routes committed Apply to runtime', function()
    local f=fixture(true)
    local barrier,callbacks=nil,{}
    local definitions={category=f.category, [f.locations[1]]=f.a,[f.locations[2]]=f.b}
    local values=f.controller:values(); f.choose(values,'Alpha',true)
    local boot=Bootstrap.new({host=f.host,categories={f.category},
        execute=function(path) return definitions[path] end,menuValues=values,
        settingsApi={subscribe=function(id,cb) callbacks[id]=cb; return function() end end},queue=function(fn) fn() end,
        subscribeLoopStart=function(cb) barrier=cb; return function() end end})
    for _,location in ipairs(f.locations) do boot:registerTemplate(location) end
    assert(boot.menu==nil); barrier(); assert(boot.phase=='running',f.errors[1] and f.errors[1].message)
    assert(boot.menu and boot.extension and #f.calls==1)
    local page=boot.menu.pageByCategory['player.quickslots']
    values=boot.menuController:values(); values[f.definitions.Alpha.settings.Size]=75
    callbacks[page.id]({providerId=page.id,revision=1,values=values})
    assert(#f.calls==2 and f.calls[2].operation=='update' and f.calls[2].settings.Size==75)
    boot:stop(); assert(f.calls[3].operation=='detach')
end)

test('adding an earlier template cannot steal an existing saved field ID', function()
    local f=fixture(true)
    local previous=f.definitions.Alpha.settings.Size
    local extra=U.copy(f.model.registry.templates[1])
    extra.id,extra.template.name='AAA','Earlier'
    table.insert(f.model.registry.templates,1,extra)
    local rebuilt=Menu.generate(f.model.registry,{catalog=f.menu.catalog})
    local found
    for _,definition in pairs(rebuilt.definitions['player.quickslots']) do
        if definition.id=='Alpha' then found=definition.settings.Size end
    end
    assert(found==previous)
    Files.publish(testRoot,rebuilt)
    local restored=Menu.generate(f.model.registry,{catalog=Files.readCatalog(testRoot)})
    for value,definition in pairs(rebuilt.definitions['player.quickslots']) do
        assert(restored.definitions['player.quickslots'][value].settings.Size==definition.settings.Size)
    end
end)

test('category text settings inherit and refresh from committed config', function()
    local f=fixture(true)
    local fields=f.category.menu.groups[1].fields
    fields[#fields+1]={id='Caption',type='text',default='Initial'}
    local model=Model.build({f.category},{f.a,f.b},f.locations)
    local menu=Menu.generate(model.registry)
    local runtime=Runtime.new(f.host,model.categories,model.templates)
    local id=menu.categorySettings['player.quickslots'].textIds.Caption
    local current='First'
    local controller=Controller.new(menu,runtime,{readValues=function() return {[id]=current} end})
    runtime:start()
    local page=menu.pageByCategory['player.quickslots']
    local values=controller:values(); f.choose(values,'Alpha',true)
    controller:apply({providerId=page.id,revision=1,values=values})
    assert(f.calls[1].settings.Caption=='First')
    current='Second'
    controller:apply({providerId=page.id,revision=2,values=controller:values()})
    assert(f.calls[2].operation=='update' and f.calls[2].settings.Caption=='Second')
end)

test('disabled template metadata prevents lifecycle calls even when selected', function()
    local f=fixture(true)
    f.a.enabled=false
    local model=Model.build({f.category},{f.a,f.b},f.locations)
    local menu=Menu.generate(model.registry)
    local runtime=Runtime.new(f.host,model.categories,model.templates)
    local controller=Controller.new(menu,runtime)
    runtime:start()
    local values=controller:values(); f.choose(values,'Alpha',true)
    controller:apply({providerId=menu.aggregate.id,revision=1,values=values})
    assert(#f.calls==0)
end)

test('invalid saved config is reported without replacing user values', function()
    local f=fixture(true)
    local path=testRoot..'/invalid.ini'
    local contents='[Templates]\n'..f.definitions.Alpha.settings.Size..'=999\n'
    local out=assert(io.open(path,'w')); out:write(contents); out:close()
    assert(not pcall(Files.ensureConfig,path,f.menu.rows,f.menu.textSettings))
    local input=assert(io.open(path)); local actual=input:read('*a'); input:close()
    assert(actual==contents)
end)

test('generated data goes into Scripts/cache and DMM resolves its nested config', function()
    local f=fixture(true,'templates','templates')
    local root=testRoot..'/new-layout'
    local paths=Layout.prepare(root)
    Files.publish(root,f.menu)
    Files.ensureConfig(paths.config,f.menu.rows,f.menu.textSettings)
    for _,row in ipairs(f.menu.rows) do
        if row.mcNavigation~=1 then assert(row.ConfigFile=='Scripts/cache/config.ini') end
    end
    local choices=Choices.parse(f.menu.aggregate.manifest)
    local model=Choices.open({id='layout-check',path=paths.manifest,choices=choices,testOnly=false})
    assert(not model.error,model.error)
    assert(model.path==paths.config)
    assert(io.open(root..'/identity-catalog.lua')==nil and io.open(root..'/menu-pages.lua')==nil
        and io.open(root..'/config.ini')==nil)
    local manifest=assert(io.open(paths.manifest)); manifest:close()
    assert(Files.readCatalog(root).next==f.menu.catalog.next)
end)

test('module settings are initialized in each template module folder', function()
    local modules=testRoot..'/module-configs'
    Layout.prepare(modules..'/Alpha')
    Layout.prepare(modules..'/Beta')
    local f=fixture(true,'module','module',modules)
    local definitions={category=f.category,[f.locations[1]]=f.a,[f.locations[2]]=f.b}
    local menuRoot=testRoot..'/module-menu'
    local legacyPath=Layout.prepare(menuRoot).config
    local legacy=assert(io.open(legacyPath,'wb'))
    legacy:write('[Templates]\n'..f.definitions.Beta.settings.Size..'=73\n');legacy:close()
    local barrier
    local boot=Bootstrap.new({host=f.host,categories={f.category},
        execute=function(path) return definitions[path] end,menuRoot=menuRoot,
        subscribeLoopStart=function(cb) barrier=cb; return function() end end})
    for _,location in ipairs(f.locations) do boot:registerTemplate(location) end
    barrier()
    assert(boot.phase=='running',f.errors[1] and f.errors[1].message)
    for _,name in ipairs({'Alpha','Beta'}) do
        local input=assert(io.open(modules..'/'..name..'/config.ini','rb'))
        local content=input:read('*a');input:close()
        assert(content:find('[Templates]',1,true))
        if name=='Beta' then
            assert(content:find(f.definitions.Beta.settings.Size..'=73',1,true))
        end
    end
    local central=assert(io.open(menuRoot..'/Scripts/cache/config.ini','rb'))
    local centralContent=central:read('*a');central:close()
    assert(not centralContent:find(f.definitions.Alpha.settings.Size,1,true)
        and centralContent:find(f.definitions.Beta.settings.Size..'=73',1,true),
        'legacy central value must remain while new module defaults stay local')
    boot:stop()
end)

test('empty template menus still create a readable config', function()
    local paths=Layout.prepare(testRoot..'/empty-templates')
    assert(Files.ensureConfig(paths.config,{},{}))
    local input=assert(io.open(paths.config,'rb'))
    local content=input:read('*a');input:close()
    assert(content=='[Templates]\n')
    assert(next(Files.readConfigValues(paths.config,{},{}))==nil)
end)

print('PASS: '..passed..' MCT menu integration tests (actual DMM parser and presentation)')
