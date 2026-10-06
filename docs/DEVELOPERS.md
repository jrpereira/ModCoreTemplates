# Developer guide

A provider is your UE4SS mod. It registers templates with MCT; MCT loads each
file in its own Lua state. Start with a managed template so MCT handles property
capture, restoration and settings updates.

## Create a provider

Use the complete [Wheel Nudge example](https://github.com/jrpereira/ModCoreTemplates/tree/main/examples/wheel-nudge) as your
starting point. An enabled provider needs this layout:

```text
WheelNudge/
├── enabled.txt
├── mod.json
└── Scripts/
    ├── main.lua
    └── mc_nudge.lua
```

`mod.json` supplies the module ID, author and version. In `Scripts/main.lua`:

```lua
local MC = require('mc')
MC.registerTemplate('nudge') -- loads sibling mc_nudge.lua at MCT startup
```

Register each template separately before the startup barrier. Late registrations
are rejected; duplicate file registrations are ignored. One invalid template
is skipped without removing other valid templates.

## Declare objects and changes

This complete `mc_nudge.lua` moves the ability wheel by 20 local units:

```lua
local MC = require('mc')
local Widget = MC('widget')
local template = {
    name = 'Small Nudge',
    category = 'player.quickslots',
    objects = {abilities = {properties = {'position'}}},
}

function template.attach(objects, params, original)
    local position = original.abilities.position
    Widget.setTranslation(objects.abilities, position.X + 20, position.Y)
    return original
end

return template
```

The category resolves `abilities` and its dependencies. Only requested objects
appear in `objects`; dependencies are resolved automatically. Declare every
property you change in `properties`, even when using a helper. The supplied
`original` has the same object structure and contains captured values.

For quickslots, select the template under **Controls → Visuals → Quickslots
Visuals**, then Apply. If the slot is unavailable, MCS lists the fallback category
page under ModCore Templates. Selecting None restores the original translation.

## Add settings

Add these fields to the template table above to make the offset configurable:

```lua
settings = {Offset = 20},
menu = {
    {id='Position', label='Position', fields={
        {id='Offset', label='Horizontal offset',
            values={min=-100, max=100, step=1}, default=20},
    }},
},
```

Then replace `position.X + 20` with `position.X + params.settings.Offset`.
Editing a menu row changes only the pending value. Apply commits it; MCT restores
and reruns managed `attach`, preventing offsets from accumulating.
See [Template menus](MENUS.md) for pickers, conditions and variations.

## Callback rules

| Value | Meaning |
| --- | --- |
| `objects` | Requested objects, in the shape of `template.objects` |
| `params.settings` | Category values, then template defaults, then committed overrides |
| `params.screen` | Width, height and reference points for layout |
| `params.state` | Copied shared state, including the latest wheel focus |
| `original` | Captured properties to return for restoration |

Settings are copied; overriding a key replaces its whole value, including a
nested table. `0` and `false` are valid overrides. Screen reference points are
`left=0`, `center=width/2`, `right=width`, `bottom=0`, `middle=height/2`, `top=height`;
account for the target parent's coordinate system.

Use supplied objects during callbacks. For subscriptions, register cleanup with
`params.onCleanup(unsubscribe)`. Cleanup also runs after world teardown, when
the attachment's widgets have been collected: never call a widget kept from an
earlier callback, since UE4SS `IsValid` itself reads the freed object. Keep it
as a weak handle and read it back, which returns nil once it died:

```lua
local Objects = require('mc').load('objects')
local kept = Objects.hold(widget)        -- a supplied or freshly read object
params.onCleanup(function()
    local live = Objects.get(kept)
    if live then Widget.setOpacity(live, opacity) end
end)
``` Prefer declared [event callbacks](MENUS.md#apply-behavior)
when reacting to wheel focus.

Managed templates need only `attach`. With `managed=false`, all three callbacks
are required: `attach(root, params, objects)`, `update(root, params, objects)` and
`detach(root, params, objects)`. Use the [lifecycle reference](LIFECYCLE-DRAFT.md)
before taking ownership of cleanup.

## Helpers and checks

Template helpers share MCT's Lua module search path. Put your own helpers in a
module-specific folder, for example `require('wheelnudge.layout')`, to avoid
name collisions. Use `MC('widget')` for MCT's widget helpers.

Run the [offline tests](BUILD.md), then test selection, repeated Apply, switching
templates and restoration in game. Invalid objects receive no detach callback;
MCT forgets them and runs managed cleanup without accessing dead widgets.
