package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
local List=require('mc.templates_list')
local Layout=require('mc.layout')
local Controller=require('mc.menu_controller')
local root=assert(os.getenv('MCT_TEST_DIR'),'MCT_TEST_DIR required')..'/TemplatesPage'
local paths=Layout.prepare(root)
assert(paths.templates==root..'/Scripts/cache/templates.lua')

-- The list holds every loaded template; a template its category selects is active.
local templates={
    {id='a',template={name='Wheels',category='player.quickslots',module='Fangdango'}},
    {id='b',template={name='Double Sidebar',category='player.quickslots',module='Fangdango'}},
    {id='c',template={name='Preymonition',category='npc.attacks',module='Preymonition'}},
    {id='d',template={name='Built In "Quoted"',category='player.quickslots'}},
}
local state={['player.quickslots']={settings={},selections={b={}}},['npc.attacks']={settings={},selections={}}}
local categories={'npc.attacks','npc.intent','player.compass','player.quickslots'}
local text=List.encode(templates,state,'controls:visuals',categories)
local file=assert(io.open(paths.templates,'wb'));file:write(text);file:close()
local list=assert(load(text,'list','t',{}))()
assert(list.slot=='controls:visuals' and #list.templates==4 and table.concat(list.categories,',')==table.concat(categories,','))
assert(list.templates[2].active==true and list.templates[1].active==false and list.templates[3].active==false
    and list.templates[4].module=='' and list.templates[4].name=='Built In "Quoted"')

-- The hooks page has one group per category with templates and in it one subgroup per
-- module supplying them, MCT's own first; each template reads active or blank. Categories
-- without templates are not listed. Ids follow the list.
local hooks=assert(loadfile('Scripts/mct_templates_page.lua'))()
assert(hooks.contract==1 and type(hooks.menu)=='function' and hooks.manifest==nil and hooks.load==nil)
local names={TemplatesPage='ModCore Templates',Fangdango='Quickslot Fangdango',Preymonition='Preymonition'}
local context={page='ModCoreTemplates',directory=root,moduleName=function(folder) return names[folder] end}
local menu=hooks.menu(context)
assert(#menu.fields==4,'the page holds only template rows')
local order={}
for _,group in ipairs(menu.groups) do
    local inner={}
    for _,sub in ipairs(group.groups) do inner[#inner+1]=sub.id..':'..sub.label end
    order[#order+1]=group.id..':'..group.label..'['..table.concat(inner,',')..']'
end
assert(table.concat(order,',')=='Category1:Npc Attacks[Category1_1:Preymonition],'
    ..'Category2:Player Quickslots[Category2_1:ModCore Templates,Category2_2:Quickslot Fangdango]',table.concat(order,','))
local labels={}
for _,item in ipairs(menu.fields) do
    assert(item.readOnly and item.choices[1].note==nil,'rows are read-only, without notes')
    labels[#labels+1]=item.group..':'..item.id..':'..item.label
end
assert(table.concat(labels,',')=='Category1_1:MCT_Listed_3:Preymonition,Category2_1:MCT_Listed_4:Built In "Quoted",'
    ..'Category2_2:MCT_Listed_1:Wheels,Category2_2:MCT_Listed_2:Double Sidebar',table.concat(labels,','))
local function row(label) for _,item in ipairs(menu.fields) do if item.label==label then return item end end end
local blank='\u{A0}'
assert(row('Double Sidebar').choices[1].label=='Active' and row('Wheels').choices[1].label==blank
    and row('Preymonition').choices[1].label==blank,'only the selected template shows as active')
-- Without names the folders are shown as they are.
local unnamed=hooks.menu({page='ModCoreTemplates',directory=root})
assert(unnamed.groups[2].groups[1].label=='TemplatesPage' and unnamed.groups[2].groups[2].label=='Fangdango')

-- Without a list (before MCT has run) the page says so instead of failing.
local empty=hooks.menu({page='ModCoreTemplates',directory=root..'/Missing'})
assert(empty.fields[1].choices[1].label=='Available once the game has loaded them')

-- ModCoreSettings builds it into a page DMM parses.
local choicesPath,presentationPath=os.getenv('MCT_DMM_CHOICES'),os.getenv('MCT_PRESENTATION')
if choicesPath then
    local Choices=dofile(choicesPath)
    local MenuData=dofile((presentationPath:gsub('presentation%.lua$','menu_data.lua')))
    local manifest=MenuData.manifest(menu)
    local items=Choices.parse(manifest)
    assert(#items==4,'four template rows')
    assert(#Choices.parse(MenuData.manifest(empty))==1)
end

-- The controller reports each committed state, and a failing report is not fatal.
local seen,errors={},{}
local menu={rows={},textSettings={},providers={},decodeState=function(values) return {n=values.n} end}
local runtime={commit=function() end}
Controller.new(menu,runtime,{values={},onState=function(committed) seen[#seen+1]=committed end})
assert(#seen==1,'the starting state is reported')
Controller.new(menu,runtime,{onState=function() error('disk full') end,
    onError=function(event) errors[#errors+1]=event end})
assert(#errors==1 and errors[1].stage=='state' and errors[1].message:find('disk full'))
print('PASS: the Templates page lists templates by category and marks the active ones')
