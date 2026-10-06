local Objects = require('mc.objects')
local M = {}
local currentSlots=setmetatable({}, {__mode='k'})

function M.unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function() return value:get() end)
    if ok then return result end
    return value
end

function M.property(object, name)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[name] end)
    if ok then return M.unwrap(value) end
end

function M.number(object, name)
    local value = tonumber(M.property(object, name))
    assert(value and value == value and math.abs(value) < math.huge,
        'unavailable visual property ' .. tostring(name))
    return value
end

local function vector(widget, member)
    -- UE4SS struct fields are views into their parent struct. Keep that
    -- parent wrapper alive while reading the nested vector components.
    local transform = assert(M.property(widget, 'RenderTransform'), 'render transform unavailable')
    local value = M.property(transform, member)
    return {X=M.number(value, 'X'), Y=M.number(value, 'Y')}
end

function M.translation(widget) return vector(widget, 'Translation') end
function M.scale(widget) return vector(widget, 'Scale') end

local relativePositions={
    [1]={X=-1,Y=0}, [2]={X=-1,Y=1}, [3]={X=0,Y=1}, [4]={X=1,Y=1},
    [5]={X=1,Y=0}, [6]={X=1,Y=-1}, [7]={X=0,Y=-1}, [8]={X=-1,Y=-1},
}

function M.relative(align)
    local position=assert(relativePositions[align],'unknown widget alignment')
    return {X=position.X,Y=position.Y}
end

function M.opacity(widget)
    local value = tonumber(widget:GetRenderOpacity())
    assert(value and value == value and math.abs(value) < math.huge, 'unavailable render opacity')
    return value
end

function M.setTranslation(widget, x, y)
    local current = M.translation(widget)
    if current.X ~= x or current.Y ~= y then widget:SetRenderTranslation({X=x, Y=y}) end
end

function M.setScale(widget, x, y)
    y = y or x
    local current = M.scale(widget)
    if current.X ~= x or current.Y ~= y then widget:SetRenderScale({X=x, Y=y}) end
end

function M.setOpacity(widget, value)
    if M.opacity(widget) ~= value then widget:SetRenderOpacity(value) end
end

function M.prepareLayout(widget)
    widget:ForceLayoutPrepass()
end

-- Slots are kept as weak handles: a slot can die before its widget.
function M.rememberSlot(widget,slot)
    if Objects.valid(widget) and Objects.valid(slot) then currentSlots[widget]=Objects.hold(slot) end
    return slot
end

function M.slot(widget)
    local slot=Objects.get(currentSlots[widget])
    if slot then return slot end
    slot=M.property(widget,'Slot')
    if Objects.valid(slot) then currentSlots[widget]=Objects.hold(slot); return slot end
end

function M.box(widget)
    local function dimensions(size)
        local width=size and tonumber(M.property(size,'X'))
        local height=size and tonumber(M.property(size,'Y'))
        if width and width>0 and height and height>0 then return width,height,width,height end
        return nil,nil,width,height
    end
    local desired=Objects.call(widget,'GetDesiredSize')
    local width,height,desiredWidth,desiredHeight=dimensions(desired)
    local source='desired'
    local propertyWidth,propertyHeight
    if not width then
        width,height,propertyWidth,propertyHeight=dimensions(M.property(widget,'DesiredSize'))
        source='property'
    end
    local rootWidth,rootHeight
    if not width then
        local tree=M.property(widget,'WidgetTree')
        local root=M.property(tree,'RootWidget')
        rootWidth=tonumber(M.property(root,'WidthOverride'))
        rootHeight=tonumber(M.property(root,'HeightOverride'))
        if rootWidth and rootWidth>0 and rootHeight and rootHeight>0 then
            width,height=rootWidth,rootHeight
            source='root-sizebox'
        end
    end
    local pivot=M.property(widget,'RenderTransformPivot')
    local pivotX=pivot and tonumber(M.property(pivot,'X'))
    local pivotY=pivot and tonumber(M.property(pivot,'Y'))
    local detail=string.format(
        'desired=%s,%s property=%s,%s root=%s,%s pivot=%s,%s',
        tostring(desiredWidth),tostring(desiredHeight),
        tostring(propertyWidth),tostring(propertyHeight),
        tostring(rootWidth),tostring(rootHeight),tostring(pivotX),tostring(pivotY))
    if not width or not height or pivotX==nil or pivotY==nil then return nil,detail end
    return {width=width,height=height,pivotX=pivotX,pivotY=pivotY},source..' '..detail
end

