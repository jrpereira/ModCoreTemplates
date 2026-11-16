--    WBP_GameHUD_C
--    └─ WidgetTree.RootWidget
--       ├─ native HUD content
--       └─ cue (per template, full screen, added last)

return {
    id = "npc.attacks",
    -- The cue joins the HUD once the player is in the game and follows the
    -- game's indicator only during combat, through MC_NPCAttackIndicator.
    hooks = { attach = "MC_PlayerReady", wake = "MC_CombatStart", sleep = "MC_CombatEnd",
        update = "MC_NPCAttackIndicator" },
    -- Notification templates chain: each template that declares cue receives
    -- its own Overlay, so templates never share or clear each other's layer.
    -- A module page's live preview (mc/preview.lua) loops four attacks, from each side,
    -- ahead and behind, each first seen, then in its parry window, then resolved, and one
    -- unblockable attack. Times in milliseconds from the loop's start.
    preview = { length = 9400, events = (function()
        local events, at = {}, 0
        for attack, direction in ipairs({3, 4, 1, 2}) do
            events[#events + 1] = {at = at, attack = attack, event = {kind = 'arrow', direction = direction}}
            events[#events + 1] = {at = at + 700, attack = attack, event = {kind = 'critical', direction = direction}}
            events[#events + 1] = {at = at + 1200, attack = attack, event = {kind = 'resolve', reason = 'sword'}}
            at = at + 1600
        end
        events[#events + 1] = {at = at, attack = 5, event = {kind = 'unblockable', active = true}}
        events[#events + 1] = {at = at + 2000, attack = 5, event = {kind = 'unblockable', active = false}}
        return events
    end)() },
    objects = {
        hud = { source = 'lookup', required = true,
            class = '/Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C' },
        hud_root = { source = 'reference', from = 'hud', member = 'WidgetTree.RootWidget',
            required = true },
        cue = { source = 'create', class = '/Script/UMG.Overlay',
            outer = 'hud_root', parent = 'hud_root', layout = 'fill' },
    },
}
