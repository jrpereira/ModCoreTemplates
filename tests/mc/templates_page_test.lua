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
local text=List.encode(templates,state,'controls:visuals')
local file=assert(io.open(paths.templates,'wb'));file:write(text);file:close()
local list=assert(load(text,'list','t',{}))()
assert(list.slot=='controls:visuals' and #list.templates==4)
assert(list.templates[2].active==true and list.templates[1].active==false and list.templates[3].active==false
    and list.templates[4].module=='' and list.templates[4].name=='Built In "Quoted"')

-- The hooks page groups templates by module, MCT's own first, and marks the active ones.
-- ModCoreSettings names each module from its folder.
local hooks=assert(loadfile('Scripts/mct_templates_page.lua'))()
assert(hooks.contract==1 and type(hooks.menu)=='function' and hooks.manifest==nil and hooks.load==nil)
local names={TemplatesPage='ModCore Templates',Fangdango='Quickslot Fangdango',Preymonition='Preymonition'}
local context={page='ModCoreTemplates',directory=root,moduleName=function(folder) return names[folder] end}
local menu=hooks.menu(context)
assert(menu.fields[1].id=='MCT_Choose' and menu.fields[1].link=='controls:visuals' and menu.fields[1].tabs,
    'the first row opens where templates are chosen')
local order={}
for _,group in ipairs(menu.groups) do order[#order+1]=group.label or group.id end
assert(table.concat(order,',')=='Choose,ModCore Templates,Preymonition,Quickslot Fangdango',table.concat(order,','))
local rows={}
for _,item in ipairs(menu.fields) do
    if item.readOnly then rows[#rows+1]=item end
end
local function row(label) for _,item in ipairs(rows) do if item.label==label then return item end end end
assert(#rows==4 and rows[1].label=='Built In "Quoted"' and rows[2].label=='Preymonition'
    and rows[3].label=='Wheels' and rows[4].label=='Double Sidebar',
    'templates are grouped by module, MCT\'s own first, then by the module\'s name')
assert(row('Double Sidebar').choices[1].label=='✔  Active' and row('Wheels').choices[1].label=='—'
    and row('Preymonition').choices[1].label=='—','only the selected template shows as active')
assert(row('Wheels').choices[1].note=='Player Quickslots' and row('Preymonition').choices[1].note=='Npc Attacks',
    'each template shows its category, faint, under its value')
-- Without names the folders are shown as they are.
local unnamed=hooks.menu({page='ModCoreTemplates',directory=root})
assert(unnamed.groups[3].label=='Fangdango' and unnamed.groups[2].label=='TemplatesPage')

-- Without a list (before MCT has run) the page says so instead of failing.
local empty=hooks.menu({page='ModCoreTemplates',directory=root..'/Missing'})
assert(empty.fields[1].choices[1].label=='Available once the game has loaded them')

-- ModCoreSettings builds it into a page DMM parses.
local choicesPath,presentationPath=os.getenv('MCT_DMM_CHOICES'),os.getenv('MCT_PRESENTATION')
if choicesPath then
    local Choices=dofile(choicesPath)
    local MenuData=dofile((presentationPath:gsub('presentation%.lua$','menu_data.lua')))
    local items=Choices.parse(MenuData.manifest(menu))
    assert(#items==5,'a link row and four template rows')
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
print('PASS: the Templates page lists loaded templates by module and marks the active ones')
