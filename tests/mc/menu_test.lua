package.path = './Scripts/?.lua;./Scripts/vendor/?.lua;' .. package.path
local Model = require('mc.menu_model')
local Menu = require('mc.menu')
local Runtime = require('mc.runtime')
local Controller = require('mc.menu_controller')
local Files = require('mc.menu_files')
local Contribution = require('mc.menu_contribution')
local Contributions = require('menu_contributions')
local Bootstrap = require('mc.bootstrap')
local Layout = require('mc.layout')
local U = require('mc.util')
-- MCT reaches the menu through ModCoreSettings. The real DMM parser and MCS
-- presentation are optional compatibility checks, run only when both are given.
local choicesPath, presentationPath = os.getenv('MCT_DMM_CHOICES'), os.getenv('MCT_PRESENTATION')
assert((choicesPath == nil) == (presentationPath == nil),
    'set both MCT_DMM_CHOICES and MCT_PRESENTATION, or neither')
local Choices = choicesPath and dofile(choicesPath)
local Presentation = presentationPath and dofile(presentationPath)
local testRoot = assert(os.getenv('MCT_TEST_DIR'), 'MCT_TEST_DIR required')
-- Published page paths must be absolute, so resolve a relative scratch directory against the working directory.
if testRoot:sub(1, 1) ~= '/' then testRoot = assert(os.getenv('PWD'), 'PWD required') .. '/' .. testRoot end
local passed, skipped = 0, 0
local function test(name, body)
    local ok, why = pcall(body)
    assert(ok, name .. ': ' .. tostring(why))
    passed = passed + 1
end
local function compatibility(name, body)
    if Choices then return test(name, body) end
    skipped = skipped + 1
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

