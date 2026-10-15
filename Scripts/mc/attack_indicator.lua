-- MC_NPCAttackIndicator: the game's combat target indicator as update events.
--
-- The indicator blueprint receives each enemy's state from the game as one
-- icon type (OnObservedStubIconTypeChanged): the attack's direction, its parry
-- window, the unblockable skull, or none. UE4SS's own hooks miss that
-- Blueprint call; UE4SSLuaEventBridge's hooks see it. It is hooked only while a
-- template listens (MCT starts and stops this source).
--
-- The bridge copies each call and delivers it on the game thread on the next
-- engine tick, so events follow the game's change by about one frame. They are
-- tables with kind and:
--   arrow        direction, path, indicator: an attack shows on an indicator
--   critical     direction, path, indicator: that attack's parry window opened
--   resolve      path, indicator, reason ('sword' or 'hidden'): an indicator's
--                attack ended
--   unblockable  path, indicator, active: the unblockable skull showed (true) or went
-- direction follows ARROWS: 1 top, 2 bottom, 3 left, 4 right. indicator is the
-- live object, valid only during the event; path names it for later.
local Objects = require('mc.objects')

local M = {}
M.ARROWS = {'TopArrow', 'BottomArrow', 'LeftArrow', 'RightArrow'}
M.ICON = '/Game/_Dawnwalker/UI/_Unified/Combat/WBP_CombatTargetIndicator.WBP_CombatTargetIndicator_C:OnObservedStubIconTypeChanged'
-- ERebelIndicatorIconType: 0 defending, 1-4 attacking from left, right, top,
-- bottom, 5-8 the same in the parry window, 9 unblockable, 10-13 weak spots.
-- Its 1-4 as ARROWS indices.
local DIRECTIONS = {[1]=3, [2]=4, [3]=1, [4]=2}
local UNBLOCKABLE = 9

local function call(object, method, ...) return Objects.call(object, method, ...) end
local valid = Objects.valid

local function visibleChain(widget)
    local current, visited = widget, 0
    while valid(current) and visited < 32 do
        if call(current, 'IsVisible') ~= true then return false end
        local opacity = call(current, 'GetRenderOpacity')
        if type(opacity) == 'number' and opacity <= 0 then return false end
        current = Objects.parent(current)
        visited = visited + 1
    end
    return true
end

-- The game updates hidden twin indicators too: only a widget whose every
-- ancestor is visible and not transparent is on screen.
function M.visible(widget) return valid(widget) and visibleChain(widget) end

-- An icon type's attack direction and whether it is the parry window, or nil.
function M.attackOf(icon)
    if DIRECTIONS[icon] then return DIRECTIONS[icon], false end
    if DIRECTIONS[icon - 4] and icon <= 8 then return DIRECTIONS[icon - 4], true end
end

-- api: UE4SSLuaEventBridge (or the global one) with hooks, and StaticFindObject.
-- emit(event) delivers an event; log is a leveled logger or nil.
function M.new(api, emit, log)
    assert(type(emit) == 'function', 'emit required')
    local self = {active = false}
    -- Per indicator path, the attack it shows: {direction, critical}.
    local attacks = {}
    -- The indicator showing the unblockable skull, if any.
    local skullSource
    local handle
    local delivered, sequence = 0, 0
    local failures = {}

    local function fail(kind, why)
        local count = failures[kind]
        failures[kind] = (count or 0) + 1
        if not count and log then log.error('attack indicator ', kind, ' failed: ', why) end
    end
    local function send(event)
        sequence = sequence + 1
        event.sequence = sequence
        local ok, why = pcall(emit, event)
        if not ok then fail('emit', why) end
    end

    local function onIcon(path, icon)
        local find = api.StaticFindObject or rawget(_G, 'StaticFindObject')
        local indicator = find(path)
        if not valid(indicator) then
            attacks[path] = nil
            if skullSource == path then skullSource = nil end
            return
        end
        local attack = attacks[path]
        -- A hidden indicator's attack is over; its new states are not on screen.
        if not M.visible(indicator) then
            if attack then
                attacks[path] = nil
                send({kind = 'resolve', reason = 'hidden', path = path, indicator = indicator})
            end
            if skullSource == path then
                skullSource = nil
                send({kind = 'unblockable', active = false, path = path, indicator = indicator})
            end
            return
        end
        -- Any other state takes the indicator's skull away first. Observed: 9, then
        -- 0 and the next attack, sometimes in one frame.
        if icon ~= UNBLOCKABLE and skullSource == path then
            skullSource = nil
            send({kind = 'unblockable', active = false, path = path, indicator = indicator})
        end
        local direction, window = M.attackOf(icon)
        if direction then
            if not (attack and attack.direction == direction) then
                attack = {direction = direction}
                attacks[path] = attack
                send({kind = 'arrow', direction = direction, path = path, indicator = indicator})
            end
            if window and not attack.critical then
                attack.critical = true
                send({kind = 'critical', direction = direction, path = path, indicator = indicator})
            end
            return
        end
        if icon == UNBLOCKABLE then
            if skullSource == nil then
                skullSource = path
                send({kind = 'unblockable', active = true, path = path, indicator = indicator})
            end
            return
        end
        -- Defending or a weak spot: nothing is coming from this indicator.
        if attack then
            attacks[path] = nil
            send({kind = 'resolve', reason = 'sword', path = path, indicator = indicator})
        end
    end

    local function deliver(hooked)
        if not self.active then return end
        delivered = delivered + 1
        local ok, why = pcall(function()
            local object, params = hooked.object, hooked.params
            local icon = params and params.IconType
            icon = type(icon) == 'table' and icon.value or icon
            local path = object and object.path
            if type(path) == 'string' and type(icon) == 'number' then onIcon(path, icon) end
        end)
        if not ok then fail('icon', why) end
    end

    local function bridge() return api.UE4SSLuaEventBridge or rawget(_G, 'UE4SSLuaEventBridge') end

    -- Hooks the indicator's icon change. A class not loaded yet leaves the hook
    -- pending; the bridge attaches it when the indicator appears.
    function self:start()
        if self.active then return true end
        local events = bridge()
        local hooks = events and events.Hooks
        local caps = events and type(events.GetCapabilities) == 'function' and events.GetCapabilities() or {}
        if not (hooks and caps.hooks and caps.hooks_bp) then
            if log then
                log.warn('MC_NPCAttackIndicator unavailable: UE4SSLuaEventBridge Blueprint hooks missing',
                    caps.hooks_reason and (' (' .. tostring(caps.hooks_reason) .. ')') or '')
            end
            return false
        end
        local ok, hooked, why = pcall(hooks.Hook, M.ICON,
            {pre = deliver, params = {'IconType'}, object_paths = true})
        if not (ok and hooked) then
            if log then log.warn('MC_NPCAttackIndicator unavailable: ', ok and why or hooked) end
            return false
        end
        handle = hooked
        attacks, skullSource = {}, nil
        delivered = 0
        self.active = true
        if log then log.debug('MC_NPCAttackIndicator hooked') end
        return true
    end

    -- Unhooks and forgets every indicator's attack.
    function self:stop()
        if not self.active then return end
        self.active = false
        if handle then pcall(handle.Unhook, handle) end
        handle = nil
        attacks, skullSource = {}, nil
        if log then
            log.debug('MC_NPCAttackIndicator unhooked after ', delivered, ' icon changes')
            for kind, count in pairs(failures) do
                if count > 1 then log.warn('attack indicator ', kind, ' failed ', count - 1, ' more times') end
            end
        end
        failures = {}
    end

    return self
end

return M
