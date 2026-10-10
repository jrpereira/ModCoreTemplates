package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local Runtime=require('mc.runtime')
local category=dofile('Scripts/categories/npc_attacks.lua')
assert(category.name=='npc.attacks' and category.single==nil,
    'notification templates chain instead of replacing each other')
local objects={}
local function object(id,class)
    local value={id=id,class=class,children={},members={},opacity=1,
        RenderTransform={Translation={X=0,Y=0},Scale={X=1,Y=1}}}
    function value:IsValid() return true end
    function value:GetFullName() return self.id end
    function value:GetOuter() return self.outer or self end
    function value:GetParent() return self.parent end
    function value:GetChildrenCount() return #self.children end
    function value:GetChildAt(index) return self.children[index+1] end
    function value:SetRenderTranslation(position) self.RenderTransform.Translation=position end
    function value:AddChild(child)
        assert(child.parent==nil)
        self.children[#self.children+1]=child; child.parent=self
        local slot={}
        function slot:IsValid() return true end
        if self.class=='Overlay' then
            -- Overlay slots have no canvas layout; fill uses alignment 0 (Fill).
            function slot:SetPadding(padding) self.padding=padding end
            function slot:SetHorizontalAlignment(alignment) self.horizontal=alignment end
            function slot:SetVerticalAlignment(alignment) self.vertical=alignment end
        else
            function slot:SetLayout(layout) self.layout=layout end
            function slot:SetAutoSize(autoSize) self.autoSize=autoSize end
        end
        child.Slot=slot
        return slot
    end
    function value:RemoveChild(child)
        for index,item in ipairs(self.children) do
            if item==child then table.remove(self.children,index); child.parent=nil; return true end
        end
        return false
    end
    objects[#objects+1]=value
    return value
end
-- The live root type is unconfirmed: P's earlier adapter used Overlay.
local function gameHud(id,rootClass)
    local hud=object(id,'WBP_GameHUD_C')
    local tree=object(id..'Tree','WidgetTree')
    local root=object(id..'Root',rootClass)
    hud.members.WidgetTree,tree.members.RootWidget,root.outer=tree,root,tree
    root:AddChild(object(id..'Native','Overlay'))
    return hud,root,tree
end
local hud,hudRoot,hudTree=gameHud('hud','CanvasPanel')
StaticFindObject=function(path) return {path=path} end
StaticConstructObject=function(class,outer)
    assert(class.path=='/Script/UMG.Overlay')
    local cue=object('cue'..#objects,'Overlay')
    cue.outer=outer
    return cue
end
local host={}
host.valid=function(value) return value~=nil end
host.identity=function(value) return value.id end
host.ready=function() return true end
host.matches=function(value,selector)
    return selector.class~=nil and value.class==selector.class:match('([^%.]+)$')
end
host.parent=function() return nil end
host.watch=function() end
host.screen=function() return {width=1920,height=1080,scale=1} end
host.member=function(parent,path)
    local value=parent
    for key in path:gmatch('[^.]+') do value=value and value.members[key] end
    return value
end
host.find=function(selector)
    local result={}
    for _,value in ipairs(objects) do
        if host.matches(value,selector) then result[#result+1]=value end
    end
    return result
end
host.subscribe=function() return function() end end
host.onError=function(error) error(error.message) end

local cues={}
local function template(id)
    cues[id]={}
    return {id=id,category=category.name,objects={hud={},cue={}},
        attach=function(values,_,original)
            assert(values.hud and values.hud.class=='WBP_GameHUD_C','hud is the live game HUD')
            assert(values.hud_root==nil,'hud_root stays a category dependency')
            local cue=values.cue
            assert(cue and cue.class=='Overlay' and cue.parent==values.hud.members.WidgetTree.members.RootWidget,
                'cue is attached to the HUD root before template attach')
            assert(cue.outer==values.hud.members.WidgetTree,'cue is owned by the HUD widget tree')
            local slot=cue.Slot
            assert(slot.layout and slot.layout.Anchors.Maximum.X==1 and slot.layout.Anchors.Maximum.Y==1
                and slot.autoSize==false
                or slot.horizontal==0 and slot.vertical==0 and slot.padding.Left==0,
                'cue fills the HUD root')
            cues[id][values.hud.id]=cue
            return original
        end}
end
local runtime=Runtime.new(host,{category},{template('a'),template('b')})
runtime:select(category.name,{a={},b={}})
runtime:start()
assert(#runtime.errors==0,runtime.errors[1] and runtime.errors[1].message)
assert(next(cues.a)==nil and next(cues.b)==nil,'cues wait until the player is ready')
runtime:signal('MCTPlayerReady')
local a,b=cues.a.hud,cues.b.hud
assert(a and b and a~=b,'each notification template receives its own cue')
assert(hudRoot:GetChildrenCount()==3 and hudRoot:GetChildAt(0).id=='hudNative',
    'cues are added after native HUD content')

runtime:select(category.name,{a={Size=2},b={}})
assert(cues.a.hud==a and a.parent==hudRoot and b.parent==hudRoot,
    'settings commits re-attach the same cue')
assert(hudRoot:GetChildrenCount()==3 and hudRoot:GetChildAt(0).id=='hudNative',
    're-attached cues stay above native content')

local second,secondRoot=gameHud('second','Overlay')
runtime:event({kind='changed',object=second,epoch=runtime.epoch})
assert(#runtime.errors==0,runtime.errors[1] and runtime.errors[1].message)
assert(cues.a.second and cues.b.second and cues.a.second~=a
    and cues.a.second.parent==secondRoot,'templates attach once per live game HUD')

runtime:select(category.name,{b={}})
assert(a.parent==nil and b.parent==hudRoot and hudRoot:GetChildrenCount()==2,
    'detach removes only that template cue')
runtime:stop()
assert(hudRoot:GetChildrenCount()==1 and secondRoot:GetChildrenCount()==1,
    'stopping restores native HUD roots')
print('PASS: notification templates chain with per-template HUD cue layers')
