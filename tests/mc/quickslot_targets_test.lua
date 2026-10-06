package.path='./Scripts/?.lua;'..package.path
dofile('tests/support/lifetimes.lua').install()
local Selectors=require('mc.selectors')
local Runtime=require('mc.runtime')
local category=dofile('Scripts/categories/player_quickslots.lua')
local graph=Selectors.compile(category.objects)
local radialCategory=dofile('Scripts/categories/player_radial.lua')
local radialGraph=Selectors.compile(radialCategory.objects)
assert(category.name=='player.quickslots' and radialCategory.name=='player.radial')
assert(category.objects.radial==nil and radialCategory.objects.radial~=nil)
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
    function value:GetRenderOpacity() return self.opacity end
    function value:SetRenderOpacity(opacity) self.opacity=opacity end
    function value:SetRenderTranslation(position) self.RenderTransform.Translation=position end
    function value:ForceLayoutPrepass() self.prepassed=true end
    function value:AddChild(child)
        assert(child.parent==nil)
        self.children[#self.children+1]=child; child.parent=self
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
            if item==child then table.remove(self.children,index); child.parent=nil; return true end
        end
        return false
    end
    objects[#objects+1]=value
    return value
end
local switcher=object('switcher','WidgetSwitcher')
local ability=object('ability','WBP_AA_Quickslots_C')
local consumable=object('consumable','WBP_HUD_Quickslots_C')
local hud=object('hud','WBP_GameHUD_C')
switcher.owner=hud
local hudTree=object('hudTree','WidgetTree')
local hudRoot=object('hudRoot','Overlay')
hud.members.WidgetTree=hudTree
hudTree.members.RootWidget=hudRoot
hud.members.WBP_AA_Quickslots=ability
hud.members.WBP_HUD_Quickslots=consumable
-- Native order differs from selector creation order, with an unrelated sibling.
switcher:AddChild(consumable)
local sibling=object('nativeSibling','Overlay')
switcher:AddChild(sibling)
switcher:AddChild(ability)
ability.Slot:SetPadding({Left=11,Top=12,Right=13,Bottom=14})
ability.Slot:SetHorizontalAlignment(2)
consumable.Slot:SetVerticalAlignment(2)
local function directions(parent,prefix,bindings)
    local source=bindings or parent
    for _,direction in ipairs({'Left','Top','Right','Bottom'}) do
        local button=object(prefix..direction,'CommonActionWidget')
        if bindings then source.members[direction]=button
        else
            local entity=object(prefix..direction..'Entity','RadialEntity')
            entity.members.Button=button
            source.members[direction]=entity
        end
    end
end
local abilityBindings=object('abilityBindings','Bindings')
local consumableBindings=object('consumableBindings','Bindings')
ability.members.WBP_AA_Quickslots_Bindings=abilityBindings
consumable.members.WBP_HUD_Quickslots_Bindings=consumableBindings
directions(ability,'ability',abilityBindings)
directions(consumable,'consumable',consumableBindings)
-- Bar selects actual gameplay buttons, independently of the binding glyphs.
for _,entry in ipairs({{ability,'ability'},{consumable,'consumable'}})do
    local wheel,prefix=entry[1],entry[2]
    local tree=object(prefix..'Tree','WidgetTree')
    local box=object(prefix..'Box','SizeBox')
    local panel=object(prefix..'Panel','Overlay')
    wheel.members.WidgetTree=tree;tree.members.RootWidget=box;box.children={panel}
    wheel.members.cross=object(prefix..'Cross','Image')
    if prefix=='ability' then
        wheel.members.Darken=object(prefix..'Darken','Image')
        wheel.members.Glow=object(prefix..'Glow','Image')
    end
    for _,direction in ipairs({'Left','Top','Right','Bottom'})do
        wheel.members[direction]=object(prefix..'Button'..direction,'QuickslotButton')
    end
end
local hudRadial=object('hudRadial','WBP_Combat_Focus_QuickslotBindingsRadial_C')
local hubRadial=object('hubRadial','WBP_Combat_Focus_QuickslotBindingsRadial_C')
directions(hudRadial,'hud')
directions(hubRadial,'hub')
switcher.outer=object('switcherOuter','WidgetTree')
FName=function(value) return value end
StaticFindObject=function(path) return {path=path} end
StaticConstructObject=function(class,outer)
    assert(outer==switcher.outer)
    return object(class.path,class.path:match('([^%.]+)$'))
end
local host={}
host.valid=function(value) return value~=nil end
host.identity=function(value) return value.id end
host.ready=function() return true end
host.matches=function(value,selector)
    return selector.object~=nil and value==switcher
        or selector.class~=nil and value.class==selector.class:match('([^%.]+)$')
end
host.parent=function() return nil end
host.watch=function() end
host.screen=function() return {width=1920,height=1080,left=0,center=960,right=1920,
    bottom=0,middle=540,top=1080} end
host.child=function(parent,class)
    for _,candidate in ipairs(parent.children) do
        if candidate.class==class then return candidate end
    end
end
host.member=function(parent,path)
    local value=parent
    for key in path:gmatch('[^.]+') do
        value=value and (key=='@owner' and value.owner or value.members[key])
    end
    return value
end
local lookedUp={}
host.find=function(selector)
    assert(not selector.from, 'scoped target was globally searched')
    lookedUp[#lookedUp+1]=selector
    local result={}
    for _,value in ipairs(objects) do
        if host.matches(value,selector) then result[#result+1]=value end
    end
    return result
end
host.subscribe=function() return function() end end
host.onError=function(error) error(error.message) end
local candidates={}
for _,selector in pairs(category.objects) do
    if selector.source=='lookup' and not selector.from then
        for _,value in ipairs(host.find(selector)) do candidates[value.id]=value end
    end
end
local sets,attached,bundles=Selectors.resolve(graph,candidates,host)
assert(bundles.switcher.ability_left.id=='abilityLeft')
assert(bundles.switcher.hud_root==hudRoot)
assert(bundles.switcher.consumable_right.id=='consumableRight')
assert(attached.switcher and not sets.radial)
assert(bundles.switcher.ability_button_left.id=='abilityButtonLeft')
assert(bundles.switcher.consumable_button_bottom.id=='consumableButtonBottom')
assert(bundles.switcher.ability_panel.id=='abilityPanel')
assert(bundles.switcher.consumable_box.id=='consumableBox')
local radialCandidates={}
for _,selector in pairs(radialCategory.objects) do
    if selector.source=='lookup' and not selector.from then
        for _,value in ipairs(host.find(selector)) do radialCandidates[value.id]=value end
    end
end
local radialSets,radialAttached,radialBundles=Selectors.resolve(radialGraph,radialCandidates,host)
assert(radialSets.radial.hudRadial and radialSets.radial.hubRadial)
assert(radialBundles.hudRadial.radial_left.id=='hudLeft')
assert(radialBundles.hubRadial.radial_bottom.id=='hubBottom')
assert(not radialAttached.hudRadial and not radialAttached.hubRadial)
lookedUp={}
local categoryOnly=Runtime.new(host,{category},{})
categoryOnly:start()
assert(#lookedUp==1 and lookedUp[1].object==category.objects.switcher.object,
    'only required category targets are searched without a template')
categoryOnly:stop()
lookedUp={}
local calls={}
local template={id='layout',category=category.name,managed=false,
    objects={'switcher','abilities','consumables','actions'},
    attach=function(_,_,targets)
        assert(targets.abilities==ability and targets.consumables==consumable)
        assert(targets.actions==ability:GetParent()
            and targets.actions==consumable:GetParent(),
            'both wheels must be direct children of the MCT canvas')
        calls[#calls+1]='attach'
    end,
    update=function(_,_,targets)
        assert(targets.abilities==ability)
        calls[#calls+1]='update'
    end,
    detach=function() calls[#calls+1]='detach' end,
}
local runtime=Runtime.new(host,{category},{template})
runtime:select(category.name,{layout={}})
runtime:start()
assert(#lookedUp==1 and lookedUp[1].object==category.objects.switcher.object,
    'unused quickslot targets must not be searched')
assert(#calls==1 and calls[1]=='attach',runtime.errors[1] and runtime.errors[1].message)
assert(ability:GetParent()~=switcher and consumable:GetParent()~=switcher,
    'shared category infrastructure must detach both wheels before template attach')
assert(ability.Slot.autoSize==true and consumable.Slot.autoSize==true
    and ability.Slot.layout.Anchors.Maximum.X==0,
    'wheels must use top-left autosized canvas slots')
runtime:select(category.name,{layout={Style=1}})
assert(#calls==2 and calls[2]=='update',
    'HUD-owned wheel targets remain resolvable after category reparenting')
runtime:event({kind='changed',object=switcher,epoch=runtime.epoch})
assert(#calls==2, 'unchanged wheel identities must not reattach')
runtime:stop()
assert(#calls==3 and calls[3]=='detach')
assert(ability:GetParent()==switcher and consumable:GetParent()==switcher,
    'shared category infrastructure must restore the native switcher hierarchy')
assert(switcher:GetChildrenCount()==3 and switcher:GetChildAt(0)==consumable
    and switcher:GetChildAt(1)==sibling and switcher:GetChildAt(2)==ability,
    'shared hosts must restore original wheel order around unrelated siblings')
assert(ability.Slot.Padding.Left==11 and ability.Slot.Padding.Bottom==14
    and ability.Slot.HorizontalAlignment==2 and consumable.Slot.VerticalAlignment==2,
    'shared hosts must restore native wheel slot settings')
print('PASS: separate quickslot and radial targets, two radials, one attachment')
