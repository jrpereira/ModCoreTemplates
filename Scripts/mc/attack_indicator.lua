-- MC_NPCAttackIndicator: the game's combat target indicator as update events.
--
-- The game reuses its indicator widgets and updates them from C++, which UE4SS
-- hooks never see. The indicator styles the attacked arrow and its centre icon
-- through one native Image call, so that call names the attack's direction and
-- state. Every atlas image passes through it, so it is hooked only while a
-- template listens (MCT starts and stops this source), and each call is
-- filtered by widget name before any other read.
--
-- Events are emitted inside the game's call, in the frame the game shows the
-- change, as tables with kind and:
--   arrow        direction, path, indicator, late: an attack shows on an indicator
--   critical     direction, path, indicator: that attack turned critical
--   resolve      path, reason ('sword', 'dark' or 'hidden'), direction when dark: an
--                indicator's attack ended
--   unblockable  path, indicator, active: the unblockable skull showed (true) or went
--   early        direction or nil, unblockable, attacker or nil: the game's early
--                warning, 0.1-0.9 s before some attacks' arrows light
-- direction follows ARROWS: 1 top, 2 bottom, 3 left, 4 right. indicator and
-- attacker are live objects, valid only during the call; path names the
-- indicator for later calls.
local Objects = require('mc.objects')

local M = {}
M.ARROWS = {'TopArrow', 'BottomArrow', 'LeftArrow', 'RightArrow'}
M.STYLING = '/Script/UMG.Image:SetBrushFromAtlasInterface'
M.EARLY = '/Script/Dawnwalker.DawnwalkerPlayerCharacter:ShowHelperAttackIndicator'
-- The early warning's 1-4 as ARROWS indices.
local EARLY_DIRECTIONS = {[1]=4, [2]=3, [3]=1, [4]=2}
-- Native arrows at or below this colour strength are the inactive state.
local INACTIVE = 0.5
local FRAME_MS = 16
local ARROW_INDEX = {}
for index, key in ipairs(M.ARROWS) do ARROW_INDEX[key] = index end

local function call(object, method, ...) return Objects.call(object, method, ...) end
local valid = Objects.valid

-- An object's full path without its class.
function M.path(object)
    local name = valid(object) and call(object, 'GetFullName')
    if type(name) ~= 'string' then return nil end
    return name:match('^%S+ (.+)$') or name
end

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

function M.visible(widget) return valid(widget) and visibleChain(widget) end

-- A native arrow the game currently shows as attacking: brightly coloured and
-- visible. The colour is read first: it is the cheaper test.
function M.lit(image)
    if not valid(image) then return false end
    local color = image.ColorAndOpacity
    if not color then return false end
    local strength = math.max(color.R or 0, color.G or 0, color.B or 0) * (color.A or 0)
    return strength > INACTIVE and visibleChain(image)
end

-- The combat target indicator whose WidgetTree holds an image.
function M.indicatorOf(image)
    local tree = valid(image) and call(image, 'GetOuter')
    local indicator = valid(tree) and call(tree, 'GetOuter')
    local name = valid(indicator) and call(indicator, 'GetFullName')
    if type(name) == 'string' and name:find('CombatTargetIndicator', 1, true) then return indicator end
end

function M.arrowOf(indicator, index)
    local image = indicator[M.ARROWS[index]]
    return valid(image) and image or nil
end

-- The names the hook looks for, by FName comparison index: comparing numbers
-- spares a string per styling call. The index ignores an FName's number, so
-- TopArrow_1 reads as TopArrow; the indicator around it is still checked.
local KNOWN = {'Reticle', 'TopArrow', 'BottomArrow', 'LeftArrow', 'RightArrow'}
local known
local function knownName(object)
    if not known then
        known = {}
        for _, name in ipairs(KNOWN) do known[FName(name):GetComparisonIndex()] = name end
    end
    return known[object:GetFName():GetComparisonIndex()]
end

