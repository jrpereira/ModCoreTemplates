package.path = './Scripts/?.lua;./Scripts/vendor/?.lua;' .. package.path
local Selector = require('mc.object_selector')
local function object(address, full, class, outer)
    local o={address=address,full=full,class=class,outer=outer,alive=true}
    function o:IsValid() return self.alive end
    function o:GetAddress() return self.address end
    function o:GetFullName() return self.full end
    function o:GetClass() return self.class end
    function o:GetOuter() return self.outer end
    function o:IsA(name) return name==self.class.full or name==self.class.full:match('^%S+%s+(.+)$') end
    return o
end
local class=object(1,'WidgetBlueprintGeneratedClass /Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C')
local widgetClass=object(3,'Class /Script/UMG.WidgetSwitcher')
local selector={object='WidgetSwitcher /Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C:WidgetTree.QuickslotsSwitcher'}
local function widget(ownerClass, widgetName, root, offset)
    local owner=object(offset,'WBP_GameHUD_C /Engine/Transient.GameEngine_0.'..root,ownerClass)
    local treeName='WidgetTree_'..offset
    local tree=object(offset+1,'WidgetTree /Engine/Transient.GameEngine_0.'..root..'.'..treeName,nil,owner)
    local leaf=object(offset+2,'WidgetSwitcher /Engine/Transient.GameEngine_0.'..root..'.'..treeName..'.'..widgetName,widgetClass,tree)
    return leaf,owner
end
local live,owner=widget(class,'QuickslotsSwitcher','WBP_GameHUD_C_1',10)
assert(Selector.className(selector)=='WidgetSwitcher')
assert(Selector.matches(live,selector) and Selector.widgetOwner(live,selector)==owner)
local otherName=widget(class,'NotQuickslotsSwitcher','WBP_GameHUD_C_2',20)
assert(not Selector.matches(otherName,selector))
local otherClass=object(2,'WidgetBlueprintGeneratedClass /Game/Other/WBP_GameHUD.WBP_GameHUD_C')
local collision=widget(otherClass,'QuickslotsSwitcher','WBP_GameHUD_C_3',30)
assert(not Selector.matches(collision,selector))
local asset=object(50,'WBP_GameHUD_C /Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.Default__WBP_GameHUD_C',class)
local tree=object(51,'WidgetTree /Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.Default__WBP_GameHUD_C.WidgetTree',nil,asset)
local default=object(52,'WidgetSwitcher /Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.Default__WBP_GameHUD_C.WidgetTree.QuickslotsSwitcher',nil,tree)
assert(not Selector.matches(default,selector))
live.alive=false; assert(not Selector.matches(live,selector)); live.alive=true
assert(Selector.matches(live,{class=widgetClass.full:match('^%S+%s+(.+)$')}))
assert(Selector.className({class='/Script/UMG.WidgetSwitcher'})=='WidgetSwitcher')
print('PASS: exact live WidgetTree owner and class selector checks')
