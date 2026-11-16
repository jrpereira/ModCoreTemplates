package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
-- A module page's live preview: the page's selected templates attach to ModCoreSettings'
-- preview host with the page's values, and the category's scripted events loop.
-- The preview keeps its host and layers as UE4SSLuaEventBridge weak handles.
dofile('tests/support/lifetimes.lua').install()
local Preview=require('mc.preview')

local function widget(name)
    local w={name=name,children={},valid=true}
    function w:IsValid() return self.valid end
    function w:GetOuter() return self.outer end
    function w:AddChildToOverlay(child)
        self.children[#self.children+1]=child;child.parent=self
        return {SetHorizontalAlignment=function() end,SetVerticalAlignment=function() end}
    end
    function w:RemoveFromParent()
        local parent=self.parent
        for i,c in ipairs(parent and parent.children or {}) do if c==self then table.remove(parent.children,i) end end
        self.parent=nil
    end
    return w
end
local owner=widget('Menu')
local tree=widget('WidgetTree');tree.outer=owner
local host=widget('Host');host.outer=tree

local vars,handlers,queue={},{},{}
local shared={GetSharedVariable=function(_,k) return vars[k] end,SetSharedVariable=function(_,k,v) vars[k]=v end}
local function register(command,fn) handlers[command]=fn;return true end
local function delay(ms,fn) queue[#queue+1]={ms=ms,fn=fn} end
local function run(limit)
    local ran=0
    while #queue>0 and ran<(limit or 1000) do
        table.sort(queue,function(a,b) return a.ms<b.ms end)
        local item=table.remove(queue,1)
        for _,other in ipairs(queue) do other.ms=other.ms-item.ms end
        item.fn();ran=ran+1
    end
end

local attaches,cleanups,events={},0,{}
local template={id='P_Omens',preview={sound={'Sound','Options'}},
    attach=function(objects,params)
        attaches[#attaches+1]={objects=objects,params=params}
        params.onCleanup(function() cleanups=cleanups+1 end)
    end,
    events={update=function(params,event) events[#events+1]=event end}}
local other={id='Other_X',preview={},attach=function() error('another module\'s template must not attach') end}
local quiet={id='P_Quiet',attach=function() error('a template without preview must not attach') end}
local decoded
local session={
    menu={definitions={['npc.attacks']={['P_Omens:1']={id='P_Omens',enabledId='MCT_P_Omens_Enabled',settings={SoundIncoming='MCT_SoundIncoming',OptionsVolume='MCT_OptionsVolume',Style='MCT_Style'}}}},
        providers={['Page.P']={id='Page.P',preview=true,categories={['npc.attacks']=true},owned={['P_Omens']=true,['P_Quiet']=true}},
        ['Page.Plain']={id='Page.Plain'}},
        decodeState=function(values) decoded=values;return {['npc.attacks']={settings={Shared=1},
            selections={P_Omens={Style=values.MCT_Style},Other_X={},P_Quiet={}}}} end},
    menuController={values=function() return {MCT_Style=2,MCT_Size='30|80'} end},
    model={templates={template,other,quiet}},
}
local script={length=3000,events={{at=0,attack=1,event={kind='arrow',direction=3}},
    {at=500,attack=1,event={kind='critical',direction=3}},{at=900,attack=1,event={kind='resolve',reason='sword'}}}}
local constructed={}
-- The command only queues its work; run here as soon as it is queued, unless held.
local held
local function later(fn) if held then held[#held+1]=fn else fn() end end
local preview=Preview.new({shared=shared,register=register,session=function() return session end,
    categories={['npc.attacks']={preview=script}},delay=delay,queue=later,
    construct=function(class,outer) local w=widget(class);w.outer=outer;constructed[#constructed+1]=w;return w end})
assert(handlers[Preview.COMMAND],'the console command is registered')
-- The command runs nothing inline, and commands before the queued run share it.
held={}
assert(handlers[Preview.COMMAND]()==true and handlers[Preview.COMMAND]()==true and #held==1,
    'one queued run for any number of commands')
local queued=table.remove(held);held=nil;queued()

-- Values arrive with the open: unapplied values override committed ones.
vars[Preview.HOST]=host
vars[Preview.VALUES]='1\nMCT_Style=4'
vars[Preview.STATE]='2 open Page.P'
handlers[Preview.COMMAND]()
assert(decoded.MCT_Style==4 and decoded.MCT_Size=='30|80','page values over committed ones, numbers kept numbers')
assert(#attaches==1,'only the page module\'s selected template attaches')
local a=attaches[1]
assert(a.objects.hud==owner and a.objects.cue==host.children[1] and #host.children==1,
    'the host\'s owning widget is the HUD; each template gets its own layer in the host')
assert(a.params.preview and a.params.settings.Style==4 and a.params.settings.Shared==1
    and a.params.screen.width==1920 and a.params.screen.height==1080,'preview params: settings and a 16:9 screen')

-- One timer is pending at a time: each event schedules the next.
assert(#queue==1,'one pending timer, not one per event')
-- The script plays: each event marked preview, with the HUD as indicator and one path per attack.
run(4)
assert(#queue==1,'still one pending timer')
assert(#events==3 and events[1].kind=='arrow' and events[1].preview and events[1].indicator==owner
    and events[1].path==events[3].path and events[2].kind=='critical','the scripted events play, one path per attack')

-- Sound: on auto (the default), events are silent unless a sound setting is selected;
-- on always sounds; off never.
assert(events[1].silent==true,'auto with nothing selected is silent')
local function next(mode,focus)
    vars[Preview.SOUND],vars[Preview.FOCUS]=mode,focus
    local before=#events
    run(4)
    return events[before+1]
end
assert(next('auto','MCT_SoundIncoming').silent==false,'auto sounds while a sound setting is selected')
assert(next('auto','MCT_Style').silent==true,'and not on another one')
assert(next('auto','MCT_OptionsVolume').silent==false,'preview.sound may list several groups')
assert(next('on','MCT_Style').silent==false,'on always sounds')
assert(next('off','MCT_SoundIncoming').silent==true,'off never does')
vars[Preview.SOUND],vars[Preview.FOCUS]=nil,nil
-- preview.sound=true: every setting of the template sounds on auto, its Enabled included.
template.preview.sound=true
-- A value change reattaches with the new values.
vars[Preview.VALUES]='3\nMCT_Style=1'
handlers[Preview.COMMAND]()
assert(#attaches==2 and cleanups==1 and attaches[2].params.settings.Style==1 and #host.children==1,
    'a change cleans up and reattaches; the old layer goes')
assert(next('auto','MCT_Style').silent==false and next('auto','MCT_P_Omens_Enabled').silent==false
    and next('auto','MCT_Other').silent==true,'sound=true: any of its settings, Enabled included')
vars[Preview.SOUND],vars[Preview.FOCUS]=nil,nil

-- The loop repeats with fresh paths.
local before=#events
run(4)
assert(#events>before and events[#events].path~=events[1].path,'the next loop uses new paths')

-- Closing stops the loop and cleans up.
vars[Preview.STATE]='4 closed Page.P'
handlers[Preview.COMMAND]()
assert(cleanups==2 and #host.children==0,'closing cleans up')
local after=#events
run(20)
assert(#events==after,'no events after closing')

-- A page without a preview opens nothing; a gone host stops the preview.
vars[Preview.STATE]='5 open Page.Plain'
handlers[Preview.COMMAND]()
assert(#attaches==2,'no preview for a page without one')
vars[Preview.STATE]='6 open Page.P'
handlers[Preview.COMMAND]()
assert(#attaches==3)
host.valid=false
run(20)
assert(cleanups==3,'a host that is gone stops the preview')
-- Templates attach by priority, lowest first, then by id, as the runtime attaches
-- them: each one's layer stacks over those before it, whatever order the selections
-- come in.
local order={}
local function ranked(id,priority)
    return {id=id,priority=priority,preview={},attach=function(objects) order[#order+1]={id=id,layer=objects.cue} end}
end
session.model={templates={ranked('P_Omens',10),ranked('P_Back',9),ranked('P_Late',nil),ranked('P_Edges',10)}}
session.menu.providers['Page.P'].owned=nil
session.menu.decodeState=function() return {['npc.attacks']={selections={P_Late={},P_Edges={},P_Omens={},P_Back={}}}} end
host.valid=true
vars[Preview.STATE]='7 open Page.P'
handlers[Preview.COMMAND]()
local ids={}
for index,entry in ipairs(order) do
    ids[index]=entry.id
    assert(host.children[index]==entry.layer,'layers stack in attach order')
end
assert(table.concat(ids,' ')=='P_Back P_Edges P_Omens P_Late','by priority, then id; no priority goes last')
vars[Preview.STATE]='8 closed Page.P'
handlers[Preview.COMMAND]()
-- The menu model keeps a template's preview in the registry's metadata, where the menu
-- looks for it to give the module page its preview (it was dropped once, so no page had one).
local Model=require('mc.menu_model')
local built=Model.build({{id='cat.x'}},
    {{id='M_T',category='cat.x',preview={background='images/x.jpg'},attach=function() end}},{'/Mods/M/Scripts/t.lua'})
assert(built.registry.templates[1].template.preview.background=='images/x.jpg','registry metadata keeps preview')
print('PASS: preview attaches the page\'s templates to the host with its values and loops the category script')
