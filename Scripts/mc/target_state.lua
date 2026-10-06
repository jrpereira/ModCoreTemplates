-- Reversible property capture for category targets, including target lists.
local Objects = require('mc.objects')
local Widget = require('mc.widget')
local TemplateTargets = require('mc.template_targets')
local M = {}

function M.specs(graph,extensions)
    local tree=TemplateTargets.compile(graph,extensions)
    return tree
end

local function fields(spec)
    local result={}
    for _, name in ipairs(spec) do result[#result+1]=name end
    local named={}
    for name in pairs(spec) do if type(name)=='string' then named[#named+1]=name end end
    table.sort(named)
    for _, name in ipairs(named) do result[#result+1]=name end
    return result
end

local function read(object,name)
    if name=='box' then
        local box,detail=Widget.box(object)
        return assert(box,'target layout unavailable: '..tostring(detail))
    end
    if name=='widthOverride' or name=='heightOverride' then
        local field=name=='widthOverride' and 'WidthOverride' or 'HeightOverride'
        return {enabled=Widget.property(object,'bOverride_'..field)==true,value=Widget.number(object,field)}
    end
    if name=='activeIndex' then return object:GetActiveWidgetIndex() end
    -- Restored later, possibly after the parent died: kept as a weak handle.
    if name=='parent' then
        local parent=Objects.parent(object)
        if parent==nil then return nil end
        local handle,why=Objects.hold(parent)
        return assert(handle,'target parent cannot be kept: '..tostring(why))
    end
    if name=='order' then
        local parent=assert(Objects.parent(object), 'target has no panel parent')
        for index=0,parent:GetChildrenCount()-1 do
            if Objects.same(parent:GetChildAt(index),object) then return index end
        end
        error('target is not a child of its panel parent')
    end
    if name=='slot' then return Widget.snapshotSlot(object) end
    if name=='position' then return Widget.translation(object) end
    if name=='size' then return Widget.scale(object) end
    if name=='opacity' then return Widget.opacity(object) end
    error('unsupported target property '..tostring(name))
end

local function write(object,name,value)
    if name=='widthOverride' or name=='heightOverride' then
        local field=name=='widthOverride' and 'WidthOverride' or 'HeightOverride'
        object['Set'..field](object,value.value)
        if not value.enabled then object['Clear'..field](object) end
        return
    end
    if name=='activeIndex' then object:SetActiveWidgetIndex(value); return end
    if name=='slot' then Widget.restoreSlot(object,value); return end
    if name=='position' then Widget.setTranslation(object,value.X,value.Y); return end
    if name=='size' then Widget.setScale(object,value.X,value.Y); return end
    if name=='opacity' then Widget.setOpacity(object,value); return end
    error('unsupported target property '..tostring(name))
end

local function selected(value,shape)
    if shape==nil or shape==true then return value end
    assert(type(shape)=='table', 'invalid property shape')
    local result={}
    for _, name in ipairs(fields(shape)) do
        result[name]=selected(Widget.property(value,name),shape[name])
    end
    return result
end

local function captureOne(object,spec)
    assert(Objects.valid(object), 'target unavailable')
    local result={}
    for _, name in ipairs(fields(spec)) do result[name]=selected(read(object,name),spec[name]) end
    return result
end

local function restoreOne(object,spec,values)
    assert(Objects.valid(object), 'target unavailable for restoration')
    local names=fields(spec)
    for index=#names,1,-1 do
        local name=names[index]
        if name~='parent' and name~='order' and name~='box' then
            write(object,name,assert(values[name], 'missing saved property '..name))
        end
    end
end

local function collectParents(object,spec,values,result)
    if spec.children then
        for _,key in ipairs(spec.order) do
            collectParents(object[key],spec.children[key],values[key],result)
        end
        return
    end
    if Objects.valid(object) then
        if values.parent~=nil then
            result[#result+1]={object=object,parent=values.parent,order=values.order or 0}
        end
        return
    end
    for index,child in ipairs(object) do collectParents(child,spec,values[index],result) end
end

local function restoreParentRecords(records)
    local groups={}
    local function same(a,b) return Objects.same(a,b) end
    for _,record in ipairs(records) do
        record.parent=assert(Objects.get(record.parent), 'saved parent unavailable')
        local key=assert(Objects.call(record.parent,'GetFullName'), 'saved parent has no identity')
        local group=groups[key]
        if not group then group={parent=record.parent,records={}}; groups[key]=group end
        group.records[#group.records+1]=record
    end
    local plans={}
    for _,group in pairs(groups) do
        local current={}
        for index=0,group.parent:GetChildrenCount()-1 do
            current[#current+1]=group.parent:GetChildAt(index)
        end
        local desired={}
        for _,child in ipairs(current) do
            local owned=false
            for _,record in ipairs(records) do
                if same(child,record.object) then owned=true; break end
            end
            if not owned then desired[#desired+1]=child end
        end
        table.sort(group.records,function(a,b)
            if a.order==b.order then
                return Objects.call(a.object,'GetFullName')<Objects.call(b.object,'GetFullName')
            end
            return a.order<b.order
        end)
        for _,record in ipairs(group.records) do
            table.insert(desired,math.min(record.order+1,#desired+1),record.object)
        end
        local changed=#current~=#desired
        if not changed then
            for index,child in ipairs(current) do
                if not same(child,desired[index]) then changed=true; break end
            end
        end
        if changed then
            local slots={}
            for _,child in ipairs(current) do
                -- All remaining siblings are rebuilt below. Capture every
                -- slot before removing any child, or leave the panel intact.
                slots[Objects.call(child,'GetFullName')]=Widget.snapshotSlot(child,true)
            end
            plans[#plans+1]={parent=group.parent,desired=desired,slots=slots}
        end
    end
    for _,record in ipairs(records) do
        local parent=Objects.parent(record.object)
        if parent and not same(parent,record.parent) then
            assert(parent:RemoveChild(record.object)~=false,'could not detach target')
        end
    end
    for _,plan in ipairs(plans) do
        local parent=plan.parent
        for index=parent:GetChildrenCount()-1,0,-1 do
            assert(parent:RemoveChild(parent:GetChildAt(index))~=false,
                'could not clear original parent for ordering')
        end
        for _,child in ipairs(plan.desired) do
            assert(Objects.valid(parent:AddChild(child)),'could not restore parent')
            local slot=plan.slots[Objects.call(child,'GetFullName')]
            if slot then Widget.restoreSlot(child,slot) end
        end
    end
end

local function restoreParents(targets,specs,order,saved)
    local records={}
    for _,name in ipairs(order) do
        if saved[name]~=nil then collectParents(targets[name],specs[name],saved[name],records) end
    end
    restoreParentRecords(records)
end

local function captureTree(object,spec)
    if spec.children then
        assert(type(object)=='table', 'target group must be a table')
        local result={}
        for _,key in ipairs(spec.order) do
            result[key]=captureTree(object[key],spec.children[key])
        end
        return result
    end
    if Objects.valid(object) then return captureOne(object,spec.properties or spec) end
    assert(type(object)=='table', 'target must be an object or list')
    local result={}
    for index,child in ipairs(object) do result[index]=captureTree(child,spec) end
    return result
end

local function restoreTree(object,spec,values)
    if spec.children then
        assert(type(object)=='table' and type(values)=='table', 'invalid target group')
        for index=#spec.order,1,-1 do
            local key=spec.order[index]
            restoreTree(object[key],spec.children[key],values[key])
        end
        return
    end
    if Objects.valid(object) then return restoreOne(object,spec.properties or spec,values) end
    assert(type(object)=='table' and type(values)=='table', 'invalid target list')
    for index=#object,1,-1 do restoreTree(object[index],spec,values[index]) end
end

function M.capture(targets,specs,order)
    if specs.children then return captureTree(targets,specs) end
    local saved={}
    for _,name in ipairs(order) do
        if specs[name] and targets[name]~=nil then
            saved[name]=captureTree(targets[name],specs[name])
        end
    end
    return saved
end

function M.restore(targets,specs,order,saved)
    if specs.children then
        local records={}
        collectParents(targets,specs,saved,records)
        restoreParentRecords(records)
        restoreTree(targets,specs,saved)
        return true
    end
    restoreParents(targets,specs,order,saved)
    for index=#order,1,-1 do
        local name=order[index]
        if saved[name]~=nil then restoreTree(targets[name],specs[name],saved[name]) end
    end
    return true
end

return M
