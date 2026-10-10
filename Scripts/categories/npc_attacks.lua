--    WBP_GameHUD_C
--    └─ WidgetTree.RootWidget
--       ├─ native HUD content
--       └─ cue (per template, full screen, added last)

return {
    name = "npc.attacks",
    -- The cue joins the HUD once the player is in the game and follows the
    -- game's indicator only during combat.
    hooks = { attach = "MCTPlayerReady", wake = "MCTCombatStart", sleep = "MCTCombatEnd" },
    -- Notification templates chain: each template that declares cue receives
    -- its own Overlay, so templates never share or clear each other's layer.
    objects = {
        hud = { source = 'lookup', required = true,
            class = '/Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C' },
        hud_root = { source = 'reference', from = 'hud', member = 'WidgetTree.RootWidget',
            required = true },
        cue = { source = 'create', class = '/Script/UMG.Overlay',
            outer = 'hud_root', parent = 'hud_root', layout = 'fill' },
    },
}
