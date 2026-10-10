package.path='./Scripts/?.lua;./Scripts/vendor/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local Selectors=require('mc.selectors')
local Targets=require('mc.template_targets')
local Manager=require('mc.managed_template')

local declarations={
    root={source='lookup',object='root',required=true},
    actions={source='create',class='/Script/UMG.CanvasPanel',outer='root',parent='root'},
}
local graph=Selectors.compile(declarations)
assert(graph.byName.actions.from=='root' and graph.byName.actions.create)
assert(not pcall(Selectors.compile,{actions={source='create',outer='root'}}))
assert(not pcall(Selectors.compile,{actions={source='event',object='root'}}))

local function object(name)
    local value={name=name,children={},opacity=1,
        RenderTransform={Translation={X=0,Y=0},Scale={X=1,Y=1}}}
    function value:IsValid() return true end
    function value:GetFullName() return self.name end
    function value:GetParent() return self.parent end
    function value:GetChildrenCount() return #self.children end
    function value:GetChildAt(index) return self.children[index+1] end
    function value:GetRenderOpacity() return self.opacity end
    function value:SetRenderOpacity(opacity) self.opacity=opacity end
    function value:SetRenderTranslation(position) self.RenderTransform.Translation=position end
    function value:ForceLayoutPrepass() self.prepassed=true end
    function value:AddChild(child)
        assert(child.parent==nil)
        self.children[#self.children+1]=child
        child.parent=self
        local slot={Padding={Left=0,Top=0,Right=0,Bottom=0},
            HorizontalAlignment=0,VerticalAlignment=0}
        function slot:IsValid() return true end
        function slot:SetLayout(layout) self.layout=layout end
        function slot:SetAutoSize(autoSize) self.autoSize=autoSize end
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
local made=0
StaticFindObject=function(path)
    assert(path=='/Script/UMG.CanvasPanel')
    return {path=path}
end
StaticConstructObject=function(class,owner)
    assert(class.path=='/Script/UMG.CanvasPanel' and owner==outer)
    made=made+1
    return object('actions-'..made)
end

local seen,fail={},false
local template={objects={root={},actions={}},attach=function(objects,_,original)
    local actions=objects.actions
    assert(actions and actions:GetParent()==root,
        'created object must be attached to its declared parent before every attach')
    seen[#seen+1]=actions
    if fail then error('injected attach failure') end
    return original
end}
local manager=Manager.new(template,(Targets.compile(graph,template.objects)),graph.order,
    {{name='actions',class='/Script/UMG.CanvasPanel',from='root',parent='root'}})
local function named() return {root=root} end
assert(manager:attach(root,named(),{settings={}}))
assert(made==1 and root:GetChildAt(0)==seen[1])
assert(manager:update(root,named(),{settings={changed=1}}))
assert(made==1 and seen[2]==seen[1] and root:GetChildrenCount()==1)
assert(manager:detach(root) and root:GetChildrenCount()==0)

fail=true
assert(not manager:attach(root,named(),{settings={}}))
assert(made==2 and root:GetChildrenCount()==0 and not manager:hasState(root))
fail=false
assert(manager:attach(root,named(),{settings={}}))
assert(made==3 and seen[#seen]~=seen[1])
manager:forget(root)
assert(root:GetChildrenCount()==0 and not manager:hasState(root))

local layoutRoot,layoutOuter=object('layout-root'),object('layout-tree')
function layoutRoot:GetOuter() return layoutOuter end
local wheel=object('wheel')
layoutRoot:AddChild(wheel)
wheel:SetRenderOpacity(0.4)
wheel.Slot:SetPadding({Left=7,Top=8,Right=9,Bottom=10})
local layoutDeclarations={
    root={source='lookup',object='layout-root',required=true},
    wheel={source='reference',from='root',member='Wheel'},
    out={source='create',class='/Script/UMG.CanvasPanel',outer='root',parent='root',
        layout='fill',prepass=true},
    bait={source='create',class='/Script/UMG.Overlay',outer='root',parent='root',
        opacity=0,reparent='wheel',destination='out',
        reparentLayout='canvas',reparentOpacity=1},
}
local layoutGraph=Selectors.compile(layoutDeclarations)
local layoutTemplate={objects={'out','bait'},attach=function(values,_,original)
    assert(values.root==nil and values.wheel==nil,
        'source dependencies must not be exposed to the template')
    assert(values.out:GetChildAt(0)==wheel and values.bait:GetParent()==layoutRoot,
        'bait source must reparent its widget into the output panel')
    assert(values.out.Slot.layout.Anchors.Maximum.X==1 and values.out.Slot.autoSize==false
        and values.out.prepassed and values.bait.opacity==0,
        'source must prepare the output panel and hide its bait before attach')
    assert(wheel.Slot.autoSize==true and wheel.opacity==1,
        'source must prepare the reparented canvas child before attach')
    return original
end}
local layoutManager=Manager.new(layoutTemplate,(Targets.compile(layoutGraph,layoutTemplate.objects)),
    layoutGraph.order,{
        {name='out',class='/Script/UMG.CanvasPanel',from='root',parent='root',
            layout='fill',prepass=true},
        {name='bait',class='/Script/UMG.Overlay',from='root',parent='root',
            opacity=0,reparent='wheel',destination='out',
            reparentLayout='canvas',reparentOpacity=1},
    })
StaticFindObject=function(path) return {path=path} end
StaticConstructObject=function(class,owner)
    assert(owner==layoutOuter)
    return object(class.path)
end
local values={}
assert(layoutManager:attach(layoutRoot,values,{settings={}},{root=layoutRoot,wheel=wheel}))
assert(layoutManager:detach(layoutRoot))
assert(layoutRoot:GetChildrenCount()==1 and layoutRoot:GetChildAt(0)==wheel,
    'detaching source-owned baits must restore the reparented widget')
assert(wheel.opacity==0.4 and wheel.Slot.Padding.Left==7 and wheel.Slot.Padding.Bottom==10,
    'detaching source-owned baits must restore source opacity and slot settings')
print('PASS: created objects attach, reparent source targets, and restore lifecycle state')
