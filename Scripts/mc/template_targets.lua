-- Compile a template's target declaration into an ordered tree. Groups only
-- organize category targets; every leaf still names a category selector.
local M = {}

local function merge(base, extra)
    local result, seen = {}, {}
    for _, source in ipairs({base or {}, extra or {}}) do
        assert(type(source)=='table', 'target properties must be a table')
        for _, property in ipairs(source) do
            if not seen[property] then result[#result+1]=property; seen[property]=true end
        end
        for property, shape in pairs(source) do
            if type(property)=='string' then result[property]=shape end
        end
    end
    return result
end

function M.compile(graph, declaration)
    assert(type(declaration)=='table', 'template.objects must be a table')
    local names, seen, visiting = {}, {}, {}
    local function leaf(name, properties)
        local selector=graph.byName[name]
        assert(selector, 'unknown template target: '..tostring(name))
        assert(not seen[name], 'duplicate template target: '..name)
        seen[name]=true
        names[#names+1]=name
        return {name=name,created=selector.create == true,
            properties=merge(selector.properties,properties)}
    end
    local function group(value, inherited, root)
        assert(type(value)=='table', 'target group must be a table')
        assert(not visiting[value], 'circular template target group')
        visiting[value]=true
        local properties=merge(inherited,value.properties)
        local node={children={},order={}}
        local function add(key, child)
            node.children[key]=child
            node.order[#node.order+1]=key
        end
        for index, item in ipairs(value) do
            if type(item)=='string' then add(root and item or index,leaf(item,properties))
            else add(index,group(item,properties)) end
        end
        local keys={}
        for key in pairs(value) do
            if type(key)=='string' and key~='properties' then keys[#keys+1]=key end
        end
        table.sort(keys)
        for _,key in ipairs(keys) do
            local item=value[key]
            assert(type(item)=='table', 'target declaration must be a table: '..key)
            if graph.byName[key] then
                assert(#item==0, 'category target cannot contain children: '..key)
                add(key,leaf(key,merge(properties,item.properties)))
            else
                add(key,group(item,properties))
            end
        end
        assert(root or #node.order>0, 'empty template target group')
        visiting[value]=nil
        return node
    end
    return group(declaration,nil,true),names
end

function M.arrange(tree, flat, unwrap, valid)
    local function visit(node)
        if node.name then
            local reference=flat and flat[node.name]
            if reference and (not valid or valid(reference)) then
                return unwrap and unwrap(reference) or reference
            end
            return nil
        end
        local result={}
        for _,key in ipairs(node.order) do result[key]=visit(node.children[key]) end
        return result
    end
    return visit(tree)
end

function M.missing(tree, objects, valid, ignoreCreated)
    local function visit(node, value)
        if node.name then
            if ignoreCreated and node.created then return nil end
            if not valid(value) then return node.name end
            return nil
        end
        for _,key in ipairs(node.order) do
            local missing=visit(node.children[key],value and value[key])
            if missing then return missing end
        end
    end
    return visit(tree,objects)
end

function M.find(tree, objects, name)
    local function visit(node, value)
        if node.name then return node.name == name and value or nil end
        for _, key in ipairs(node.order) do
            local found = visit(node.children[key], value and value[key])
            if found then return found end
        end
    end
    return visit(tree, objects)
end

function M.assign(tree, objects, name, value)
    local function visit(node, group)
        for _, key in ipairs(node.order) do
            local child = node.children[key]
            if child.name == name then group[key] = value; return true end
            if child.children and visit(child, group[key]) then return true end
        end
    end
    assert(visit(tree, objects), 'created object not declared by template: ' .. name)
end

return M
