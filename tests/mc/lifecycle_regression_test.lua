-- Regression coverage for managed cleanup and target replacement.
local root=arg[1] or '..'
package.path=root..'/ModCoreTemplates/Scripts/?.lua;'..package.path
local Runtime=require('mc.runtime')
local State=require('mc.target_state')
local function object(id)
    local o={id=id,valid=true,children={},opacity=1}
    function o:IsValid() return self.valid end
    function o:GetFullName() return self.id end
    function o:GetParent() return self.parent end
    function o:GetChildrenCount() return #self.children end
    function o:GetChildAt(i) return self.children[i+1] end
    function o:AddChild(child)
        self.children[#self.children+1]=child; child.parent=self
        local slot=object('slot')
        slot.Padding={Left=0,Top=0,Right=0,Bottom=0}
        slot.HorizontalAlignment,slot.VerticalAlignment=0,0
        function slot:SetPadding(value) self.Padding=value end
        function slot:SetHorizontalAlignment(value) self.HorizontalAlignment=value end
        function slot:SetVerticalAlignment(value) self.VerticalAlignment=value end
        function slot:GetClass() return {GetName=function() return 'WidgetSwitcherSlot' end} end
        child.Slot=slot
        return slot
    end
    function o:RemoveChild(child)
        for i,v in ipairs(self.children) do
            if v==child then table.remove(self.children,i); child.parent=nil; return true end
        end
        return false
    end
    function o:GetRenderOpacity() return self.opacity end
    function o:SetRenderOpacity(v)
        if self.failRestore and v==1 then error('injected restore failure') end
        self.opacity=v
    end
    return o
end
local function fixture(template,targets)
    local o=object('root'); o.class='Root'
    local errors={}
    local host={
        valid=function(v) return v~=nil and v.valid~=false end,
        identity=function(v) return v.id end,
        ready=function(v) return v.ready~=false end,
        matches=function(v,s) return v.class==s.class end,
        parent=function(v) return v.parent end,
        member=function(v,name) return v[name] end,
        find=function() return {o} end,
        watch=function() end,
        screen=function() return {width=1920,height=1080} end,
        subscribe=function() return function() end end,
        onError=function(e) errors[#errors+1]=e end,
    }
    template.id,template.category='t','c'
    local runtime=Runtime.new(host,{{name='c',objects=targets or {root={source='lookup',class='Root'}}}},{template})
    runtime:select('c',{t={}})
    return runtime,o,host,errors
end

for _,kind in ipairs({'lost','world_invalidated'}) do
    local subscriptions,cleanups=0,0
    local r,o=fixture({objects={'root'},attach=function(_,params,saved)
        subscriptions=subscriptions+1
        params.onCleanup(function() subscriptions=subscriptions-1;cleanups=cleanups+1 end)
        return saved
    end})
    r:start(); assert(subscriptions==1)
    if kind=='lost' then o.valid=false end
    r:event({kind=kind,id=o.id,epoch=r.epoch})
    r:stop()
    assert(next(r:attachments('t'))==nil and subscriptions==0 and cleanups==1)
end

do
    local seen={}
    local r,o=fixture({managed=false,objects={'child'},
        attach=function(_,_,targets) seen[#seen+1]=targets.child end,
        update=function(_,_,targets) seen[#seen+1]=targets.child end,
        detach=function() end,
    },{root={source='lookup',class='Root'},child={source='reference',from='root',member='child',required=true}})
    local old,new=object('old-child'),object('new-child')
    o.child=old; r:start(); assert(seen[1]==old)
    o.child=new; r:event({kind='changed',object=o,epoch=r.epoch})
    assert(seen[2]==new)
    r:select('c',{t={changed=1}})
    assert(seen[3]==new)
end

do
    local seen={}
    local r,o=fixture({managed=false,objects={group={'child'}},
        attach=function(_,_,targets) seen[#seen+1]=targets.group[1] end,
        update=function(_,_,targets) seen[#seen+1]=targets.group[1] end,
        detach=function() end,
    },{root={source='lookup',class='Root'},child={source='reference',from='root',member='child',required=true}})
    local old,new=object('old-child'),object('new-child')
    o.child=old; r:start(); assert(seen[1]==old)
    old.valid=false; o.child=new
    r:event({kind='changed',object=o,epoch=r.epoch})
    assert(seen[2]==new and not r.errors[1])
end

do
    local parent,other=object('parent'),object('other')
    local a,b,c=object('a'),object('b'),object('c')
    parent:AddChild(a);parent:AddChild(b);parent:AddChild(c)
    local targets,specs,order={b=b},{b={'parent','order'}},{'b'}
    local saved=State.capture(targets,specs,order)
    parent:RemoveChild(b);other:AddChild(b)
    State.restore(targets,specs,order,saved)
    assert(parent.children[1]==a and parent.children[2]==b and parent.children[3]==c)
end

do
    local r,o=fixture({managed=true,objects={root={properties={'opacity'}}},
        attach=function(objects)
            objects.root:SetRenderOpacity(.2)
            objects.root.failRestore=true
            error('injected attach failure')
        end})
    r:start(); assert(o.opacity==.2 and next(r:attachments('t'))==nil)
    o.failRestore=false
    r:select('c',{}); r:stop()
    assert(o.opacity==1)
end

do
    local o=object('switch-root');o.class='Root'
    local sink,epoch,activated
    local host={valid=function(v)return v and v.valid end,
        identity=function(v)return v.id end,ready=function()return true end,
        matches=function(v,s)return v.class==s.class end,parent=function()end,
        find=function()return{o}end,watch=function()end,
        screen=function()return{width=1920,height=1080}end,
        subscribe=function(fn,getEpoch)sink,epoch=fn,getEpoch;return function()end end,
        onError=function()end}
    local old={id='old',category='single',managed=true,
        objects={root={properties={'opacity'}}},
        attach=function(objects)
            objects.root:SetRenderOpacity(.2)
            objects.root.failRestore=true
            error('attach failed')
        end}
    local replacement={id='replacement',category='single',objects={'root'},managed=false,
        attach=function()activated=true end,update=function()end,detach=function()end}
    local r=Runtime.new(host,{{name='single',single=true,objects={root={source='lookup',class='Root'}}}},
        {old,replacement})
    r:select('single',{old={}});r:start()
    r:select('single',{replacement={}})
    assert(not activated and o.opacity==.2)
    o.failRestore=false
    sink({kind='changed',object=o,epoch=epoch()})
    assert(activated and o.opacity==1)
end

do
    local detached=0
    local r,o,host=fixture({managed=false,objects={'root'},attach=function() end,update=function() end,
        detach=function() detached=detached+1 end})
    r:start(); host.screen=function() return nil end
    r:select('c',{});r:stop()
    assert(detached==1 and next(r:attachments('t'))==nil)
end

do
    local cleaned=0
    local manager=require('mc.managed_template').new({attach=function(_,params,saved)
        params.onCleanup(function() cleaned=cleaned+1; if cleaned==1 then error('temporary unsubscribe failure') end end)
        return saved
    end},{root={}},{'root'})
    local o=object('cleanup-root')
    assert(manager:attach(o,{root=o},{settings={}}))
    assert(not manager:detach(o))
    assert(manager:detach(o) and cleaned==2)
end

do
    local live,attempt,releaseAllowed=0,0,false
    local manager=require('mc.managed_template').new({attach=function(_,params,saved)
        attempt=attempt+1
        if attempt==2 then
            live=live+1
            params.onCleanup(function()
                if not releaseAllowed then error('temporary release failure') end
                live=live-1
            end)
            error('update failed after allocating resource')
        end
        return saved
    end},{root={}},{'root'})
    local o=object('update-root')
    assert(manager:attach(o,{root=o},{settings={}}))
    assert(not manager:update(o,{root=o},{settings={changed=1}}))
    assert(manager:hasState(o))
    releaseAllowed=true
    assert(manager:detach(o))
    assert(live==0,'failed update cleanup was lost during recovery')
end
print('PASS: lifecycle regression cases')
