package.path = './Scripts/?.lua;./Scripts/vendor/?.lua;' .. package.path
local MC = require('mc.objects')
local function object(name)
    return {
        IsValid=function(self) return not self.dead end,
        GetFullName=function() return name end,
        GetParent=function(self) return self.parent end,
    }
end
local a, alias, b = object('Widget /live.A'), object('Widget /live.A'), object('Widget /live.B')
assert(MC.valid(a) and not MC.valid(nil) and not MC.valid({}))
assert(MC.same(a, alias) and not MC.same(a, b))
assert(not MC.same(object(nil), object(nil)))
assert(not MC.same(object(''), object('')))
a.parent=b
assert(MC.parent(a)==b)
b.dead=true
assert(MC.parent(a)==nil and not MC.same(b,b))
a.dead=true
function a:GetParent() error('invalid object must not be accessed') end
assert(MC.parent(a)==nil)
local broken = object('broken')
function broken:IsValid() error('invalid wrapper') end
assert(not MC.valid(broken))
function alias:GetFullName() error('unavailable name') end
assert(not MC.same(object('Widget /live.A'),alias))
function alias:GetParent() error('unavailable parent') end
assert(MC.parent(alias)==nil)
assert(MC.call({add=function(_,a,b) return a+b end},'add',2,3)==5)
print('PASS: shared object helpers handle invalid wrappers, aliases and parent loss')

-- isA walks the object's class chain and never calls UE4SS IsA, whose string form
-- runs a whole-object StaticFindObject walk; each class is read once.
do
    local reads=0
    local function class(full,super)
        return {IsValid=function() return true end,
            GetFullName=function() reads=reads+1; return full end,
            GetSuperStruct=function() return super end}
    end
    local widget=class('Class /Script/UMG.Widget',class('Class /Script/CoreUObject.Object'))
    local hud=class('WidgetBlueprintGeneratedClass /Game/HUD/WBP_Hud.WBP_Hud_C',class('Class /Script/UMG.UserWidget',widget))
    local instance={IsValid=function() return true end,GetClass=function() return hud end,
        IsA=function() error('string IsA must not be used') end}
    assert(MC.isA(instance,'/Game/HUD/WBP_Hud.WBP_Hud_C'))
    assert(MC.isA(instance,'/Script/UMG.UserWidget') and MC.isA(instance,'Class /Script/UMG.Widget'))
    assert(not MC.isA(instance,'/Script/UMG.PanelWidget'))
    reads=0
    for _=1,10 do MC.isA(instance,'/Script/UMG.Widget') end
    assert(reads==10,'a known class costs one name read per check: '..reads)
    assert(not MC.isA({IsValid=function() return false end},'/Script/UMG.Widget'))
    print('PASS: isA walks the class chain once per class')
end

do
    -- A class chain that cannot be read falls back to UE4SS IsA.
    local bare={IsValid=function() return true end,GetFullName=function() return 'Class /Test/Bare.Bare' end}
    local instance={IsValid=function() return true end,GetClass=function() return bare end,
        IsA=function(_,path) return path=='/Script/UMG.Widget' end}
    assert(MC.isA(instance,'/Script/UMG.Widget') and not MC.isA(instance,'/Script/UMG.UserWidget'))
    print('PASS: isA falls back to IsA without GetSuperStruct')
end
