package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
-- Keyed template fields: fixed choices by key and {from=} entries that ModCoreSettings lists
-- from the template module's files each time the menu opens.
local Provider=require('mc.provider_settings')
local Model=require('mc.menu_model')
local Menu=require('mc.menu')
local From=require('menu_from')

local SOUNDS={{key='none',label='None'},{key='chime',label='Chime',note='flat',sound='/Game/A/Chime'},
    {from='choices/cue_sounds.lua'},{key='last',label='Last'}}
local _,groups=Provider.template({
    {id='Sound',label='Sound',fields={
        {id='.Incoming',label='Incoming',values=SOUNDS,default='ping'},
        {id='.Volume',label='Volume',values={min=0,max=200,step=10},default=100,
            conditions={visible={field='.Incoming',values={'none','chime'}}}},
        {id='.Style',label='Style',values={{key='off',label='Off'},{key='on',label='On'}},default='on'},
    }},
})
local incoming=groups[1].fields[1]
assert(incoming.keyed and incoming.listed and incoming.type=='enum','a keyed listed enum')
assert(table.concat(incoming.values,' ')=='none chime last','fixed keys are its values')
assert(#incoming.choices==4 and incoming.choices[3].from=='choices/cue_sounds.lua','choices keep their order')
assert(groups[1].fields[3].keyed and not groups[1].fields[3].listed,'keyed without a list')

local function rejects(menu,pattern)
    local ok,why=pcall(Provider.template,menu,{})
    assert(not ok and tostring(why):find(pattern,1,true),tostring(why))
end
rejects({{id='K',label='K',values={{key='a',label='A'}},default='a'}},'two choices or a from entry')
rejects({{id='K',label='K',values={{key='a',label='A'},{key='a',label='B'}},default='a'}},'duplicate key')
rejects({{id='K',label='K',values={{key='1',label='A'},{key='b',label='B'}},default='b'}},'not a number')
rejects({{id='K',label='K',values={{key='a',label='A'},{from='../x.lua'}},default='a'}},'relative')
rejects({{id='K',label='K',values={{key='a',label='A'},{from='x.lua',key='k'}},default='a'}},'unsupported property key')
rejects({{id='K',label='K',values={{key='a',label='A'},{key='b',label='B'}},default='c'}},'default must match a choice')
rejects({{id='K',label='K',values={{key='a',label='A'},{from='x.lua'}},default='c d'}},'default must match a choice')
rejects({{id='K',label='K',widget='tabs',values={{key='a',label='A'},{from='x.lua'}},default='a'}},'picker or cycler')
-- Rules name fixed keys only: listed keys are unknown until the menu opens.
rejects({{id='S',label='S',fields={
    {id='.K',label='K',values={{key='a',label='A'},{from='x.lua'}},default='a'},
    {id='.V',label='V',values={min=0,max=1},default=0,conditions={visible={field='.K',values={'ping'}}}},
}}},'distinct source choice')

-- Menu data: fixed choices as declared, from entries with the template module's folder.
local category={id='npc.attacks',objects={root={source='lookup',object='x'}},settings={constant=false}}
local template={id='Omens',category=category.id,objects={'root'},managed=false,menuTarget='templates',
    menu={{id='Sound',label='Sound',fields={{id='.Incoming',label='Incoming',values=SOUNDS,default='ping'}}}}}
template.providerId='P'
for _,operation in ipairs({'attach','update','detach'}) do template[operation]=function() end end
local model=Model.build({category},{template},{'/Mods/9_P/Scripts/mc_omens.lua'})
local menu=Menu.generate(model.registry)
local row
for _,candidate in ipairs(menu.rows) do if candidate.label=='Incoming' then row=candidate end end
assert(row and Menu.keyed(row) and row.default=='ping','a keyed row defaulting to a listed key')
assert(row.values[3].from=='choices/cue_sounds.lua' and row.values[3].root=='/Mods/9_P','from entries carry the module folder')
assert(row.values[2].sound=='/Game/A/Chime' and row.values[2].note=='flat','fixed choices keep notes and sounds')
-- Any well-formed key is accepted: the module's files decide what is offered.
assert(Menu.accepts(row,'chime') and Menu.accepts(row,'angel') and Menu.accepts(row,'gone_file'),'keys pass')
assert(not Menu.accepts(row,'3') and not Menu.accepts(row,'a b') and not Menu.accepts(row,7),'malformed keys do not')
local style={type='enum',values={{key='off',label='Off'},{key='on',label='On'}}}
assert(Menu.accepts(style,'on') and not Menu.accepts(style,'angel'),'without a list only its keys')

-- The published page carries the entry; ModCoreSettings' expander resolves it.
local published
for _,page in ipairs(menu.pages or {}) do
    for _,item in ipairs(page.menu and page.menu.fields or {}) do
        if item.id==row.id then published=page.menu end
    end
end
published=published or menu.menu
local found
for _,item in ipairs(published.fields) do if item.id==row.id then found=item end end
assert(found and found.values[3].from and found.values[3].root=='/Mods/9_P','published with its from entry')
local expand=From.expander({load=function(path,env)
    assert(path=='/Mods/9_P/Scripts/choices/cue_sounds.lua',path)
    return load([[return function(context)
        local out={}
        for _,name in ipairs(context.files('sounds')) do out[#out+1]={key=name:match('^cue_(%w+)'),label='X'} end
        return out
    end]],path,'t',env)
end,files=function(root,sub) assert(root=='/Mods/9_P' and sub=='sounds'); return {'cue_ping.wav'} end})
local resolved=expand(published)
for _,item in ipairs(resolved.fields) do
    if item.id==row.id then
        local keys={}
        for i,choice in ipairs(item.values) do keys[i]=choice.key end
        assert(table.concat(keys,' ')=='none chime ping last','resolved in place')
    end
end
print('PASS: keyed template fields with listed choices: declared, published with their module, accepted by key')
