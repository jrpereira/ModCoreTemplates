# Wheel Nudge example

This complete MCT module moves the ability wheel by a percentage of the screen
width and height. It uses the existing `player.quickslots` category.

It requires a working ModCore Templates installation and its menu integration.

Place this example's `Scripts` folder under an installed module, for example
`Mods/WheelNudge/Scripts`. UE4SS loads `Scripts/main.lua`, which registers
[mc_nudge.lua](Scripts/mc_nudge.lua) with MCT through `M.registerTemplate('nudge')`.
The example `mod.json` supplies its module ID, author, and version; the template
itself declares `category='player.quickslots'`.
Select **Wheel Nudge** under `player.quickslots` in the menu.

Apply that selection, then open the **WheelNudge** module settings page. Both
offsets default to zero, so the wheel stays in place until you change them and
apply the settings. For example, a horizontal offset of `10` adds 192 units to
the original horizontal translation when `params.screen.width` is 1920.
Offsets use the widget's local render translation; parent scaling can affect
the visible distance. Select no template (or another layout) to restore the
original position.

The category resolves `abilities` through its switcher and already declares its
`position` property for restoration. The template requests only `abilities`; it
does not search for or retain widgets. MCT deep-copies category settings before
overlaying this template's values. On a committed setting change, MCT restores
the saved position and calls `attach` again. On detach, it restores the position.

The full declaration and callback are in [mc_nudge.lua](Scripts/mc_nudge.lua).

Managed attachments that subscribe to events register an unsubscribe callback with
`params.onCleanup(unsubscribe)`. MCT runs cleanup before restoration on update,
detach, and failed attachment, and also when forgetting invalid objects or resetting
the manager. Cleanup must be safe after world teardown. Guard queued callbacks with
an attachment-local active flag, clear that flag in cleanup, and resolve objects
when handling events rather than retaining widget references in subscriptions.
