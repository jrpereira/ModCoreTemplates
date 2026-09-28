return {
    name = "player.radial",
    single = true,
    objects = {
        radial = { source = 'lookup', class = '/Game/_Dawnwalker/UI/_Unified/HUD/CombatFocus/WBP_Combat_Focus_QuickslotBindingsRadial.WBP_Combat_Focus_QuickslotBindingsRadial_C', attach = false },
        radial_left = { source = 'reference', from = 'radial', member = 'Left.Button' },
        radial_top = { source = 'reference', from = 'radial', member = 'Top.Button' },
        radial_right = { source = 'reference', from = 'radial', member = 'Right.Button' },
        radial_bottom = { source = 'reference', from = 'radial', member = 'Bottom.Button' },
    },
}
