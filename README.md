# ModCore Templates

The fresh lifecycle design and executable draft are documented in
[Lifecycle draft](docs/LIFECYCLE-DRAFT.md), with copied menu generation and Apply
routing described in [Template menus](docs/MENUS.md). The previous runtime remains available in Git history while this implementation
is being tested in Dawnwalker.

Mod data lives in `Scripts/categories` and `Scripts/cache`; providers keep their
explicitly registered template entries in their own `Scripts` folders.
Generated settings and page data use the cache; DMM's `mod_settings.ini` stays at root.

Build modular game-feature and UI customizations as Lua templates. Register
categories, expose settings, and implement `attach`.
ModCoreTemplates manages selection and lifecycle; the template supplies behavior.

## Features

- Single-selection or multiple-enabled templates per category.
- Generated category and module settings pages.
- Category-owned object and group selectors with event-driven lifecycle checks.
- Template callbacks receive effective settings: category settings overlaid by template settings.

## Template Best Practices

See the complete [Wheel Nudge example](examples/wheel-nudge/README.md) for a
small working template and its `main.lua` loader.

### Categories and templates

Choose a category by the objects it recognizes, then declare only the objects your
template needs in `template.objects`. MCT resolves those objects and their
dependencies before calling the template. A category's other objects are not looked
up merely because they exist. Group related objects when order matters, for example
`objects = {buttons = {'ability_left', 'ability_right'}}`; the callback receives the
same structure as `objects.buttons`.

Each category object declares a `source`: `lookup` finds a live object by path or
class; `reference` reads a member from another declared object; `create` constructs
a class with the WidgetTree of its declared `outer` as owner. For example,
`actions = {source='create', class='/Script/UMG.CanvasPanel', outer='switcher', parent='hud_root'}`
constructs a CanvasPanel and adds it to the declared `hud_root` before the first
managed `attach`. The visual layout remains the template's responsibility. MCT
reuses the panel across updates and removes it from its parent during cleanup.
A template must include `switcher`, `hud_root`, and `actions` in its `objects`
declaration to use them.

If no category describes the objects you need, define one with its own target
selectors. Put settings shared by its templates in the category's `menu.groups[].fields`
(and defaults in `settings`). MCT deep-copies the category settings, then overlays
deep-copied template defaults and committed values by key. Nested tables are copied
too; overriding a key replaces that whole value rather than merging its members.
A template can therefore use a category field directly or override its value with
a template field of the same ID, without changing the category's copy.

Template menus are ordered arrays of groups. Fields may use a leading-dot relative
ID (`Wheels + .X` becomes `WheelsX`), and `values` may be a numeric range, a
numeric-to-label picker map, or a named domain such as `percent`. Templates declare
variations separately; variation branches belong to whole groups. MCT supplies the
standard Control Layout link automatically. See [Template menus](docs/MENUS.md).

### Attach and update

Templates use managed lifecycle by default. Define
`attach(objects, params, original)`, where `objects` contains the declared objects
and `original` contains the values MCT captured from their declared `properties`.
Return `original` (or the same-shaped original values) so MCT can restore them on
detach. Declare additional properties on a target or target group when the
template changes them.

`params.settings` contains the effective category and template settings.
`params.screen` contains `width` and `height`, plus horizontal reference points
`left = 0`, `center = width / 2`, `right = width`, and vertical reference points
`bottom = 0`, `middle = height / 2`, `top = height`. For example,
`params.screen.right - 20` is 20 units left of the right reference point; account
for the widget parent's coordinate system when applying it.

Use the supplied `objects` rather than searching for widgets in the callback, and
do not retain object references after it returns. MCT checks availability and
handles their lifecycle. A managed template does not need an `update` function:
when committed settings change, MCT restores the saved values and calls `attach`
again with fresh `params`. Set `managed = false` only if the template must own
its lifecycle; then implement
`attach(root, params, objects)`, `update(root, params, objects)`, and
`detach(root, params, objects)` yourself; `update` must reapply the new settings
without accumulating changes from the previous call.

### Register templates

Keep each template's object, menu declaration, and callbacks in its own file. A
provider's UE4SS `Scripts/main.lua` registers each sibling template; MCT does not
scan installed modules:

```lua
local M = require('mc')
M.addTemplate('layout')
```

This registers `mc_layout.lua`; that template declares its own category. MCT loads
it at the startup barrier and discovers the module ID, author, and version from
the provider's `mod.json`. Declare the properties changed by shared helpers in each template's
`objects`, allowing MCT to restore them.

## Requirements and installation

Use UE4SS with Lua 5.4, Dawnwalker Mod Menu, ModCoreSettings for the documented
menu presentation, and UE4SSLuaEventBridge API 5 with `lifetimes.captureObject`.
MCT does not require the `object_lifetimes` capability flag at startup. If the
bridge reports that its native lifetime service is unavailable, MCT uses its
earlier map-scoped address and full-name identity so templates can still attach.
This fallback cannot distinguish an object recreated at the same address with
the same name before a map change; native lifetime capture remains preferred.
Other capture failures leave the affected object unattached. Install under
`Mods/_ModCore_3_Templates` and enable the mod.
Disable the old `_UE4SSTemplatingEngine` installation before starting the game.
The Lua runtime starts on UE4SS's game thread and consumes only explicit provider
registrations made before its startup barrier.

ModCoreControls owns input separately. Select a visual template without moving
its input bindings into the template; one wheel should not need two steering columns.

## Lifecycle contract

MCT calls `attach` when a selected template's objects are available. Committed
settings changes update the attachment using the callback form described above.
For managed templates, MCT restores declared properties on detach; unmanaged
templates own their detach behavior. Invalid objects are forgotten without a
detach callback.

## Documentation

- [Lifecycle contract](docs/LIFECYCLE-DRAFT.md): current callbacks and registration.
- [Build guide](docs/BUILD.md): source preparation and tests.
- [Changelog](CHANGELOG.md): changes by version.

Live selector resolution and UE4SS lifecycle hooks: [Object source](docs/OBJECT-SOURCE.md).
