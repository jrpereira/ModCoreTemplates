local Objects = require('mc.objects')
local M = {}

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
    local transform = M.property(widget, 'RenderTransform')
    local value = M.property(transform, member)
    local x, y = M.number(value, 'X'), M.number(value, 'Y')
    assert(transform ~= nil, 'render transform unavailable')
    return {X=x, Y=y}
end

function M.translation(widget) return vector(widget, 'Translation') end
function M.scale(widget) return vector(widget, 'Scale') end

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

function M.appearance(widget, settings, prefix, position)
    M.setTranslation(widget, position.X + settings[prefix .. 'X'],
        position.Y + settings[prefix .. 'Y'])
    M.setScale(widget, settings[prefix .. 'Size'] / 100)
    M.setOpacity(widget, settings[prefix .. 'Opacity'] / 100)
end

function M.reparent(widget, parent)
    local previous = assert(Objects.parent(widget), 'widget parent unavailable')
    assert(previous:RemoveChild(widget) ~= false, 'could not remove widget from parent')
    local slot = assert(parent:AddChild(widget), 'could not reparent widget')
    assert(Objects.valid(slot), 'widget slot unavailable after reparenting')
    slot:SetPadding({Left=0, Top=0, Right=0, Bottom=0})
    slot:SetHorizontalAlignment(1)
    slot:SetVerticalAlignment(1)
    return slot
end

function M.prepareLayout(widget)
    widget:ForceLayoutPrepass()
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

function M.readback(widget)
    local ok, result = pcall(function()
        local position = M.translation(widget)
        return 'opacity=' .. tostring(M.opacity(widget))
            .. ' scale=' .. tostring(M.scale(widget).X)
            .. ' x=' .. tostring(position.X) .. ' y=' .. tostring(position.Y)
    end)
    return ok and result or 'unavailable (' .. tostring(result) .. ')'
end

return M
