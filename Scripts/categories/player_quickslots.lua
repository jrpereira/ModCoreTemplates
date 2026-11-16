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
    id = "player.quickslots",
    -- A loading save creates the HUD with empty wheels and fills them a moment
    -- later, while the loading screen still covers it. Attach once the HUD has
    -- been quiet for two seconds.
    attachDelay = 2000,
    -- Templates receive control events once the player is in the game.
    hooks = { wake = "MC_PlayerReady" },
    -- The Template picker and the selected template's settings appear in
    -- ModCore Controls' Visuals section instead of an MCT or module page.
    slot = { provider = 'controls', slot = 'visuals' },
    -- MCT moves both wheels into its canvas and restores the native hierarchy
    -- when no quickslot template is selected. The game's own state picks the
    -- active wheel wherever the wheels sit, so nothing stays in the switcher.
    -- Created objects cannot declare required; sharedObjects makes their
    -- successful creation a prerequisite for every enabled quickslot template.
    sharedObjects = {'actions'},
    -- Every pass that may move, show or hide the key indicators publishes
    -- templates.layout.changed, so ModCore Controls re-copies their layout.
    layoutEvent = true,
    -- A module page's live preview borrows the game's own wheels (mc/preview.lua, the
    -- runtime's lend): the actions canvas moves whole, with the wheels it adopted, into the
    -- preview while it is open, with the page's template attached to the wheels, and
    -- returns to its place in the HUD when it closes. Its loop focuses each wheel in turn, 2 s each, as ModCore Controls
    -- reports it, and once a loop gives the consumable Top slot a Global key while the
    -- abilities have focus, then clears it.
    -- Times in milliseconds from the loop's start.
    -- Without a game to lend from (the main menu), the preview shows unavailable.
    preview = { lend = true, unavailable = 'Load a game to preview your Quickslots', length = 8000, events = (function()
        local function focus(at, from, to)
            return {at = at, event = {name = 'controls.group.focus', group = {from = from, to = to}}}
        end
        local function global(at, slot)
            local rows = {{false, false, false, false}, {false, false, false, false}}
            if slot then rows[2][slot] = true end
            return {at = at, event = {name = 'controls.slots.global', global = rows}}
        end
        return {focus(0, 2, 1), focus(2000, 1, 2), focus(4000, 2, 1), global(4000, 2),
            focus(6000, 1, 2), global(6000, nil)}
    end)() },
    objects = {
        switcher = {  object = "WidgetSwitcher /Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C:WidgetTree.QuickslotsSwitcher", source = 'lookup',
            required = true },
        hud_root = { member = '@owner.WidgetTree.RootWidget',
            required = true, source = 'reference', from = 'switcher' },
        actions = { class = '/Script/UMG.CanvasPanel', source = 'create',
            outer = 'switcher', parent = 'hud_root', layout = 'fill', prepass = true,
            adopt = {'abilities','consumables'}, adoptLayout = 'canvas' },

        -- Resolve through the owning HUD so moving both wheels keeps their
        -- category targets.
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
