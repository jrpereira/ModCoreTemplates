package.path = './Scripts/?.lua;' .. package.path
local Model = require('mc.menu_model')
local Menu = require('mc.menu')
local Runtime = require('mc.runtime')
local Controller = require('mc.menu_controller')
local Files = require('mc.menu_files')
local Contribution = require('mc.menu_contribution')
local Contributions = require('mc.menu_contributions')
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
    local pages=Contribution.build(moduleOnly.menu,'/Mods/_ModCore_3_Templates').pages
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
    local contribution=Contribution.build(f.menu,'/Mods/_ModCore_3_Templates/')
    assert(Contributions.validate('ModCoreTemplates',contribution))
    local pages=contribution.pages
    assert(pages[1].id=='ModCoreTemplates' and pages[1].attach=='_ModCore_3_Templates'
        and pages[1].visible==true,'category pages show the aggregate in place of the MCT folder entry')
    local category=pages[2]
    assert(category.id==f.menu.pageByCategory['player.quickslots'].id and category.under=='ModCoreTemplates'
        and category.configDirectory=='/Mods/_ModCore_3_Templates' and category.attach==nil)
    local beta=pages[3]
    assert(beta.id=='ModCoreTemplates.module.Beta' and beta.author=='Example Author'
        and beta.group=='module' and beta.attach=='Beta')
end)

test('provider link is published as a ModCoreSettings page link', function()
    local f=fixture(true)
    local linkId=f.definitions.Beta.navigation.ControlLayoutLink
    local row
    for _,candidate in ipairs(f.menu.rows) do if candidate.Id==linkId then row=candidate end end
    assert(row and row.mcNavigation==1 and row.mcLinkPage=='ModCoreControls' and row.mcLinkProvider==nil)
    local manifest=f.menu.pageByModule.Beta.manifest
    local section=manifest:match('%[Setting%.'..linkId:gsub('%p','%%%0')..'%]\n(.-)\n\n')
    assert(section and section:find('mcLinkPage=ModCoreControls',1,true)
        and section:find('mcNavigation=1',1,true))
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

test('invalid saved config is reported without replacing user values', function()
    local f=fixture(true)
    local path=testRoot..'/invalid.ini'
    local contents='[Templates]\n'..f.definitions.Alpha.settings.Size..'=999\n'
    local out=assert(io.open(path,'w')); out:write(contents); out:close()
    assert(not pcall(Files.ensureConfig,path,f.menu.rows,f.menu.textSettings))
    local input=assert(io.open(path)); local actual=input:read('*a'); input:close()
    assert(actual==contents)
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

print('PASS: '..passed..' MCT menu tests'..(Choices and ' (with actual DMM parser and presentation)'
    or ' ('..skipped..' DMM compatibility test skipped)'))