function M.measure(widget)
    local size = widget:GetDesiredSize()
    local width, height = M.number(size, 'X'), M.number(size, 'Y')
    assert(width > 0 and height > 0, 'widget layout size is not ready')
    local pivot = assert(M.property(widget, 'RenderTransformPivot'), 'widget pivot unavailable')
    return {width=width, height=height, pivotX=M.number(pivot, 'X'), pivotY=M.number(pivot, 'Y')}
end

-- Place the rendered bounds at x/y, including negative scale and pivot.
function M.position(widget, box, x, y, scale)
    M.setScale(widget, scale)
    M.setTranslation(widget,
        x - box.pivotX * box.width * (1 - scale) - math.min(0, scale * box.width),
        y - box.pivotY * box.height * (1 - scale) - math.min(0, scale * box.height))
    return true
end

function M.canvasPosition(widget, box, x, y, scale)
    M.setScale(widget, scale)
    local slot=M.slot(widget)
    if not slot then return false,'wheel canvas slot unavailable' end
    local position={
        X=x - box.pivotX * box.width * (1 - scale) - math.min(0, scale * box.width),
        Y=y - box.pivotY * box.height * (1 - scale) - math.min(0, scale * box.height),
    }
    local ok,why=pcall(function() slot:SetPosition(position) end)
    if not ok then return false,'wheel canvas position failed: '..tostring(why) end
    ok,why=pcall(function() slot:SetSize({X=box.width,Y=box.height}) end)
    if not ok then return false,'wheel canvas size failed: '..tostring(why) end
    M.setTranslation(widget,0,0)
    return true
end

function M.snapshotSlot(widget, forReordering)
    local slot = assert(M.property(widget, 'Slot'), 'widget slot unavailable')
    local class = Objects.call(slot, 'GetClass')
    local className = class and Objects.call(class, 'GetName')
    local padding = M.property(slot, 'Padding')
    if className~='CanvasPanelSlot' and padding ~= nil then
        local readable, values = pcall(function()
            return {
                Left=M.number(padding, 'Left'), Top=M.number(padding, 'Top'),
                Right=M.number(padding, 'Right'), Bottom=M.number(padding, 'Bottom'),
            }
        end)
        if readable then
            if forReordering and type(className)=='string' then
                assert(className=='OverlaySlot' or className=='WidgetSwitcherSlot',
                    'unsupported widget slot for reversible reordering: '..className)
            end
            return {kind='padding',padding=values,
                horizontal=M.number(slot, 'HorizontalAlignment'),
                vertical=M.number(slot, 'VerticalAlignment')}
        end
    end
    local layout = M.property(slot, 'LayoutData')
    if layout ~= nil then
        local offsets = assert(M.property(layout, 'Offsets'), 'canvas slot offsets unavailable')
        local anchors = assert(M.property(layout, 'Anchors'), 'canvas slot anchors unavailable')
        local minimum = assert(M.property(anchors, 'Minimum'), 'canvas slot minimum unavailable')
        local maximum = assert(M.property(anchors, 'Maximum'), 'canvas slot maximum unavailable')
        local alignment = assert(M.property(layout, 'Alignment'), 'canvas slot alignment unavailable')
        local autoSize = M.property(slot, 'bAutoSize')
        if type(autoSize) ~= 'boolean' then autoSize = Objects.call(slot, 'GetAutoSize') end
        assert(type(autoSize)=='boolean', 'canvas slot auto size unavailable')
        return {kind='canvas',layout={
            Offsets={Left=M.number(offsets,'Left'),Top=M.number(offsets,'Top'),
                Right=M.number(offsets,'Right'),Bottom=M.number(offsets,'Bottom')},
            Anchors={Minimum={X=M.number(minimum,'X'),Y=M.number(minimum,'Y')},
                Maximum={X=M.number(maximum,'X'),Y=M.number(maximum,'Y')}},
            Alignment={X=M.number(alignment,'X'),Y=M.number(alignment,'Y')},
        },zOrder=M.number(slot,'ZOrder'),autoSize=autoSize}
    end
    error('unsupported widget slot for reversible reordering')
end

function M.restoreSlot(widget, state)
    assert(type(state) == 'table', 'invalid slot snapshot')
    local slot = assert(M.property(widget, 'Slot'), 'widget slot unavailable')
    if state.kind=='canvas' then
        slot:SetLayout(state.layout)
        slot:SetZOrder(state.zOrder)
        slot:SetAutoSize(state.autoSize)
        return
    end
    assert(state.kind=='padding' and type(state.padding)=='table', 'invalid slot snapshot')
    slot:SetPadding(state.padding)
    slot:SetHorizontalAlignment(state.horizontal)
    slot:SetVerticalAlignment(state.vertical)
end

return M
