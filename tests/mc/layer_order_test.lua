-- Created layers that share a parent stack in template order, (priority, id), as a
-- full attach leaves them, even when a template attaches after the others.
package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local Selectors=require('mc.selectors')
local Targets=require('mc.template_targets')
local Manager=require('mc.managed_template')

local nextAddress=0
local function object(name)
    nextAddress=nextAddress+1
    local value={name=name,address=nextAddress,children={},opacity=1,
        RenderTransform={Translation={X=0,Y=0},Scale={X=1,Y=1}}}
    function value:IsValid() return true end
    function value:GetFullName() return self.name end
    function value:GetAddress() return self.address end
    function value:GetParent() return self.parent end
    function value:GetChildrenCount() return #self.children end
    function value:GetChildAt(index) return self.children[index+1] end
    function value:GetRenderOpacity() return self.opacity end
    function value:SetRenderOpacity(opacity) self.opacity=opacity end
    function value:SetRenderTranslation(position) self.RenderTransform.Translation=position end
    function value:AddChild(child)
        assert(child.parent==nil)
        self.children[#self.children+1]=child
        child.parent=self
        local slot={Padding={Left=0,Top=0,Right=0,Bottom=0},
            HorizontalAlignment=0,VerticalAlignment=0}
        function slot:IsValid() return true end
        function slot:GetClass() return {GetName=function() return 'OverlaySlot' end} end
        function slot:SetPadding(padding) self.Padding=padding end
        function slot:SetHorizontalAlignment(alignment) self.HorizontalAlignment=alignment end
        function slot:SetVerticalAlignment(alignment) self.VerticalAlignment=alignment end
        child.Slot=slot
        return slot
    end
    function value:RemoveChild(child)
        for index,item in ipairs(self.children) do
            if item==child then
                table.remove(self.children,index)
                child.parent=nil
                return true
            end
        end
        return false
    end
    return value
end

local root,outer=object('root'),object('WidgetTree')
function root:GetOuter() return outer end
local native=object('native HUD content')
root:AddChild(native)
local classLookups=0
local overlayClass=object('Class /Script/UMG.Overlay')
StaticFindObject=function(path) classLookups=classLookups+1; assert(path=='/Script/UMG.Overlay'); return overlayClass end
StaticConstructObject=function(_,owner)
    assert(owner==outer)
    return object('cue')
end

local declarations={
    root={source='lookup',object='root',required=true},
    cue={source='create',class='/Script/UMG.Overlay',outer='root',parent='root',layout='fill'},
}
local graph=Selectors.compile(declarations)
local cues={}
local function manager(id,priority)
    local template={id=id,objects={'cue'},attach=function(values,_,original)
        cues[id]=values.cue
        return original
    end}
    return Manager.new(template,(Targets.compile(graph,template.objects)),graph.order,
        {{name='cue',class='/Script/UMG.Overlay',from='root',parent='root',layout='fill'}},
        {priority=priority,id=id})
end
local omens,edges,background,alpha=manager('Omens',10),manager('Edges',11),
    manager('Background',9),manager('Alpha',10)
local function attach(m) assert(m:attach(root,{},{settings={}},{root=root})) end
local function order()
    local names={}
    for index=0,root:GetChildrenCount()-1 do
        local child=root:GetChildAt(index)
        if child==native then names[#names+1]='native' end
        for id,cue in pairs(cues) do if cue==child then names[#names+1]=id end end
    end
    return table.concat(names,',')
end

attach(omens)
attach(edges)
assert(order()=='native,Omens,Edges',order())
assert(classLookups==1,'a created class is looked up once while it lives')
-- Enabled mid-session: the backdrop goes under the layers already shown.
cues.Edges.Slot:SetPadding({Left=3,Top=0,Right=0,Bottom=0})
attach(background)
assert(order()=='native,Background,Omens,Edges',order())
assert(cues.Edges.Slot.Padding.Left==3,'a moved layer keeps its slot settings')
-- Equal priority: by id.
attach(alpha)
assert(order()=='native,Background,Alpha,Omens,Edges',order())
-- Reattaching one template puts its new layer back in its place.
assert(omens:detach(root))
cues.Omens=nil
attach(omens)
assert(order()=='native,Background,Alpha,Omens,Edges',order())
-- Another manager's layer above them all, as the quickslot canvas sits above the cues.
local canvas=manager('Canvas',100)
attach(canvas)
assert(order()=='native,Background,Alpha,Omens,Edges,Canvas',order())
-- An update (an Apply) re-adds each reused layer; it keeps its place and stays registered.
for _,m in ipairs({background,alpha,omens,edges}) do
    assert(m:update(root,{},{settings={}},{root=root}))
end
assert(order()=='native,Background,Alpha,Omens,Edges,Canvas',order())
-- A layer attached after the updates still lands under the higher ones.
local low=manager('Low',5)
attach(low)
assert(order()=='native,Low,Background,Alpha,Omens,Edges,Canvas',order())
assert(edges:update(root,{},{settings={}},{root=root}))
assert(order()=='native,Low,Background,Alpha,Omens,Edges,Canvas',order())
print('PASS: created layers stack by template priority, then id, whatever the attach order')
