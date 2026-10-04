--    QuickslotsSwitcher
--    ├─ WBP_HUD_Quickslots
--    │  └─ SizeBox → Overlay
--    │     ├─ cross
--    │     ├─ Left, Top, Right, Bottom buttons
--    │     └─ WBP_HUD_Quickslots_Bindings
--    └─ WBP_AA_Quickslots
--       └─ SizeBox → Overlay
--          ├─ Darken, Glow
--          └─ cross, Left, Top, Right, Bottom buttons,
--             WBP_AA_Quickslots_Bindings


local category = {
    name = "player.quickslots",
    single = true,
    -- MCT moves both wheels into its canvas and restores the native hierarchy
    -- when no quickslot template is selected. The baits keep the wheels'
    -- switcher slots as compatibility placeholders for native selection calls.
    -- Created objects cannot declare required; sharedObjects makes their
    -- successful creation a prerequisite for every enabled quickslot template.
    sharedObjects = {'actions','bait1','bait2'},
    objects = {
        switcher = {  object = "WidgetSwitcher /Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C:WidgetTree.QuickslotsSwitcher", source = 'lookup',
            required = true },
        hud_root = { member = '@owner.WidgetTree.RootWidget',
            required = true, source = 'reference', from = 'switcher' },
        actions = { class = '/Script/UMG.CanvasPanel', source = 'create',
            outer = 'switcher', parent = 'hud_root', layout = 'fill', prepass = true },
        bait1 = { source = 'create', class = '/Script/UMG.Overlay', outer = 'switcher', parent = 'switcher',
            opacity = 0, reparent = 'abilities', destination = 'actions', reparentLayout = 'canvas' },
        bait2 = { source = 'create', class = '/Script/UMG.Overlay', outer = 'switcher', parent = 'switcher',
            opacity = 0, reparent = 'consumables', destination = 'actions', reparentLayout = 'canvas' },

        -- Resolve through the owning HUD so the baits can move both wheels
        -- without losing their category targets.
        abilities = { from = 'switcher', member = '@owner.WBP_AA_Quickslots', class = 'WBP_AA_Quickslots_C', source = 'reference' },
        consumables = { from = 'switcher', member = '@owner.WBP_HUD_Quickslots', class = 'WBP_HUD_Quickslots_C', source = 'reference' },
        change_prompt = { source = 'reference', from = 'switcher',
            member = '@owner.WBP_HUD_Quickslots_ChangePrompt' },

        -- Native SizeBoxes anchor the direct-child Overlay lookups used by Bar.
        ability_box = { source = 'reference', from = 'abilities', member = 'WidgetTree.RootWidget' },
        consumable_box = { source = 'reference', from = 'consumables', member = 'WidgetTree.RootWidget' },
        ability_panel = { source = 'lookup', from = 'ability_box', class = 'Overlay' },
        consumable_panel = { source = 'lookup', from = 'consumable_box', class = 'Overlay' },
        ability_cross = { source = 'reference', from = 'abilities', member = 'cross' },
        ability_darken = { source = 'reference', from = 'abilities', member = 'Darken' },
        ability_glow = { source = 'reference', from = 'abilities', member = 'Glow' },
        consumable_cross = { source = 'reference', from = 'consumables', member = 'cross' },

        ability_button_left = { source = 'reference', from = 'abilities', member = 'Left' },
        ability_button_top = { source = 'reference', from = 'abilities', member = 'Top' },
        ability_button_right = { source = 'reference', from = 'abilities', member = 'Right' },
        ability_button_bottom = { source = 'reference', from = 'abilities', member = 'Bottom' },
        consumable_button_left = { source = 'reference', from = 'consumables', member = 'Left' },
        consumable_button_top = { source = 'reference', from = 'consumables', member = 'Top' },
        consumable_button_right = { source = 'reference', from = 'consumables', member = 'Right' },
        consumable_button_bottom = { source = 'reference', from = 'consumables', member = 'Bottom' },

        ability_left = { source = 'reference', from = 'abilities', member = 'WBP_AA_Quickslots_Bindings.Left' },
        ability_top = { source = 'reference', from = 'abilities', member = 'WBP_AA_Quickslots_Bindings.Top' },
        ability_right = { source = 'reference', from = 'abilities', member = 'WBP_AA_Quickslots_Bindings.Right' },
        ability_bottom = { source = 'reference', from = 'abilities', member = 'WBP_AA_Quickslots_Bindings.Bottom' },
        consumable_left = { source = 'reference', from = 'consumables', member = 'WBP_HUD_Quickslots_Bindings.Left' },
        consumable_top = { source = 'reference', from = 'consumables', member = 'WBP_HUD_Quickslots_Bindings.Top' },
        consumable_right = { source = 'reference', from = 'consumables', member = 'WBP_HUD_Quickslots_Bindings.Right' },
        consumable_bottom = { source = 'reference', from = 'consumables', member = 'WBP_HUD_Quickslots_Bindings.Bottom' },
    },

}

return category