-- api: RegisterHook, UnregisterHook, ExecuteInGameThread, ExecuteWithDelay and,
-- when the engine tick is hooked, ExecuteInGameThreadAfterFrames. emit(event)
-- delivers an event; log is a leveled logger or nil.
function M.new(api, emit, log)
    assert(type(emit) == 'function', 'emit required')
    local self = {active = false}
    -- Per indicator path, the attack it shows: {direction, critical}.
    local attacks = {}
    -- The indicator showing the unblockable skull, if any.
    local skullSource
    -- Indicators whose arrow was styled before it lit, checked next frame.
    local pending, scheduled = {}, false
    local hook, earlyHook
    local styled, handled, sequence = 0, 0, 0
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

    local function later(milliseconds, callback)
        if milliseconds <= FRAME_MS and rawget(_G, 'EngineTickAvailable') == true
            and type(api.ExecuteInGameThreadAfterFrames) == 'function' then
            api.ExecuteInGameThreadAfterFrames(1, callback)
        else
            api.ExecuteWithDelay(milliseconds, function() api.ExecuteInGameThread(callback) end)
        end
    end

    -- Next frame, each indicator that styled an arrow not lit at the time: an
    -- arrow lit now that is not its attack's is an attack. This never turns an
    -- arrow critical or out.
    local function recheck()
        scheduled = false
        if not self.active then pending = {} return end
        local paths = pending
        pending = {}
        for path in pairs(paths) do
            local ok, why = pcall(function()
                local indicator = StaticFindObject(path)
                if not (valid(indicator) and M.visible(indicator)) then return end
                local attack = attacks[path]
                for direction = 1, #M.ARROWS do
                    if not (attack and attack.direction == direction) and M.lit(M.arrowOf(indicator, direction)) then
                        attacks[path] = {direction = direction}
                        send({kind = 'arrow', direction = direction, path = path, indicator = indicator, late = true})
                        return
                    end
                end
            end)
            if not ok then fail('late arrow', why) end
        end
    end
    local function schedule(path)
        pending[path] = true
        if scheduled then return end
        scheduled = true
        local ok, why = pcall(later, FRAME_MS, recheck)
        if not ok then scheduled = false; pending = {}; fail('schedule', why) end
    end

    -- The centre icon, before the call, from the sprite argument: the sword
    -- means no attack is pending, SkullRed an unblockable attack. The game
    -- updates hidden twin indicators too: a hidden indicator's skull is not on
    -- screen, and only the indicator that showed it takes it away.
    local function onCentre(image, sprite)
        local indicator = M.indicatorOf(image)
        if not indicator then return end
        local path = M.path(indicator)
        sprite = sprite or ''
        local visible = M.visible(indicator)
        local sword = sprite:find('Sword', 1, true) ~= nil
        local resolved = sword and attacks[path] ~= nil
        if visible or skullSource == path then
            local skull = visible and sprite:find('SkullRed', 1, true) ~= nil
            if skull then
                local fresh = skullSource == nil
                skullSource = path
                if fresh then send({kind = 'unblockable', active = true, path = path, indicator = indicator}) end
            elseif skullSource ~= nil then
                skullSource = nil
                resolved = resolved or sword
                send({kind = 'unblockable', active = false, path = path, indicator = indicator})
            end
        end
        if resolved then
            attacks[path] = nil
            send({kind = 'resolve', reason = 'sword', path = path, indicator = indicator})
        end
    end

    -- An indicator arrow, after the call, once its brush and colour are set:
    -- lit for an attack, dark when the game turns it off. Nothing the hook can
    -- read tells a first styling from the critical one, so the second styling
    -- of an indicator's attack arrow is the critical one.
    local function onArrow(image, direction)
        local indicator = M.indicatorOf(image)
        if not indicator then return end
        local path = M.path(indicator)
        local attack = attacks[path]
        -- An arrow's parents end inside its indicator's own tree, so the
        -- indicator's visibility is checked by itself. Hidden, its attack is over.
        if not M.visible(indicator) then
            if attack then
                attacks[path] = nil
                send({kind = 'resolve', reason = 'hidden', path = path, indicator = indicator})
            end
            return
        end
        if M.lit(image) then
            if attack and attack.direction == direction then
                if attack.critical then return end
                attack.critical = true
                send({kind = 'critical', direction = direction, path = path, indicator = indicator})
            else
                attacks[path] = {direction = direction}
                send({kind = 'arrow', direction = direction, path = path, indicator = indicator, late = false})
            end
            return
        end
        if attack and attack.direction == direction then
            attacks[path] = nil
            send({kind = 'resolve', reason = 'dark', direction = direction, path = path, indicator = indicator})
        end
        schedule(path)
    end

    -- Hoisted so a styling call builds no closure.
    local function spriteName(sprite) return sprite:get():GetFName():ToString() end
    local function centreCall(context, sprite)
        styled = styled + 1
        local object = context:get()
        if knownName(object) ~= 'Reticle' then return end
        handled = handled + 1
        local read, name = pcall(spriteName, sprite)
        onCentre(object, read and name or nil)
    end
    local function arrowCall(context)
        local object = context:get()
        local direction = ARROW_INDEX[knownName(object)]
        if not direction then return end
        handled = handled + 1
        onArrow(object, direction)
    end
    -- A fault inside the game's call is logged once per kind and never escapes.
    local function before(context, sprite)
        if not self.active then return end
        local ok, why = pcall(centreCall, context, sprite)
        if not ok then fail('centre icon', why) end
    end
    local function after(context)
        if not self.active then return end
        local ok, why = pcall(arrowCall, context)
        if not ok then fail('arrow', why) end
    end

    local function onEarly(_, data)
        if not self.active then return end
        local ok, why = pcall(function()
            local attack = data:get()
            local attacker
            local component = attack.Instigator
            if valid(component) then attacker = call(component, 'GetOwner') end
            send({kind = 'early', direction = EARLY_DIRECTIONS[tonumber(attack.Direction)],
                unblockable = attack.bIsUnblockable == true,
                attacker = valid(attacker) and attacker or nil})
        end)
        if not ok then fail('early warning', why) end
    end

    -- Hooks the styling call and the early warning; the early warning is a
    -- bonus, so the styling call alone is enough to start.
    function self:start()
        if self.active then return true end
        local ok, pre, post = pcall(api.RegisterHook, M.STYLING, before, after)
        if not (ok and type(pre) == 'number' and type(post) == 'number') then
            if log then log.warn('MC_NPCAttackIndicator unavailable: ', ok and 'no hook id' or pre) end
            return false
        end
        hook = {pre, post}
        local early, earlyPre, earlyPost = pcall(api.RegisterHook, M.EARLY, onEarly)
        if early and type(earlyPre) == 'number' then
            earlyHook = {earlyPre, earlyPost}
        elseif log then
            log.warn('MC_NPCAttackIndicator early warning unavailable: ', early and 'no hook id' or earlyPre)
        end
        attacks, skullSource, pending = {}, nil, {}
        styled, handled = 0, 0
        self.active = true
        if log then log.debug('MC_NPCAttackIndicator hooked') end
        return true
    end

    -- Unhooks and forgets every indicator's attack.
    function self:stop()
        if not self.active then return end
        self.active = false
        if earlyHook then pcall(api.UnregisterHook, M.EARLY, earlyHook[1], earlyHook[2]) end
        if hook then pcall(api.UnregisterHook, M.STYLING, hook[1], hook[2]) end
        hook, earlyHook = nil, nil
        attacks, skullSource, pending = {}, nil, {}
        if log then
            log.debug('MC_NPCAttackIndicator unhooked after ', styled, ' styling calls, ', handled,
                ' of them the indicator\'s')
            for kind, count in pairs(failures) do
                if count > 1 then log.warn('attack indicator ', kind, ' failed ', count - 1, ' more times') end
            end
        end
        failures = {}
    end

    return self
end

return M
