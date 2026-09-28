package.path='./Scripts/?.lua;'..package.path
local Selectors=require('mc.selectors')
local State=require('mc.target_state')
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
    local value={name=name,children={}}
    function value:IsValid() return true end
    function value:GetFullName() return self.name end
    function value:GetParent() return self.parent end
    function value:GetChildrenCount() return #self.children end
    function value:GetChildAt(index) return self.children[index+1] end
    function value:AddChild(child)
        assert(child.parent==nil)
        self.children[#self.children+1]=child
        child.parent=self
        return child
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
local manager=Manager.new(template,State.specs(graph,template.objects),graph.order,
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
assert(manager:attach(root,named(),{settings={}}))
manager:reset()
assert(root:GetChildrenCount()==0 and not manager:hasState(root))
print('PASS: created objects attach to declared parents, survive update and clean up on failure, detach, forget and reset')
