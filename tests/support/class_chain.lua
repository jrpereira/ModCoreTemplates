-- Test double for a UE4SS class chain: GetClass() returns a class whose
-- GetSuperStruct() chain names every path in classes, as Objects.isA walks it.
-- head is the class's own full name; by default one derived from the set.
return function(classes, head)
    local paths = {}
    for path, on in pairs(classes or {}) do if on then paths[#paths + 1] = path end end
    table.sort(paths)
    local function class(full, super)
        return {IsValid=function() return true end, GetFullName=function() return full end,
            GetSuperStruct=function() return super end}
    end
    local super
    for index = #paths, 1, -1 do super = class('Class ' .. paths[index], super) end
    return class(head or ('Class /Test/Classes.' .. table.concat(paths, '+')), super)
end
