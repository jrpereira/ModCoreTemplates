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
