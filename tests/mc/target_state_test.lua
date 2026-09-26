package.path='./Scripts/?.lua;'..package.path
local State=require('mc.target_state')
local Widget=require('mc.widget')
assert(Widget.property({bAutoSize=false},'bAutoSize')==false)
assert(Widget.property({bAutoSize={get=function() return false end}},'bAutoSize')==false)

local function widget(name)
    local object={name=name,children={},active=0,
        RenderTransform={Translation={X=0,Y=0},Scale={X=1,Y=1}},opacity=1}
    function object:IsValid() return true end
    function object:GetFullName() return self.name end
    function object:GetParent() return self.parent end
    function object:GetChildrenCount() return #self.children end
    function object:GetChildAt(index) return self.children[index+1] end
    function object:RemoveChild(child)
        for index,value in ipairs(self.children) do
            if value==child then table.remove(self.children,index);child.parent=nil;return true end
        end
        return false
    end
    function object:AddChild(child)
        assert(not child.parent)
        self.children[#self.children+1]=child
        child.parent=self
        child.Slot={LayoutData={},Padding={Left=0,Top=0,Right=0,Bottom=0},
            HorizontalAlignment=0,VerticalAlignment=0}
        function child.Slot:IsValid() return true end
        function child.Slot:GetClass() return {GetName=function() return 'WidgetSwitcherSlot' end} end
        function child.Slot:SetPadding(value) self.Padding=value end
        function child.Slot:SetHorizontalAlignment(value) self.HorizontalAlignment=value end
        function child.Slot:SetVerticalAlignment(value) self.VerticalAlignment=value end
        return child.Slot
    end
    function object:GetActiveWidgetIndex() return self.active end
    function object:SetActiveWidgetIndex(value) self.active=value end
    function object:SetRenderTranslation(value) self.RenderTransform.Translation=value end
    function object:SetRenderScale(value) self.RenderTransform.Scale=value end
    function object:GetRenderOpacity() return self.opacity end
    function object:SetRenderOpacity(value) self.opacity=value end
    return object
end

local switcher,elsewhere=widget('switcher'),widget('elsewhere')
local first,second=widget('first'),widget('second')
switcher:AddChild(first);switcher:AddChild(second)
switcher.active=1
local targets={switcher=switcher,buttons={first,second}}
local specs={switcher={'activeIndex'},buttons={'parent','order','slot','position'}}
local order={'switcher','buttons'}
local saved=State.capture(targets,specs,order)
assert(saved.switcher.activeIndex==1 and saved.buttons[1].order==0
    and saved.buttons[2].order==1 and saved.buttons[1].position.X==0)
switcher:RemoveChild(first)
elsewhere:AddChild(first)
first:SetRenderTranslation({X=50,Y=60})
switcher:SetActiveWidgetIndex(0)
assert(State.restore(targets,specs,order,saved))
assert(switcher:GetChildAt(0)==first and switcher:GetChildAt(1)==second)
assert(switcher:GetActiveWidgetIndex()==1)
assert(first.RenderTransform.Translation.X==0 and first.RenderTransform.Translation.Y==0)
local graph=require('mc.selectors').compile({
    first={object='first'},second={object='second'},
})
local declaration={buttons={row={'first','second'},properties={'parent','order','position'}}}
local tree=require('mc.template_targets').compile(graph,declaration)
local nested=require('mc.template_targets').arrange(tree,{first=first,second=second})
assert(nested.buttons.row[1]==first and nested.buttons.row[2]==second)
local nestedSaved=State.capture(nested,State.specs(graph,declaration))
assert(nestedSaved.buttons.row[1].parent==switcher
    and nestedSaved.buttons.row[2].order==1)
switcher:RemoveChild(second);elsewhere:AddChild(second)
second:SetRenderTranslation({X=30,Y=40})
assert(State.restore(nested,tree,nil,nestedSaved))
assert(second:GetParent()==switcher and second.RenderTransform.Translation.X==0)
print('PASS: declared target properties and nested lists restore in original order')

-- Managed event subscriptions have the same lifetime as their attachment.
local Manager=require('mc.managed_template')
local active,cleaned,fail=0,0,false
local definition={attach=function(objects,params,original)
    active=active+1
    params.onCleanup(function() active=active-1;cleaned=cleaned+1 end)
    objects.switcher:SetActiveWidgetIndex(0)
    if fail then error('injected attach failure') end
    return original
end}
local managed=Manager.new(definition,{switcher={'activeIndex'}},{'switcher'})
local named={switcher=switcher}
assert(managed:attach(switcher,named,{settings={}}) and active==1)
assert(managed:update(switcher,named,{settings={}}) and active==1 and cleaned==1)
assert(managed:detach(switcher) and active==0 and switcher.active==1)
fail=true
assert(not managed:attach(switcher,named,{settings={}}) and active==0)
assert(switcher.active==1,'failed attach restores native state after cleanup')
fail=false
assert(managed:attach(switcher,named,{settings={}}))
managed:forget(switcher)
assert(active==0,'forget must unsubscribe even when world objects cannot be restored')
assert(managed:attach(switcher,named,{settings={}}))
managed:reset()
assert(active==0,'reset must remove all subscriptions')
print('PASS: managed cleanup on update, detach, failure, forget and reset')

do
    local canvas,other=widget('canvas'),widget('other-canvas')
    canvas.AddChild=function(self,child)
        self.children[#self.children+1]=child; child.parent=self
        local slot={LayoutData={Offsets={Left=0,Top=0,Right=0,Bottom=0},
            Anchors={Minimum={X=0,Y=0},Maximum={X=0,Y=0}},
            Alignment={X=0,Y=0}},ZOrder=0,bAutoSize=false}
        function slot:IsValid() return true end
        function slot:GetClass() return {GetName=function() return 'CanvasPanelSlot' end} end
        function slot:SetLayout(value) self.LayoutData=value end
        function slot:SetZOrder(value) self.ZOrder=value end
        function slot:SetAutoSize(value) self.bAutoSize=value end
        child.Slot=slot
        return slot
    end
    local a,b,c=widget('canvas-a'),widget('canvas-b'),widget('canvas-c')
    canvas:AddChild(a);canvas:AddChild(b);canvas:AddChild(c)
    a.Slot.LayoutData.Offsets.Left=123;a.Slot.ZOrder=7;a.Slot.bAutoSize=true
    local targets,specs,order={b=b},{b={'parent','order'}},{'b'}
    local saved=State.capture(targets,specs,order)
    canvas:RemoveChild(b);other:AddChild(b)
    assert(State.restore(targets,specs,order,saved))
    assert(canvas:GetChildAt(0)==a and canvas:GetChildAt(1)==b and canvas:GetChildAt(2)==c)
    assert(a.Slot.LayoutData.Offsets.Left==123 and a.Slot.ZOrder==7 and a.Slot.bAutoSize)
end

do
    local unknown,other=widget('unknown-panel'),widget('other-unknown')
    unknown.AddChild=function(self,child)
        self.children[#self.children+1]=child;child.parent=self
        child.Slot={IsValid=function()return true end,UncapturedState=42,
            Padding={Left=0,Top=0,Right=0,Bottom=0},
            HorizontalAlignment=0,VerticalAlignment=0,
            GetClass=function() return {GetName=function() return 'HorizontalBoxSlot' end} end}
        return child.Slot
    end
    local a,b,c=widget('unknown-a'),widget('unknown-b'),widget('unknown-c')
    unknown:AddChild(a);unknown:AddChild(b);unknown:AddChild(c)
    local targets,specs,order={b=b},{b={'parent','order'}},{'b'}
    local saved=State.capture(targets,specs,order)
    unknown:RemoveChild(b);other:AddChild(b)
    local ok=pcall(State.restore,targets,specs,order,saved)
    assert(not ok,'unknown slot must not be silently rebuilt')
    assert(unknown:GetChildAt(0)==a and unknown:GetChildAt(1)==c
        and a.Slot.UncapturedState==42)
end
