-- Loading a save from a running game collects the old world while MCT still
-- knows its objects. UE4SS IsValid reads the object, so any call on a kept
-- wrapper reads freed memory. Here a freed object raises on every access and
-- counts it; the native lifetime is read without touching the object.
package.path='./Scripts/?.lua;'..package.path
local Lifetimes=dofile('tests/support/lifetimes.lua')
local Source=require('mc.widget_source')
local References=require('mc.lua_references')
local Runtime=require('mc.runtime')
local Objects=require('mc.objects')

local HUD='/Game/HUD/WBP_Hud.WBP_Hud_C'
local reads,states,everything={}, setmetatable({}, {__mode='k'}), {}
local nextAddress=100
local object
local function slot()
    local value=object('Slot')
    local data=states[value]
    data.Padding={Left=0,Top=0,Right=0,Bottom=0}
    data.HorizontalAlignment,data.VerticalAlignment=0,0
    return value
end
local methods={
    IsValid=function(self) return states[self].alive end,
    GetAddress=function(self) return states[self].address end,
    GetFullName=function(self) return states[self].full end,
    GetOuter=function(self) return states[self].outer end,
    GetParent=function(self) return states[self].parent end,
    GetWorld=function() return nil end,
    IsInViewport=function() return true end,
    IsA=function(self,class) return states[self].classes[(class:gsub('^Class ',''))]==true end,
    GetChildrenCount=function(self) return #states[self].children end,
    GetChildAt=function(self,index) return states[self].children[index+1] end,
    GetRenderOpacity=function(self) return states[self].opacity end,
    SetRenderOpacity=function(self,value) states[self].opacity=value end,
    SetRenderTranslation=function(self,value) states[self].RenderTransform.Translation=value end,
    ForceLayoutPrepass=function() end,
    SetLayout=function(self,value) states[self].layout=value end,
    SetAutoSize=function(self,value) states[self].autoSize=value end,
    SetPadding=function(self,value) states[self].Padding=value end,
    SetHorizontalAlignment=function(self,value) states[self].HorizontalAlignment=value end,
    SetVerticalAlignment=function(self,value) states[self].VerticalAlignment=value end,
    AddChild=function(self,child)
        local children=states[self].children
        children[#children+1]=child
        states[child].parent=self
        local value=slot()
        states[child].Slot=value
        return value
    end,
    RemoveChild=function(self,child)
        for index,item in ipairs(states[self].children) do
            if item==child then
                table.remove(states[self].children,index)
                states[child].parent=nil
                return true
            end
        end
        return false
    end,
}
function object(name,classes,outer)
    nextAddress=nextAddress+1
    local data={full=name,address=nextAddress,classes=classes or {},outer=outer,alive=true,
        children={},opacity=1,RenderTransform={Translation={X=0,Y=0},Scale={X=1,Y=1}}}
    local value=setmetatable({},{
        __index=function(_,key)
            if not data.alive then
                reads[#reads+1]=name..'.'..tostring(key)
                error('freed object read: '..name..'.'..tostring(key))
            end
            if methods[key]~=nil then return methods[key] end
            return data[key]
        end,
        __newindex=function(_,key,value)
            if not data.alive then
                reads[#reads+1]=name..'.'..tostring(key)..'='
                error('freed object written: '..name..'.'..tostring(key))
            end
            data[key]=value
        end,
    })
    states[value]=data
    everything[#everything+1]=value
    return value
end
local widget={['/Script/UMG.Widget']=true}
local userWidget={['/Script/UMG.Widget']=true,['/Script/UMG.UserWidget']=true,[HUD]=true}
local function hud(label)
    local tree=object('WidgetTree '..label)
    local value=object('WBP_Hud_C /Engine/Transient.'..label,userWidget,tree)
    local canvas=object('CanvasPanel /Engine/Transient.'..label..'.Canvas',widget,tree)
    local wheel=object('Overlay /Engine/Transient.'..label..'.Wheel',widget,tree)
    methods.AddChild(canvas,wheel)
    states[value].Wheel=wheel
    return value,wheel
end
local permanent={}
local function free()
    for _,value in ipairs(everything) do
        if not permanent[value] then states[value].alive=false end
    end
end

local service=Lifetimes.service(function(value)
    return states[value]~=nil and states[value].alive==true
end)
local jobs,hooks,notify={}, {}, {}
-- A class default object survives the load.
local layout=object('WidgetLayoutLibrary /Script/UMG.Default__WidgetLayoutLibrary')
permanent[layout]=true
local made=0
function StaticFindObject(path)
    if path=='/Script/UMG.Default__WidgetLayoutLibrary' then return layout end
    return {path=path}
end
function StaticConstructObject(_,outer)
    made=made+1
    return object('CanvasPanel /Engine/Transient.Created_'..made,widget,outer)
end
methods.GetViewportSize=function() return {X=1920,Y=1080} end
methods.GetViewportScale=function() return 1 end
local api={
    UE4SSLuaEventBridge=Lifetimes.bridge(service),
    StaticFindObject=StaticFindObject,
    IsInGameThread=function() return true end,
    ExecuteInGameThread=function(callback) jobs[#jobs+1]=callback end,
    NotifyOnNewObject=function(class,callback) notify[class]=callback end,
    RegisterHook=function(path,pre,post) hooks[path]={pre=pre,post=post}; return 1,2 end,
    UnregisterHook=function(path) hooks[path]=nil end,
    MCTOnError=function(error) error.message=nil end,
}
local live={}
function api.FindAllOf(class)
    assert(class=='WBP_Hud_C')
    local result={}
    for _,value in ipairs(live) do
        if states[value].alive then result[#result+1]=value end
    end
    return result
end
local function drain()
    while #jobs>0 do table.remove(jobs,1)() end
end
local function wrap(value) return {get=function() return value end} end

local category={name='hud',objects={
    hud={source='lookup',class=HUD},
    wheel={source='reference',from='hud',member='Wheel'},
    out={source='create',class='/Script/UMG.CanvasPanel',outer='hud',parent='hud',layout='fill'},
    bait={source='create',class='/Script/UMG.Overlay',outer='hud',parent='hud',
        reparent='wheel',destination='out',reparentLayout='canvas'},
}}
local cleanups,touched=0,0
local template={id='t',category='hud',objects={'out','bait'},
    attach=function(objects,params,original)
        -- A template keeps what its cleanup touches as a weak handle.
        local kept=assert(Objects.hold(objects.out))
        params.onCleanup(function()
            cleanups=cleanups+1
            local out=Objects.get(kept)
            if out then touched=touched+1; out:SetRenderOpacity(1) end
        end)
        return original
    end}

local first,firstWheel=hud('Hud_1')
live[1]=first
local source=Source.new({category},api)
local host=References.new(source)
local runtime=Runtime.new(host,{category},{template})
runtime:select('hud',{t={}})
runtime:start()
drain()
local attachments=runtime:attachments('t')
assert(next(attachments) and made==2, 'the template attaches to the first HUD')
assert(states[firstWheel].parent and states[states[firstWheel].parent].full:find('Created_1',1,true),
    'the wheel is moved into the created panel')
assert(hooks['/Script/UMG.UserWidget:AddToViewport'], 'a live HUD arms the widget hooks')

-- The save loads: every object of the old world is collected.
free()
local menu=object('WBP_Loading_C /Engine/Transient.Loading',userWidget)
hooks['/Script/UMG.UserWidget:AddToViewport'].post(wrap(menu))
assert(#jobs>0, 'an unrelated hook with no live root queues the hook refresh')
drain()
assert(#reads==0, 'freed objects read: '..table.concat(reads,', '))
assert(next(hooks)==nil, 'leaving the world removes every widget hook')

-- The new world's HUD is announced; the old attachment is forgotten.
local second=hud('Hud_2')
live[1]=second
notify[HUD](second)
drain()
assert(#reads==0, 'freed objects read: '..table.concat(reads,', '))
assert(cleanups==1 and touched==0, 'the cleanup runs and skips its collected widget')
local current=runtime:attachments('t')
local count=0
for _,reference in pairs(current) do
    count=count+1
    assert(host.unwrap(reference)==second, 'only the new HUD is attached')
end
assert(count==1 and made==4, 'the template attaches to the new HUD with new created objects')
assert(service.held>0)
runtime:stop()
source.stop()
drain()
assert(#reads==0, 'freed objects read: '..table.concat(reads,', '))
print('PASS: a save load reads no collected object')
