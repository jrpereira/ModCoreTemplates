# Settings

## Why there is no mod_settings.ini

A `mod_settings.ini` is a hand-written manifest for Dawnwalker Mod Menu (DMM): one file
that declares a mod's settings up front. MCT cannot ship one because it has no settings
of its own to declare. Its settings come from whichever templates and categories are
installed, and they change whenever a provider mod is added or removed.

Instead, MCT describes its pages as menu data after the templates load and publishes
them through ModCoreSettings (MCS), which builds the pages. MCT writes nothing at the
mod root and never writes DMM manifests. Values are saved in `config.ini` files, not in
a manifest. Leftover `mod_settings.ini` files from older builds are ignored.

## Where values are stored

| File | Holds |
|---|---|
| `Scripts/cache/config.ini` (MCT root) | Category selections, shared category fields and the settings of templates on category or slot pages |
| `<Provider>/config.ini` (the template's module root) | Settings of templates whose page is the module page (the default) |
| `Scripts/cache/identity-catalog.lua` | Numbered setting ids, so saved values survive regeneration |
| `log_level.txt` (MCT root) | Optional log level |

Keep all of these when updating. Unknown or retired keys are ignored. Invalid saved
values fall back to the defaults and never block startup.

## Settings

MCT generates these rows. Setting ids are prefixed `MCT_`; readable ids are kept where
listed, and the rest are numbered (`MCT_<n>`) through the identity catalog.

### Template picker

One per category with `single = true` (only one template can be active).

- **Template** (`MCT_Template`): which template is active for `player.quickslots`.
  Choose **None** to restore the original game state. It appears in ModCore Controls'
  Visuals section, not on an MCT page.
- **`<Category>` Template** (`MCT_<Category>Template`, such as `MCT_PlayerRadialTemplate`):
  the same choice for the other single categories: `player.radial`, `player.compass`,
  `player.charges`, `player.self` and `player.stats`. Each choice notes the module
  folder that supplies the template.

### Template enabled toggle

One per template in a category that is not `single` (such as `npc.attacks`).

- **Enabled** (`MCT_<TemplateName>_Enabled`): No or Yes, under a heading naming the
  template. A template that is not enabled stays in the menu but receives no lifecycle
  callbacks.

### Shared category fields

Declared in a category's `menu.groups[].fields`. They apply to every template in that
category and show while a template is selected. A template's own value with the same
key overrides the shared one. The default categories shipped with MCT declare none.

### Template fields

Declared by each template's `menu` and stored under the template's module. A relative field id
(leading dot) is joined to its group id (`Layout` + `.Size` becomes `LayoutSize`); an
absolute one is used as written. A template
with `variations` also gets one picker per variation, named by the title-cased
variation id (`style` becomes `Style`).

Field types are inferred from `values`:

- **Integer**: `{min=, max=, step=, suffix=}`, or `'percent'` for 0..100 with a `%` suffix.
- **Picker**: a map of numbers to labels, optionally `{label=, note=, sound=}` per choice.
  Up to 8 choices can show as tabs with `tab=true`.

Conditions (`visible`, `label`, `dim`) change how a row is shown, not what is saved or
delivered to the template.

The example [Wheel Nudge](../examples/wheel-nudge/README.md) declares:

- **Horizontal offset** (`HorizontalPercent`): -25..25 %, default 0. Shifts the
  ability wheel by that share of the screen width.
- **Vertical offset** (`VerticalPercent`): -25..25 %, default 0. Shifts it by
  that share of the screen height.

### Templates tab

ModCore Settings' Templates tab lists every installed template, grouped by module and
category, with the active ones marked **Active**. These rows (`MCT_Listed_<n>`) are
read-only and save nothing.

### Merged notice

When all of a module's templates have moved to a slot on another page,
the module page shows only `MCT_MergedNotice`: a link to the slot, such as Controls.
It is navigation and saves nothing.

## Logging

The default level is WARN. For more detail, put a level (`trace`, `debug`, `info`,
`warn`, `error` or `critical`) in `log_level.txt` at the MCT root and restart. Messages
appear in `UE4SS.log`.

See [Template menus](MENUS.md) for how fields are declared and placed.
