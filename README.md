# ModCore Templates

The fresh lifecycle design and executable draft are documented in
[Lifecycle draft](docs/LIFECYCLE-DRAFT.md), with copied menu generation and Apply
routing described in [Template menus](docs/MENUS.md). The previous runtime remains available in Git history while this implementation
is being tested in Dawnwalker.

Mod data lives in `Scripts/templates`, `Scripts/categories`, and `Scripts/cache`.
Generated settings and page data use the cache; DMM's `mod_settings.ini` stays at root.

Build modular game-feature and UI customizations as Lua templates. Register
categories, expose settings, and implement `attach`, `update`, and `detach`.
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

Choose a category by the targets it recognizes, then declare only the targets your
template needs in `template.targets`. MCT resolves those targets and their selector
dependencies before calling the template. A category's other targets are not looked
up merely because they exist. Group related targets when order matters, for example
`targets = {buttons = {'ability_left', 'ability_right'}}`; the callback receives the
same structure as `objects.buttons`.

If no category describes the objects you need, define one with its own target
selectors. Put settings shared by its templates in the category's `menu.fields`
(and defaults in `settings`). MCT deep-copies the category settings, then overlays
deep-copied template defaults and committed values by key. Nested tables are copied
too; overriding a key replaces that whole value rather than merging its members.
A template can therefore use a category field directly or override its value with
a template field of the same ID, without changing the category's copy.

### Attach and update

Prefer a managed template (`managed = true`). Define
`attach(objects, params, original)`, where `objects` contains the declared targets
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
again with fresh `params`. If you opt for an unmanaged template, implement
`attach(root, params, objects)`, `update(root, params, objects)`, and
`detach(root, params, objects)` yourself; `update` must reapply the new settings
without accumulating changes from the previous call.

### Share behavior in `main.lua`

When several templates use the same widget operations, load their declarations in
`main.lua`, define the common functions once, then attach the template-specific
callbacks and return the loaded templates. The [example main.lua](examples/wheel-nudge/Scripts/templates/main.lua)
shows that pattern with one template; more templates can reuse the same helper.

Keep each template's target and menu declarations in its own file. MCT loads only
`mc.lua` when present, or `main.lua` for existing modules, so the returned list
determines which templates it registers. Declare the properties changed by shared helpers in each template's
`targets`, allowing MCT to restore them.

## Requirements and installation

Use UE4SS with Lua 5.4, Dawnwalker Mod Menu, ModCoreSettings for the documented
menu presentation, and UE4SSLuaEventBridge API 5 with `lifetimes.captureObject`.
MCT does not require the `object_lifetimes` capability flag at startup. If the
bridge reports that its native lifetime service is unavailable, MCT uses its
earlier map-scoped address and full-name identity so templates can still attach.
This fallback cannot distinguish an object recreated at the same address with
the same name before a map change; native lifetime capture remains preferred.
Other capture failures leave the affected object unattached. Install under
`Mods/_ModCore_Templates` and enable the mod.
Disable the old `_UE4SSTemplatingEngine` installation before starting the game.
The Lua runtime starts on UE4SS's game thread. It discovers installed modules with a `Scripts/templates` folder, loading
each folder's `mc.lua` or `main.lua` when present and otherwise loading its Lua template files.

ModCoreControls owns input separately. Select a visual template without moving
its input bindings into the template; one wheel should not need two steering columns.

## Lifecycle contract

MCT calls `attach` when a selected template's targets are available. Committed
settings changes update the attachment using the callback form described above.
For managed templates, MCT restores declared properties on detach; unmanaged
templates own their detach behavior. Invalid objects are forgotten without a
detach callback.

## Documentation

- [Lifecycle contract](docs/LIFECYCLE-DRAFT.md): current callbacks and registration.
- [Build guide](docs/BUILD.md): source preparation and tests.
- [Changelog](CHANGELOG.md): changes by version.

Live selector resolution and UE4SS lifecycle hooks: [Object source](docs/OBJECT-SOURCE.md).