compatibility('copied manifests parse with actual DMM and ModCoreSettings', function()
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

test('generated controls do not assign secondary levels or default tabs', function()
    for _, single in ipairs({true, false}) do
        local f=fixture(single)
        for _, provider in pairs(f.menu.providers) do
            for _, row in ipairs(provider.rows) do
                assert(row.mcLevel==nil, row.Id .. ': unexpected level')
                assert(row.mcType~='tab', row.Id .. ': unexpected tab')
            end
            assert(not provider.manifest:find('mcLevel=[1-6]'))
        end
    end
end)

test('module-target templates do not add controls to the MCT aggregate page', function()
    local mixed=fixture(true)
    assert(#mixed.menu.aggregate.rows==0)
    assert(#mixed.menu.pageByModule.Beta.rows>0)
    local moduleOnly=fixture(true,'module','module')
    assert(#moduleOnly.menu.aggregate.rows==0 and #moduleOnly.menu.pages==2)
    assert(moduleOnly.menu.pageByModule.Alpha and moduleOnly.menu.pageByModule.Beta)
    local pages=Contribution.build(moduleOnly.menu,'/Mods/3_ModCore_Templates').pages
    assert(#pages==3 and pages[1].id=='ModCoreTemplates' and pages[1].visible==false
        and pages[1].manifest==nil,'an empty aggregate is hidden')
    for index=2,3 do
        local page=pages[index]
        assert(page.group=='module' and page.attach==page.name and page.under==nil)
        assert(page.configDirectory=='/Mods/'..page.name and page.manifest:find('[Setting.',1,true))
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

test('menu contribution validates and orders the aggregate before its category pages', function()
    local f=fixture(true)
    local contribution=Contribution.build(f.menu,'/Mods/3_ModCore_Templates/')
    assert(Contributions.validate('ModCoreTemplates',contribution))
    local pages=contribution.pages
    assert(pages[1].id=='ModCoreTemplates' and pages[1].attach=='3_ModCore_Templates'
        and pages[1].visible==true,'category pages show the aggregate in place of the MCT folder entry')
    local category=pages[2]
    assert(category.id==f.menu.pageByCategory['player.quickslots'].id and category.under=='ModCoreTemplates'
        and category.configDirectory=='/Mods/3_ModCore_Templates' and category.attach==nil)
    local beta=pages[3]
    assert(beta.id=='ModCoreTemplates.module.Beta' and beta.author=='Example Author'
        and beta.group=='module' and beta.attach=='Beta')
end)

test('templates get no automatic Control Layout link', function()
    local f=fixture(true)
    assert(f.definitions.Beta.navigation.ControlLayoutLink==nil)
    for _,row in ipairs(f.menu.rows) do assert(row.Label~='Control Layout',row.Id) end
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
    assert(boot.menu and #f.calls==1)
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

test('invalid saved config falls back to its default without blocking startup', function()
    local f=fixture(true)
    local path=testRoot..'/invalid.ini'
    local id=f.definitions.Alpha.settings.Size
    local out=assert(io.open(path,'w')); out:write('[Templates]\n'..id..'=999\n'); out:close()
    assert(Files.ensureConfig(path,f.menu.rows,f.menu.textSettings))
    local default
    for _,row in ipairs(f.menu.rows) do if row.Id==id then default=tonumber(row.Default) end end
    local values=Files.readConfigValues(path,f.menu.textSettings,f.menu.rows)
    assert(default and values[id]==default)
end)

test('generated data goes into Scripts/cache', function()
    local f=fixture(true,'templates','templates')
    local root=testRoot..'/new-layout'
    local paths=Layout.prepare(root)
    Files.publish(root,f.menu)
    Files.ensureConfig(paths.config,f.menu.rows,f.menu.textSettings)
    for _,row in ipairs(f.menu.rows) do
        if row.mcNavigation~=1 then assert(row.ConfigFile=='Scripts/cache/config.ini') end
    end
    if Choices then
        -- ModCoreSettings resolves ConfigFile against configDirectory as DMM does for mod_settings.ini.
        local choices=Choices.parse(f.menu.aggregate.manifest)
        local model=Choices.open({id='layout-check',path=root..'/mod_settings.ini',choices=choices,testOnly=false})
        assert(not model.error,model.error)
        assert(model.path==paths.config,'DMM resolves the nested config')
    end
    assert(io.open(root..'/identity-catalog.lua')==nil and io.open(root..'/menu-pages.lua')==nil
        and io.open(root..'/config.ini')==nil)
    for _,path in ipairs(paths.retired) do assert(io.open(path)==nil,'retired menu file was published') end
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

test('publishing removes files left by the former DMM handoff', function()
    local f=fixture(true)
    local root=testRoot..'/retired'
    local paths=Layout.prepare(root)
    for _,path in ipairs(paths.retired) do
        local out=assert(io.open(path,'wb')); out:write('[Mod]\nId=ModCoreTemplates\n'); out:close()
    end
    Files.publish(root,f.menu)
    for _,path in ipairs(paths.retired) do assert(io.open(path)==nil,path..' must be removed') end
end)

test('bootstrap publishes menu pages through ModCoreSettings and withdraws them on stop', function()
    local modules=testRoot..'/published-modules'
    Layout.prepare(modules..'/Alpha'); Layout.prepare(modules..'/Beta')
    local f=fixture(true,nil,nil,modules)
    local root=testRoot..'/published'
    Layout.prepare(root)
    local values={}
    local shared={GetSharedVariable=function(_,key) return values[key] end,
        SetSharedVariable=function(_,key,value) values[key]=value end}
    local barrier
    local definitions={category=f.category,[f.locations[1]]=f.a,[f.locations[2]]=f.b}
    local boot=Bootstrap.new({host=f.host,categories={f.category},menuRoot=root,menuShared=shared,
        execute=function(path) return definitions[path] end,
        subscribeLoopStart=function(cb) barrier=cb; return function() end end})
    for _,location in ipairs(f.locations) do boot:registerTemplate(location) end
    assert(values[Contributions.prefix..Contributions.hex('ModCoreTemplates')]==nil,'nothing is published before the barrier')
    barrier()
    assert(boot.phase=='running',f.errors[1] and f.errors[1].message)
    local generation,path=Contributions.slot(values[Contributions.prefix..Contributions.hex('ModCoreTemplates')])
    assert(generation==1 and path:find(root..'/Scripts/cache/',1,true)==1)
    local function read(file)
        local input=assert(io.open(file,'rb')); local content=input:read('*a'); input:close()
        return content
    end
    local decoded=Contributions.decode(read(path),function(name) return read(root..'/Scripts/cache/'..name) end)
    assert(decoded.id=='ModCoreTemplates' and decoded.pages[1].id=='ModCoreTemplates'
        and decoded.pages[1].attach=='published' and #decoded.pages==3)
    assert(values[Contributions.index]==Contributions.hex('ModCoreTemplates'))
    boot:stop()
    local _,withdrawn=Contributions.slot(values[Contributions.prefix..Contributions.hex('ModCoreTemplates')])
    assert(withdrawn=='' and io.open(path)==nil,'stopping withdraws the published pages')
end)

test('a failed menu publish is reported and the templates keep running', function()
    local modules=testRoot..'/unpublished-modules'
    Layout.prepare(modules..'/Alpha'); Layout.prepare(modules..'/Beta')
    local f=fixture(true,nil,nil,modules)
    local root=testRoot..'/unpublished'
    Layout.prepare(root)
    local barrier
    local definitions={category=f.category,[f.locations[1]]=f.a,[f.locations[2]]=f.b}
    local boot=Bootstrap.new({host=f.host,categories={f.category},menuRoot=root,
        menuShared={GetSharedVariable=function() end,
            SetSharedVariable=function() error('shared variables locked') end},
        execute=function(path) return definitions[path] end,
        subscribeLoopStart=function(cb) barrier=cb; return function() end end})
    for _,location in ipairs(f.locations) do boot:registerTemplate(location) end
    barrier()
    assert(boot.phase=='running' and boot.runtime)
    local reported
    for _,e in ipairs(f.errors) do if e.stage=='menu' then reported=e.message end end
    assert(reported and reported:find('shared variables locked',1,true),'publish failure must be reported')
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

local orientation={[7]='Horizontal',[5]='Vertical'}
local function barsGroup()
    return {id='Bars',label='Bars',fields={
        {id='.A',label='Orientation',values=orientation,default=7},
        {id='.KH',label='Horizontal Keys',values={[0]='Above',[1]='Below'},default=0,
            conditions={visible={field='.A',match={7}}}},
        {id='.KV',label='Vertical Keys',values={[0]='Left',[1]='Right'},default=1,
            conditions={visible={field='.A',match={5}},
                label={field='.A',match={5},text='Side Keys'}}},
    }}
end
local function slotFixture(locationBase, extraFields, conditional)
    local f=fixture(true,'module','module',locationBase)
    f.category.slot={provider='controls',slot='visuals'}
    f.a.variations={style={values={[0]='Swap',[1]='Stack'},default=0}}
    f.a.menu={{id='Layout',label='Layout',fields={field('Size',20)}},
        {id='Extra',label='Extra',variation={style=1},fields={field('.Gap',5)}}}
    if conditional then f.a.menu[#f.a.menu+1]=barsGroup() end
    for n=1,extraFields or 0 do
        table.insert(f.b.menu[1].fields,field('F'..n,0))
    end
    local model=Model.build({f.category},{f.a,f.b},f.locations)
    f.model,f.menu=model,Menu.generate(model.registry)
    local runtime=Runtime.new(f.host,model.categories,model.templates)
    f.runtime,f.controller=runtime,Controller.new(f.menu,runtime)
    runtime:start()
    f.definitions={}
    for _,definition in pairs(f.menu.definitions[f.category.name]) do f.definitions[definition.id]=definition end
    return f
end
local function section(manifest,id)
    local fields={}
    local body=assert((manifest..'\n\n'):match('%[Setting%.'..id:gsub('%p','%%%0')..'%]\n(.-)\n\n'),id)
    for key,value in body:gmatch('([^\n=]+)=([^\n]*)') do fields[key]=value end
    return fields
end

test('a slot category moves to one hidden page with flattened visibility', function()
    local f=slotFixture()
    local page=assert(f.menu.pageBySlot['player.quickslots'])
    assert(page.slot=='controls:visuals' and not page.category and not page.module)
    assert(#f.menu.aggregate.rows==0 and not f.menu.pageByCategory['player.quickslots'])
    assert(not f.menu.pageByModule.Alpha.module and not f.menu.pageByModule.Beta.module,
        'slot templates leave their own module configs')
    local selector=f.menu.selectors['player.quickslots']
    local alpha,beta
    for value,id in pairs(selector.byValue) do if id=='Alpha' then alpha=value else beta=value end end
    assert(page.rows[1].Id==selector.id,'Template comes first')
    local template=section(page.manifest,selector.id)
    assert(template.VisibleWhen==nil and template.Group=='Slot' and template.mcHeading==nil)
    local shared=section(page.manifest,f.menu.categorySettings['player.quickslots'].fields.Size)
    assert(shared.VisibleWhen==selector.id and shared.VisibleValues==alpha..'|'..beta
        or shared.VisibleValues==beta..'|'..alpha)
    local size=section(page.manifest,f.definitions.Alpha.settings.Size)
    assert(size.VisibleWhen==selector.id and size.VisibleValues==tostring(alpha))
    local gap=section(page.manifest,f.definitions.Alpha.settings.ExtraGap)
    assert(gap.VisibleWhen==f.definitions.Alpha.settings.Style and gap.VisibleValues=='1',
        'variation groups gate through their variation row')
    local style=section(page.manifest,f.definitions.Alpha.settings.Style)
    assert(style.VisibleWhen==selector.id and style.VisibleValues==tostring(alpha))
    local seen={}
    for index,row in ipairs(page.rows) do
        assert(row.mcNavigation~=1,'navigation links stay out of the slot')
        assert(row.ConfigFile=='Scripts/cache/config.ini')
        local rule=section(page.manifest,row.Id).VisibleWhen
        assert(rule==nil or seen[rule],row.Id..': rule must name an earlier slot row')
        seen[row.Id]=index
    end
    assert(not page.manifest:find('%[Category%.[^S]'),'source Category rules are not published')
end)

test('the template picker notes each choice with its module', function()
    local f=fixture(true,'module','module')
    f.category.slot={provider='controls',slot='visuals'}
    local function generate()
        local model=Model.build({f.category},{U.copy(f.a),U.copy(f.b)},f.locations)
        return Menu.generate(model.registry)
    end
    -- Without module metadata the picker keeps one line per choice.
    local menu=generate()
    local selector=menu.selectors['player.quickslots']
    local page=menu.pageBySlot['player.quickslots']
    assert(section(page.manifest,selector.id).mcChoiceNotes==nil)
    f.a.module,f.b.module='Alpha','Beta'
    menu=generate()
    selector,page=menu.selectors['player.quickslots'],menu.pageBySlot['player.quickslots']
    local expected={}
    for value,id in pairs(selector.byValue) do expected[tostring(value)]=id end
    local notes,count=section(page.manifest,selector.id).mcChoiceNotes,0
    for value,text in assert(notes):gmatch('([^:;]+):([^;]+)') do
        assert(expected[value]==text and value~='0','None has no note: '..value)
        expected[value]=nil;count=count+1
    end
    assert(count==2 and next(expected)==nil)
    if Choices then
        local choices=Choices.parse(page.manifest)
        Presentation.parse(page.manifest,choices)
    end
    -- A template without a module has no note; the others keep theirs.
    f.b.module=nil
    menu=generate()
    notes=section(menu.pageBySlot['player.quickslots'].manifest,
        menu.selectors['player.quickslots'].id).mcChoiceNotes
    assert(notes:match('^%d+:Alpha$'),notes)
    -- Notes follow the menu text rules and fit MCS's 64-character limit.
    f.b.module=('x'):rep(65)
    assert(not pcall(generate))
    f.b.module='Beta;Two'
    assert(not pcall(generate))
end)

local function conditionalPage()
    local f=fixture(true,'module','module')
    f.a.menu={barsGroup()}
    local model=Model.build({f.category},{f.a,f.b},f.locations)
    local menu=Menu.generate(model.registry)
    local definition
    for _,candidate in pairs(menu.definitions[f.category.name]) do
        if candidate.id=='Alpha' then definition=candidate end
    end
    return menu.pageByModule.Alpha,definition.settings,menu.selectors['player.quickslots']
end

test('field conditions become row visibility and label rules', function()
    local page,ids=conditionalPage()
    local kh,kv=section(page.manifest,ids.BarsKH),section(page.manifest,ids.BarsKV)
    assert(kh.VisibleWhen==ids.BarsA and kh.VisibleValues=='7' and kh.mcLabelWhen==nil)
    assert(kv.VisibleWhen==ids.BarsA and kv.VisibleValues=='5')
    assert(kv.mcLabelWhen==ids.BarsA and kv.mcLabels=='5:Side Keys' and kv.Label=='Vertical Keys')
    local a=section(page.manifest,ids.BarsA)
    assert(a.VisibleWhen==nil and a.mcLabelWhen==nil,'fields without conditions are unchanged')
    -- The template picker still gates the group through its Category rule.
    local group=assert((page.manifest..'\n\n'):match('%[Category%.'..kh.Group..'%]\n(.-)\n\n'))
    assert(group:find('VisibleWhen=',1,true),'the group keeps its template-picker rule')
end)

compatibility('field conditions hide and relabel rows live in DMM', function()
    local page,ids,selector=conditionalPage()
    local choices=Choices.parse(page.manifest)
    Presentation.parse(page.manifest,choices)
    local model=Choices.open({id=page.id,choices=choices,testOnly=true})
    assert(not model.error,model.error)
    local index={}
    for i,setting in ipairs(model.items) do index[setting.id]=i end
    local alpha
    for value,id in pairs(selector.byValue) do if id=='Alpha' then alpha=value end end
    if index[selector.id] then model:set(index[selector.id],alpha) end
    local visible=model:visibility()
    assert(visible[index[ids.BarsKH]] and not visible[index[ids.BarsKV]],'Horizontal shows KH')
    model:set(index[ids.BarsA],5)
    visible=model:visibility()
    assert(not visible[index[ids.BarsKH]] and visible[index[ids.BarsKV]],'Vertical shows KV')
    local rule=model.items[index[ids.BarsKV]].mcLabelRule
    assert(rule and rule.values[5]=='Side Keys' and rule.values[7]==nil)
    if index[selector.id] then
        model:set(index[selector.id],0)
        visible=model:visibility()
        assert(not visible[index[ids.BarsA]] and not visible[index[ids.BarsKV]],'None hides the template')
    end
end)

test('slot rows take field conditions and hidden values still apply', function()
    local f=slotFixture(nil,nil,true)
    local page=f.menu.pageBySlot['player.quickslots']
    local ids=f.definitions.Alpha.settings
    local kh,kv=section(page.manifest,ids.BarsKH),section(page.manifest,ids.BarsKV)
    assert(kh.VisibleWhen==ids.BarsA and kh.VisibleValues=='7')
    assert(kv.VisibleWhen==ids.BarsA and kv.VisibleValues=='5' and kv.mcLabels=='5:Side Keys')
    local selector=f.menu.selectors['player.quickslots']
    assert(section(page.manifest,ids.BarsA).VisibleWhen==selector.id,'the source keeps the template rule')
    f.controller:apply(event(f,page,1,function(v)
        f.choose(v,'Alpha',true); v[ids.BarsA]=5; v[ids.BarsKH]=1
    end))
    local settings=f.calls[1].settings
    assert(f.calls[1].operation=='attach' and settings.BarsA==5 and settings.BarsKH==1
        and settings.BarsKV==1,'hidden fields keep and deliver their values')
end)

test('slot pages publish hidden with rows addressed to the slot', function()
    local f=slotFixture(nil,40)
    local contribution=Contribution.build(f.menu,'/Mods/3_ModCore_Templates')
    assert(Contributions.validate('ModCoreTemplates',contribution))
    local page=f.menu.pageBySlot['player.quickslots']
    local published
    for _,candidate in ipairs(contribution.pages) do if candidate.id==page.id then published=candidate end end
    assert(published.visible==false and published.configDirectory=='/Mods/3_ModCore_Templates')
    assert(published.under=='ModCoreTemplates','the fallback page sits under the aggregate')
    assert(#contribution.rows==math.ceil(#page.rows/32) and #contribution.rows>1,'rows are chunked')
    local ids={}
    for _,row in ipairs(contribution.rows) do
        assert(row.page==page.id and row.slot=='controls:visuals' and #row.settings<=32)
        for _,id in ipairs(row.settings) do ids[#ids+1]=id end
    end
    for index,row in ipairs(page.rows) do assert(ids[index]==row.Id) end
    local plain=Contribution.build(fixture(true).menu,'/Mods/3_ModCore_Templates')
    assert(plain.rows==nil,'without slots the contribution keeps contract 1')
end)

test('modules whose templates moved to a slot keep their page with a link to the slot', function()
    local f=slotFixture()
    local contribution=Contribution.build(f.menu,'/Mods/3_ModCore_Templates')
    assert(Contributions.validate('ModCoreTemplates',contribution))
    local merged={}
    for _,page in ipairs(contribution.pages) do
        assert(not page.link,'merged modules publish pages, not link entries')
        if page.group=='module' then merged[#merged+1]=page end
    end
    assert(#merged==2 and merged[1].id=='ModCoreTemplates.module.Alpha' and merged[2].id=='ModCoreTemplates.module.Beta')
    local beta=merged[2]
    assert(beta.attach=='Beta' and beta.author=='Example Author'
        and beta.configDirectory=='/Mods/3_ModCore_Templates','merged pages store in the central config')
    local page=f.menu.pageByModule.Beta
    assert(f.menu.providers[beta.id]==page and page.merged=='controls:visuals')
    local notice=section(page.manifest,'MCT_MergedNotice')
    assert(page.rows[1].Id=='MCT_MergedNotice' and notice.mcLinkPage=='controls:visuals'
        and notice.mcNavigation=='1' and notice.mcType=='tab' and notice.mcLevel=='5'
        and notice.PresetLabels=='Controls|Controls' and notice.ConfigFile==nil)
    assert(notice.Label=='These settings have been merged into Controls and can also be edited there')
    local selector=f.menu.selectors['player.quickslots']
    local size=section(page.manifest,f.definitions.Beta.settings.Size)
    assert(section(page.manifest,selector.id) and size.ConfigFile=='Scripts/cache/config.ini',
        'the page edits the slot rows in the central config')
    assert(page.rows[2].Id==selector.id and section(page.manifest,selector.id).mcHeading==nil
        and section(page.manifest,selector.id).mcLevel==nil,
        'the template picker follows the notice as a plain row, not in the title row')
    assert(f.menu.selectors['player.quickslots'] and f.menu.pageBySlot['player.quickslots'].rows[1].Id==selector.id)
    assert(not page.manifest:find('Setting.'..f.definitions.Alpha.settings.Size,1,true),'only its own templates')
    for index,row in ipairs(page.rows) do
        assert(index==1 or row.mcNavigation~=1,row.Id..': the notice is the only link')
    end
    assert(not page.manifest:find('Label=Control Layout',1,true))
    if Choices then
        local items=Presentation.parse(page.manifest,Choices.parse(page.manifest))
        assert(items[1].id=='MCT_MergedNotice' and items[1].mcTabs and items[1].mcFont==5,
            'the notice renders as a small label with one link button')
    end
    -- Apply from the module page reaches the runtime like the slot page.
    f.controller:apply(event(f,page,1,function(v) f.choose(v,'Beta',true);v[f.definitions.Beta.settings.Size]=42 end))
    assert(#f.calls==1 and f.calls[1].id=='Beta' and f.calls[1].settings.Size==42)
    -- A module that still has its own settings keeps its own page.
    local other={name='player.stats',single=true,objects={root={source='lookup',object='switcher'}}}
    local extra={id='Gamma',name='Gamma',category='player.stats',objects={'root'},managed=false,
        menu={{id='Layout',label='Layout',fields={field('Size',20)}}},
        attach=function() end,update=function() end,detach=function() end}
    local model=Model.build({f.category,other},{f.a,f.b,extra},
        {f.locations[1],f.locations[2],'/Mods/Beta/Scripts/templates/other.lua'})
    local menu=Menu.generate(model.registry)
    assert(menu.pageByModule.Beta.module=='Beta' and not menu.pageByModule.Beta.merged)
    assert(menu.pageByModule.Alpha.merged=='controls:visuals')
end)

test('slot Apply selects templates and updates their settings', function()
    local f=slotFixture()
    local page=f.menu.pageBySlot['player.quickslots']
    f.controller:apply(event(f,page,1,function(v) f.choose(v,'Alpha',true) end))
    assert(#f.calls==1 and f.calls[1].operation=='attach' and f.calls[1].id=='Alpha')
    f.controller:apply(event(f,page,2,function(v) v[f.definitions.Alpha.settings.Size]=64 end))
    assert(f.calls[2].operation=='update' and f.calls[2].settings.Size==64)
    f.controller:apply(event(f,page,3,function(v) f.choose(v,'Alpha',false) end))
    assert(f.calls[3].operation=='detach','None detaches')
end)

test('slot values are copied once from module configs to the central config', function()
    local modules=testRoot..'/slot-modules'
    Layout.prepare(modules..'/Alpha'); Layout.prepare(modules..'/Beta')
    local f=slotFixture(modules)
    local selector=f.menu.selectors['player.quickslots']
    local beta
    for value,id in pairs(selector.byValue) do if id=='Beta' then beta=value end end
    local betaSize,alphaSize=f.definitions.Beta.settings.Size,f.definitions.Alpha.settings.Size
    local function write(path,content)
        local out=assert(io.open(path,'wb')); out:write(content); out:close()
    end
    local function read(path)
        local input=assert(io.open(path,'rb')); local content=input:read('*a'); input:close()
        return content
    end
    f.category.retired={'MCT_OldA','MCT_OldB'}
    local moduleConfig=('[Other]\nKeep=1\nMCT_OldA=3\n[Templates]\n'..selector.id..'='..beta..'\n'..betaSize..'=999\n'
        ..'MCT_OldA=1\n'..alphaSize..'=33\nForeign=7\nMCT_OldB = 2\n'):gsub('\n','\r\n')
    local cleaned=moduleConfig:gsub('\r\nMCT_OldA=1',''):gsub('\r\nMCT_OldB = 2','')
    write(modules..'/Beta/config.ini',moduleConfig)
    local menuRoot=testRoot..'/slot-menu'
    local centralPath=Layout.prepare(menuRoot).config
    -- A stale central copy loses to the module value that was in effect before the move.
    -- Unknown and legacy keys are ignored, even repeated or non-numeric.
    write(centralPath,'[Templates]\n'..alphaSize..'=11\nLegacy=1\nLegacy=x\nMCT_WheelsX=5\n')
    local definitions={category=f.category,[f.locations[1]]=f.a,[f.locations[2]]=f.b}
    local function start()
        local barrier
        local boot=Bootstrap.new({host=f.host,categories={f.category},menuRoot=menuRoot,
            execute=function(path) return definitions[path] end,
            subscribeLoopStart=function(cb) barrier=cb; return function() end end})
        for _,location in ipairs(f.locations) do boot:registerTemplate(location) end
        barrier()
        assert(boot.phase=='running',f.errors[1] and f.errors[1].message)
        return boot
    end
    local boot=start()
    local central=read(centralPath)
    assert(central:find(selector.id..'='..beta,1,true) and central:find(alphaSize..'=33',1,true),central)
    assert(central:find(betaSize..'=20',1,true),'invalid saved values fall back to defaults')
    assert(read(modules..'/Beta/config.ini')==cleaned,
        'only retired Templates lines go; migrated copies, other sections and CRLF stay')
    assert(io.open(modules..'/Alpha/config.ini')==nil,'a missing module config is not created')
    assert(next(Files.readSection(centralPath,'Migrations'))==nil,'nothing is marked while a config is missing')
    assert(boot.menuController:values()[selector.id]==beta)
    assert(#f.calls==1 and f.calls[1].id=='Beta' and f.calls[1].operation=='attach')
    boot:stop()
    -- A config that appears later is still copied and cleaned; then both are marked.
    write(modules..'/Alpha/config.ini','[Templates]\nMCT_OldB=4\n')
    boot=start()
    assert(read(modules..'/Alpha/config.ini')=='[Templates]\n')
    central=read(centralPath)
    local done=Files.readSection(centralPath,'Migrations')
    assert(done['slot.player.quickslots']=='1' and done['retired.MCT_OldA']=='1'
        and done['retired.MCT_OldB']=='1',central)
    boot:stop()
    -- Once done, the central config wins and later starts change nothing, even if a
    -- retired key reappears.
    local later=cleaned:gsub(alphaSize..'=33',alphaSize..'=44')..'MCT_OldA=9\r\n'
    write(modules..'/Beta/config.ini',later)
    boot=start()
    assert(read(centralPath)==central,'the second start rewrites nothing')
    assert(read(modules..'/Beta/config.ini')==later,'each cleanup runs once')
    assert(boot.menuController:values()[alphaSize]==33)
    boot:stop()
end)

compatibility('slot rows splice into the host slot and Apply reaches the runtime', function()
    local scripts=assert(presentationPath:match('^(.*)[/\\][^/\\]+$'))
    local savedPath=package.path
    package.path=scripts..'/?.lua;'..package.path
    local Navigation,Slots=require('navigation'),require('menu_slots')
    package.path=savedPath
    local choices=dofile(choicesPath)
    assert(Navigation.install(choices))
    local logs={}
    local slots=assert(Slots.install(choices,function(e,d) logs[#logs+1]=e..' '..tostring(d) end,Contributions))
    local files={}
    choices.fs={read=function(path) return files[path] end,
        write=function(path,content) files[path]=content end,
        rename=function(a,b) files[b]=assert(files[a]);files[a]=nil end,
        remove=function(path) files[path]=nil end}
    local host=table.concat({'[Mod]','Id=ModCoreControls','Name=Controls',
        '[Setting.MCC_Page]','Id=MCC_Page','Type=picker','Label=Page','Group=Pages',
        'PresetValues=0|1','PresetLabels=Options|Visuals','Default=0','mcNavigation=1',
        '[Category.Visuals]','VisibleWhen=MCC_Page','VisibleValues=1',
        '[Setting.MCC_Visuals_Pending]','Id=MCC_Visuals_Pending','Type=picker','Label=Quickslot templates',
        'Group=Visuals','PresetValues=0|1','PresetLabels=Coming|Coming','Default=0','mcReadOnly=1',
        'mcSlot=visuals',
        '[Setting.Speed]','Id=Speed','Type=picker','Label=Speed','Group=Options','PresetValues=0|1',
        'PresetLabels=Slow|Fast','Default=0','VisibleWhen=MCC_Page','VisibleValues=0',
        'ConfigFile=config.ini','ConfigSection=Main','ConfigKey=Speed',''},'\n')
    files['/mcc/config.ini'],files['/mcc/mod_settings.ini']='[Main]\nSpeed=0\n',host
    local f=slotFixture(nil,nil,true)
    local page=f.menu.pageBySlot['player.quickslots']
    local config={'[Templates]'}
    for _,row in ipairs(page.rows) do config[#config+1]=row.Id..'='..row.Default end
    files['/mct/Scripts/cache/config.ini']=table.concat(config,'\n')..'\n'
    local mcc={id='ModCoreControls',name='Controls',path='/mcc/mod_settings.ini',
        choices=choices.parse(host),settingsCount=3,testOnly=false}
    local source={id=page.id,name=page.name,path='/mct/mod_settings.ini',choices=choices.parse(page.manifest),
        settingsCount=#page.rows,mcManifest=page.manifest,testOnly=false}
    local inserts={}
    for _,row in ipairs(Contribution.build(f.menu,'/mct').rows) do
        local provider,name=Contributions.address(row.slot)
        assert(provider==Contributions.provider('ModCoreControls') and name=='visuals')
        inserts[#inserts+1]={contributor='ModCoreTemplates',source=source,settings=row.settings}
    end
    slots.inserts={[Contributions.provider('ModCoreControls')]={visuals=inserts}}
    local events={}
    slots.applied=function(provider,event) events[#events+1]={id=provider.id,event=event} end
    assert(slots:load(mcc,function(path) return files[path] end) and #logs==0,logs[1])
    assert(#mcc.choices==2+#page.rows,'every slot row was inserted')
    local index={}
    for i,setting in ipairs(mcc.choices) do index[setting.id]=i end
    local selector=f.menu.selectors['player.quickslots']
    local alpha
    for value,id in pairs(selector.byValue) do if id=='Alpha' then alpha=value end end
    local model=choices.open(mcc)
    assert(not model.error,model.error)
    model:set(index.MCC_Page,1)
    local alphaSize=index[f.definitions.Alpha.settings.Size]
    local visible=model:visibility()
    assert(visible[index[selector.id]] and not visible[alphaSize],'None shows only the Template row')
    model:set(index[selector.id],alpha)
    visible=model:visibility()
    assert(visible[alphaSize] and not visible[index[f.definitions.Alpha.settings.ExtraGap]]
        and not visible[index[f.definitions.Beta.settings.Size]],'the selection gates its own rows')
    model:set(index[f.definitions.Alpha.settings.Style],1)
    assert(model:visibility()[index[f.definitions.Alpha.settings.ExtraGap]],'variation rows follow the variation')
    local bars=f.definitions.Alpha.settings
    visible=model:visibility()
    assert(visible[index[bars.BarsKH]] and not visible[index[bars.BarsKV]],'slot: Horizontal shows KH')
    model:set(index[bars.BarsA],5)
    visible=model:visibility()
    assert(not visible[index[bars.BarsKH]] and visible[index[bars.BarsKV]],'slot: Vertical shows KV')
    model:set(index[selector.id],0)
    assert(not model:visibility()[index[bars.BarsKV]],'slot: the template picker still gates conditioned rows')
    model:set(index[selector.id],alpha)
    model:set(index[bars.BarsA],7)
    model:set(index.MCC_Page,0)
    assert(not model:visibility()[alphaSize],'the host page gates the slot')
    model:set(alphaSize,64)
    local ok,err=model:apply()
    assert(ok,err)
    assert(#events==1 and events[1].id==page.id)
    f.controller:apply({providerId=page.id,revision=1,values=events[1].event.values})
    assert(#f.calls==1 and f.calls[1].id=='Alpha' and f.calls[1].operation=='attach'
        and f.calls[1].settings.Size==64)
    assert(files['/mcc/config.ini']=='[Main]\nSpeed=0\n','the host config never sees slot values')
end)

test('category slots are validated', function()
    local function rejects(slot,single,pattern)
        local ok,why=pcall(Model.build,{{name='player.quickslots',single=single,slot=slot}},{},{})
        assert(not ok and tostring(why):find(pattern,1,true),tostring(why))
    end
    rejects('controls:visuals',true,'must be a table')
    rejects({provider='controls',slot='visuals',extra=1},true,'unknown field')
    rejects({provider='controls'},true,'slot.slot')
    rejects({provider='a b',slot='visuals'},true,'slot.provider')
    rejects({provider='controls',slot='visuals'},false,'requires a single category')
    local ok,why=pcall(Model.build,{{name='player.quickslots',single=true,retired={'MCT_Old'}}},{},{})
    assert(not ok and tostring(why):find('requires a slot',1,true),tostring(why))
    ok,why=pcall(Model.build,{{name='player.quickslots',single=true,
        slot={provider='controls',slot='visuals'},retired={'Old'}}},{},{})
    assert(not ok and tostring(why):find('invalid setting id',1,true),tostring(why))
    local live=slotFixture()
    live.category.retired={live.definitions.Alpha.settings.Size}
    local model=Model.build({live.category},{live.a,live.b},live.locations)
    ok,why=pcall(Menu.generate,model.registry)
    assert(not ok and tostring(why):find('is still generated',1,true),tostring(why))
    local model=Model.build({{name='player.quickslots',single=true,slot={provider='controls',slot='visuals'}}},{},{})
    assert(model.registry.categories:getCategory('player.quickslots').slot=='controls:visuals')
end)

print('PASS: '..passed..' MCT menu tests'..(Choices and ' (with actual DMM parser and presentation)'
    or ' ('..skipped..' DMM compatibility test skipped)'))
