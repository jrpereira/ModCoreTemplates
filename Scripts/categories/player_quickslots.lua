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
    objects = {
        switcher = { source = 'lookup', object = "WidgetSwitcher /Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C:WidgetTree.QuickslotsSwitcher", required = true,
            properties = {'activeIndex'} },
        hud_root = { source = 'reference', from = 'switcher', member = '@owner.WidgetTree.RootWidget' },
        actions = { source = 'create', class = '/Script/UMG.CanvasPanel', outer = 'switcher', parent = 'hud_root' },
        -- Resolve through the owning HUD, so a layout can move a wheel out of
        -- the switcher without losing its category target.
        abilities = { source = 'reference', from = 'switcher', member = '@owner.WBP_AA_Quickslots', class = 'WBP_AA_Quickslots_C',
            properties = {'parent','order','slot','position','size'} },
        consumables = { source = 'reference', from = 'switcher', member = '@owner.WBP_HUD_Quickslots', class = 'WBP_HUD_Quickslots_C',
            properties = {'parent','order','slot','position','size'} },

        ability_box = { source = 'reference', from = 'abilities', member = 'WidgetTree.RootWidget' },
        consumable_box = { source = 'reference', from = 'consumables', member = 'WidgetTree.RootWidget' },
        ability_panel = { source = 'lookup', from = 'ability_box', class = 'Overlay' },
        consumable_panel = { source = 'lookup', from = 'consumable_box', class = 'Overlay' },

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
