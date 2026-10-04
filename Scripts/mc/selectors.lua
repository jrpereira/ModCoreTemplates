-- Category selector graph. Native discovery and identity belong to the host.
local M = {}
local TemplateTargets = require('mc.template_targets')

function M.compile(objects)
    assert(type(objects) == 'table', 'category.objects must be a table')
    local graph, order, visiting, visited = {}, {}, {}, {}
    for name, value in pairs(objects) do
        assert(type(name) == 'string' and name ~= '', 'object name required')
        assert(type(value) == 'table', name .. ': object declaration must be a table')
        for key in pairs(value) do
            assert(key == 'source' or key == 'object' or key == 'class'
                or key == 'within' or key == 'from' or key == 'member'
                or key == 'outer' or key == 'parent'
                or key == 'reparent' or key == 'destination'
                or key == 'layout' or key == 'opacity' or key == 'prepass'
                or key == 'brushColor'
                or key == 'reparentLayout' or key == 'reparentOpacity'
                or key == 'attach' or key == 'required'
                or key == 'properties', name .. ': unknown object field ' .. tostring(key))
        end
        local source = value.source
        assert(source == 'lookup' or source == 'reference' or source == 'create',
            name .. ': source must be lookup, reference, or create')
        assert(value.properties == nil or type(value.properties) == 'table',
            name .. ': invalid properties')
        if source == 'create' then
            assert(type(value.class) == 'string'
                and value.class:match('^/Script/[%w_]+%.[%w_]+$'),
                name .. ': created object needs a class path')
            assert(type(value.outer) == 'string' and value.outer ~= '',
                name .. ': created object needs an outer object')
            assert(value.parent == nil or type(value.parent) == 'string'
                and value.parent ~= '', name .. ': invalid created object parent')
            assert((value.reparent == nil and value.destination == nil)
                or type(value.reparent) == 'string' and value.reparent ~= ''
                and type(value.destination) == 'string' and value.destination ~= '',
                name .. ': created object reparent needs object and destination')
            assert(value.layout == nil or value.layout == 'fill',
                name .. ': invalid created object layout')
            assert(value.opacity == nil or type(value.opacity) == 'number',
                name .. ': invalid created object opacity')
            if value.brushColor ~= nil then
                assert(type(value.brushColor)=='table',name .. ': invalid brush color')
                for _,component in ipairs({'R','G','B','A'}) do
                    local channel=value.brushColor[component]
                    assert(type(channel)=='number' and channel>=0 and channel<=1,
                        name .. ': invalid brush color component ' .. component)
                end
            end
            assert(value.prepass == nil or type(value.prepass) == 'boolean',
                name .. ': invalid created object prepass')
            assert(value.reparentLayout == nil or value.reparentLayout == 'canvas',
                name .. ': invalid reparent layout')
            assert(value.reparentOpacity == nil or type(value.reparentOpacity) == 'number',
                name .. ': invalid reparent opacity')
            assert(value.object == nil and value.from == nil and value.member == nil
                and value.within == nil and value.attach == nil and value.required == nil
                and value.properties == nil, name .. ': invalid created object declaration')
            graph[name] = {source=source,create=true,class=value.class,outer=value.outer,
                from=value.outer,parent=value.parent,reparent=value.reparent,
                destination=value.destination,
                layout=value.layout,opacity=value.opacity,
                brushColor=value.brushColor,prepass=value.prepass,
                reparentLayout=value.reparentLayout,
                reparentOpacity=value.reparentOpacity,
                attach=false,required=false,properties={}}
        elseif source == 'reference' then
            assert(type(value.from) == 'string' and value.from ~= ''
                and type(value.member) == 'string' and value.member ~= '',
                name .. ': reference needs from and member')
            assert(value.object == nil and value.within == nil and value.outer == nil
                and value.attach == nil and value.parent == nil
                and value.reparent == nil and value.destination == nil
                and value.layout == nil and value.opacity == nil and value.prepass == nil
                and value.brushColor == nil
                and value.reparentLayout == nil and value.reparentOpacity == nil,
                name .. ': invalid reference declaration')
            assert(value.class == nil or type(value.class) == 'string',
                name .. ': invalid reference class')
            assert(value.required == nil or type(value.required) == 'boolean',
                name .. ': invalid required')
            graph[name] = {source=source,from=value.from,member=value.member,
                class=value.class,attach=false,required=value.required == true,
                properties=value.properties}
        else
            assert(value.member == nil and value.outer == nil and value.parent == nil
                and value.reparent == nil and value.destination == nil
                and value.layout == nil and value.opacity == nil and value.prepass == nil
                and value.brushColor == nil
                and value.reparentLayout == nil and value.reparentOpacity == nil,
                name .. ': lookup cannot declare member or outer')
            assert(not (value.from and value.within),
                name .. ': from and within are exclusive')
            if value.from then
                assert(type(value.from) == 'string' and value.from ~= ''
                    and value.object == nil and type(value.class) == 'string',
                    name .. ': scoped lookup needs from and class')
                assert(value.attach == nil and value.required == nil,
                    name .. ': scoped lookup cannot attach independently')
            else
                assert((value.object ~= nil) ~= (value.class ~= nil),
                    name .. ': lookup needs object or class')
            end
            local target=value.object or value.class
            assert(type(target) == 'string' and target ~= '',
                name .. ': invalid lookup target')
            assert(value.within == nil or type(value.within) == 'string',
                name .. ': invalid within')
            assert(value.attach == nil or type(value.attach) == 'boolean',
                name .. ': invalid attach')
            assert(value.required == nil or type(value.required) == 'boolean',
                name .. ': invalid required')
            graph[name] = {source=source,object=value.object,class=value.class,
                within=value.within,from=value.from,attach=value.attach ~= false,
                required=value.required == true,properties=value.properties}
        end
    end
    local function visit(name)
        assert(graph[name], 'unknown within selector: ' .. name)
        assert(not visiting[name], 'circular within reference: ' .. name)
        if visited[name] then return end
        visiting[name] = true
        if graph[name].within then visit(graph[name].within) end
        if graph[name].from then visit(graph[name].from) end
        if graph[name].parent then visit(graph[name].parent) end
        if graph[name].reparent then visit(graph[name].reparent) end
        if graph[name].destination then visit(graph[name].destination) end
        visiting[name], visited[name] = nil, true
        order[#order + 1] = name
    end
    local names = {}
    for name in pairs(graph) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do visit(name) end
    local roots = {}
    for _, name in ipairs(order) do
        local selector = graph[name]
        roots[name] = selector.from and roots[selector.from] or name
    end
    return {byName=graph, order=order, roots=roots}
end

-- A template requests only the category targets it names and their dependencies.
function M.project(graph, targets)
    local _, names=TemplateTargets.compile(graph,targets)
    local wanted={}
    local function include(name)
        local selector=graph.byName[name]
        assert(selector, 'unknown template target: '..tostring(name))
        if wanted[name] then return end
        wanted[name]=true
        if selector.from then include(selector.from) end
        if selector.parent then include(selector.parent) end
        if selector.reparent then include(selector.reparent) end
        if selector.destination then include(selector.destination) end
        if selector.within then include(selector.within) end
    end
    for _,name in ipairs(names) do include(name) end
    local projected={byName={},order={},roots={}}
    for _,name in ipairs(graph.order) do
        if wanted[name] then
            projected.byName[name]=graph.byName[name]
            projected.order[#projected.order+1]=name
            projected.roots[name]=graph.roots[name]
        end
    end
    return projected
end

function M.resolve(graph, candidates, host)
    local sets, union, bundles = {}, {}, {}
    local function beneath(object, roots)
        local seen = {}
        local parent = host.parent(object)
        while parent ~= nil and host.valid(parent) do
            local id = host.identity(parent)
            if seen[id] then return false end
            if roots[id] then return true end
            seen[id] = true
            parent = host.parent(parent)
        end
        return false
    end
    for _, name in ipairs(graph.order) do
        local selector, matches = graph.byName[name], {}
        if selector.create then
            -- Managed templates construct these after existing selectors resolve.
        elseif selector.from then
            for id, bundle in pairs(bundles) do
                local parent = bundle[selector.from]
                if parent and host.valid(parent) then
                    local object
                    if selector.member then object = host.member(parent, selector.member)
                    else object = host.child(parent, selector.class) end
                    if object and host.valid(object)
                        and (not selector.class or host.matches(object, selector)) then
                        bundle[name] = object
                        matches[host.identity(object)] = object
                    end
                end
            end
        else
            for id, object in pairs(candidates) do
                if host.valid(object) and host.matches(object, selector)
                    and (not selector.within or beneath(object, sets[selector.within])) then
                    matches[id] = object
                    if selector.attach then union[id] = object end
                    bundles[id] = bundles[id] or {}
                    bundles[id][name] = object
                end
            end
        end
        sets[name] = matches
    end
    for id, bundle in pairs(bundles) do
        if union[id] then
            for name, selector in pairs(graph.byName) do
                if selector.from and selector.required
                    and bundle[graph.roots[name]] == union[id] and bundle[name] == nil then
                    union[id] = nil
                    break
                end
            end
        end
    end
    return sets, union, bundles
end

return M
