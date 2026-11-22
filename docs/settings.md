# Settings

## Why there is no mod_settings.ini

A `mod_settings.ini` is a hand-written manifest for Dawnwalker Mod Menu (DMM): one file
that declares a mod's settings up front. MCT cannot ship one because it has no settings
of its own to declare. Its settings come from whichever templates and categories are
installed, and they change whenever a provider mod is added or removed.

Instead, ModCore Settings (MCS) shows MCT's pages, built from the installed templates.
Values are saved in `config.ini` files. A leftover `mod_settings.ini` is ignored.

## Where values are stored

| File | Holds |
|---|---|
| `Scripts/cache/config.ini` (MCT root) | Each category's template picks and shared fields, whichever page shows them |
| `<Provider>/config.ini` (the template's module root) | Each template's Enabled toggle and settings, on module, category and slot pages alike |

In MCT's config the active templates are saved under `[Templates]`, one key per
category (`<Category>Priority<n>` for a picker per priority), and a category's shared
fields, where it declares any, in its section, `[<category>]`. In a provider's config
each template's settings go in a section of their own, `[<Module>.<Template>]`, under
their own names:

```ini
; 3_ModCore_Templates/Scripts/cache/config.ini
[Templates]
PlayerQuickslots=Fangdango_SingleUnderbar

; 9_ModCore_Preymonition/config.ini
[Preymonition.Omens]
Enabled=1
ParryStyle=chevron
ParrySize=30|80
```

`<Module>` is the module id ModCoreSettings gives for the template's mod folder, and
`<Template>` the template's declared `id`. A key is the setting's name as the template
declares it (a relative field id joined to its group: `Parry` + `.Style` is
`ParryStyle`); a template's on/off toggle is `Enabled`. Templates declare nothing for
this.

Keep all of these when updating. Unknown or retired keys are ignored. Invalid saved
values fall back to the defaults and never block startup.

## Settings

MCT adds these rows. Every id is derived from the category, module and template and
is prefixed `MCT_`. These are the menu ids; the
config saves each row under its section and name, as above. A template's rows are named
`MCT_<Module>_<Id>_...`: `<Module>` is the module id ModCoreSettings gives for the
template's mod folder (its `mod.json` `id`, else the folder name) and `<Id>` the
template's declared `id`.

### Template picker

One per category that has templates with `uniqueBy = 'category'`, and one per priority
for templates with `uniqueBy = 'priority'`. Only one template in each picker can be active.

- **Template** (`MCT_Template`): which template is active for `player.quickslots`.
  Choose **None** to restore the original game state. It appears on the Controls
  tab of the ModCore Settings page, as the Quickslots heading, not on an MCT page.
- **`<Category>` Template** (`MCT_<Category>Template`, such as `MCT_PlayerRadialTemplate`):
  the same choice for category-unique templates in other categories, such as
  `player.radial`, `player.compass`, `player.charges`, `player.self` and `player.stats`.
  Each choice notes the module folder that supplies the template.
- **`<Category>` (priority `<n>`)** (`MCT_<Category>Priority<n>Template`, such as
  `MCT_NpcAttacksPriority10Template`): which of the priority-unique templates with
  priority `<n>` is active in that category.

### Template enabled toggle

One per template without `uniqueBy` (such as the `npc.attacks` templates).

- **`<Label>`** (`MCT_<Module>_<Id>_Enabled`): an on/off switch (Disabled or
  Enabled) that stands in for the template's heading, with the template's settings indented beneath it. A template that is not enabled stays in the menu but receives no lifecycle
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
- **Range** (`type='range'`): `{min=, max=, step=, suffix=, delta=}` with
  `default={low, high}`: a low and a high value on one track (ModCore Settings' range row).
  `min`/`max` may be `{low marker's, high marker's}` pairs; `delta` bounds `high-low`.
  Saved as `<low>|<high>`; the template reads `{low, high}`. Not in category settings or
  slot categories.
- **Picker**: a map of numbers to labels, optionally `{label=, note=, sound=}` per choice.
  `widget` shows it as `picker` (default), `tabs` (up to 8), `cycler` or `switch`.
- **Keyed picker**: a list of `{key=, label=, note=, sound=}` choices, saved and delivered
  to the template as the key (`settings.Style == 'fiend'`), so adding or reordering choices
  never moves a saved one. It may also hold `{from='choices/x.lua'}` entries: a list file in
  the module's `Scripts/` whose choices are put in that place every time the menu opens, so files added to the mod while the game runs appear the next time. A listed
  picker accepts any well-formed saved key, and the template gets it even when its file is
  gone: fall back for a key you can't serve. See [MENUS.md](MENUS.md#listed-choices).

Conditions (`visible`, `label`, `dim`) change how a row is shown, not what is saved or
delivered to the template.

The example [Wheel Nudge](../examples/wheel-nudge/README.md) declares:

- **Horizontal offset** (`HorizontalPercent`): -25..25 %, default 0. Shifts the
  ability wheel by that share of the screen width.
- **Vertical offset** (`VerticalPercent`): -25..25 %, default 0. Shifts it by
  that share of the screen height.

### Templates tab

ModCore Settings' Templates tab lists every installed template, grouped by module and
category, with the active ones marked **Active**. These rows are read-only and save
nothing.

### Merged notice

When all of a module's templates have moved to a slot on another page, the module
page starts with a notice linking to the slot (such as Controls), and then
lists the module's own settings in that slot, editable there too and saved where the
slot saves them. The notice itself is navigation and saves nothing.

## Logging

The default level is WARN. For more detail, install the UE4SS Lua Log Bridge and raise
ModCoreTemplates' level on its Logs page, or set `ModCoreTemplates=DEBUG` under
`[Levels]` in the bridge's `config.ini`. Messages appear in `UE4SS.log`.

See [Template menus](MENUS.md) for how fields are declared and placed.
