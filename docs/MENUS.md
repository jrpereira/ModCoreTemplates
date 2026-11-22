# Template menus

MCT generates menus after registered templates load, before attaching objects.
Start with the [developer guide](DEVELOPERS.md) for a complete template. Examples
below focus on menu declarations; callbacks must still declare their targets.

## Where settings are saved

MCT builds its settings pages from your declarations and shows them through ModCore
Settings. Where a value is saved depends on the row, not the page that shows it:

| File | Holds |
|---|---|
| `3_ModCore_Templates/Scripts/cache/config.ini` | Each category's template picks and shared fields |
| `<YourProvider>/config.ini` | Each template's Enabled toggle and settings, on every page that shows them |

Both hold player settings and are kept on update. See [settings.md](settings.md) for
the sections and keys.

## Where pages appear

- **ModCore Templates:** category selectors, template toggles and shared category settings.
  When it has nothing of its own to show, its entry links to ModCore Settings'
  Templates tab instead.
- **Category page:** fields for templates explicitly targeting `templates`, listed under
  ModCore Templates.
- **Module page:** the default location for template fields. The module is the mod
  folder that registers the template. ModCore Settings shows the page as that module,
  with the name, author, version and icon from its `mod.json`, and lists it as a ModCore
  module when its `mod.json` group is `ModCore`. A module with settings of its own keeps
  its entry, and the page follows it.

Set `menuTarget='templates'` on a template only when its fields belong on the
category page rather than its module page.

- **Slot:** a category may name a slot on another provider's page:

  ```lua
  slot = { provider = 'controls', slot = 'visuals' },
  ```

  `provider` is the full provider id, or the lowercase short name of a `ModCore<Name>`
  provider. The category's Template picker, Enabled toggles, shared fields and every
  template's fields then appear in that slot instead of on aggregate, category or
  module pages. The Template picker and Enabled toggles always show; other rows show
  while their template, or their variation value, is selected. The picker, labelled
  with the category (`Quickslots`), heads the section, and the selected template's
  settings follow under it.

  A module whose templates all moved to slots keeps its page in the module group, over
  the same settings. It starts with a notice, "These settings have been merged into
  Controls and can also be edited there", whose button opens the slot. When the slot is
  unavailable (its host is missing or does not declare it), ModCore Settings shows the
  category's settings under ModCore Templates instead, saved in the same place.

A category's templates appear in the order their modules register them
(`MC.registerTemplate`); priority does not affect this order.

Templates with `uniqueBy = 'category'` share one template picker per category, with
`None`. Templates with `uniqueBy = 'priority'` share one picker per priority, labelled
`<Category> (priority <n>)`, after the category picker and lowest priority first.
Each template choice notes its module folder; ModCoreSettings shows the module's name
on a second line under the template's label. `None` and templates without a module have
no note. Every other template gets an `Enabled` toggle, labelled with the template's label, that
heads its settings, so the heading row itself turns the template on or off. It is off by default; a template
declaring `defaultEnabled = true` starts on. A category can have both. A template's
optional `description` (text) fills the side panel: on its Enabled toggle, and on its
choice in a template picker while it is selected. A template that declares `enabled = false` still shows in
the menu but receives no callbacks, whatever the player selects.

## Field declarations

Keep runtime values in `settings`. A template's `menu` is its ordered list of
groups; variation pickers show first and these groups after them.

```lua
local template = {
    id = 'example.quickslots',
    label = 'Example quickslots',
    category = 'player.quickslots',
    objects = {abilities = {}}, -- this example declares a menu without changing properties
    variations = {
        style = {
            description = 'Choose the visual arrangement.',
            values = {[0]='Swap', [1]='Stack'},
            default = 0,
        },
    },
    menu = {
        {id='Layout', label='Layout', variation={style=1}, fields={
            {id='.Size', label='Size',
                values={min=10,max=200,step=1,suffix='%'}, default=100},
        }},
    },
}

function template.attach(objects, params, original)
    return original
end
return template
```

A leading dot makes a child ID relative to its group: `Layout` + `.Size` becomes
`LayoutSize`. An absolute child ID is used as written. A group under a variation may
likewise use a relative ID, but an absolute group ID is usually clearer.

A field declares what it holds (`type`) separately from how it shows (`widget`), with
`values` the domain and `default` a separate, explicit property. `type` may be left out
when `values` says it:

| `type` | `values` | `default` | `widget` (first is the default) |
|---|---|---|---|
| `enum` | a numeric-keyed label map such as `{[85]='Small',[100]='Medium'}`, ordered by value | a value | `picker` (DMM's arrows), `tabs` (up to 8), `cycler`, `switch` (values 0 and 1) |
| `integer` | `{min=-1000,max=1000,step=10,suffix=}`, or `'percent'` (0..100 with `%`) | a number | `slider` |
| `range` | `{min=0,max=100,step=10,suffix='%',delta={10}}` | `{low,high}` | `range` |

A range is always declared (`type='range'`): a low and a high value on one track that the
template reads as `{low, high}`, saved as `<low>|<high>`. `min` and `max` are its edges, or
`{low marker's, high marker's}` bounds, such as `min={0,60}, max={40,100}`; `delta` is the
smallest and largest `high-low`, `{min,max}`, `{min}` or one number for both. `step`
divides the track into 1 to 40 steps. Category settings and slot categories take no range.

`style` makes a row stand out: `'title'` puts an enum in the page title row,
`'category'` lets it stand in for its group's heading, `'notice'` sets it small and
muted. A menu group's `style='none'` hides its heading. Sizes otherwise follow a row's
place on the page.

A picker choice is its label, or a ModCore Settings menu-data choice without its
value: `{label=, note=, sound=}`. `note` is shown small under the choice (at most 64
characters); `sound` is a Wwise event path under `/Game/` that plays instead of the
menu's change sound when the row changes to that choice, or `'none'` for silence:

```lua
values={[0]='None', [1]={label='Short Swoosh', sound='/Game/Audio/AK_Events/Events/UI/UI_Inventory/UI_Claws_Equip'}}
```

### Listed choices

A keyed picker lists `{key=, label=, note=, sound=}` choices and saves the chosen key. Among
them, `{from=<file>}` entries name a list file relative to the template module's `Scripts/`;
ModCore Settings runs it every time the page opens and puts the choices it returns in
that place:

```lua
{id='.Incoming', label='Attack incoming', default='chime', values={
    {key='none', label='None'},
    {key='chime', label='Chime', note='flat', sound='/Game/Audio/AK_Events/Events/UI/UI_Gameplay/UI_AA_Cooldown_Ended'},
    {from='choices/cue_sounds.lua'},
}}
-- Scripts/choices/cue_sounds.lua: pure Lua 5.4, run in ModCore Settings' Lua state
return function(context)
    local names = context.files('sounds')     -- names directly inside <module>/sounds
    local out = {}
    for _, name in ipairs(names or {}) do
        local key = name:lower():match('^cue_([%w_]+)%.wav$')
        if key then out[#out + 1] = {key=key, label=key, note='cue'} end
    end
    table.sort(out, function(a, b) return a.key < b.key end)
    return out
end
```

`context.head(path, count)` gives the first `count` bytes (at most 4096) of a file in the
module folder, or nil and why, so a list file can leave out a file it cannot use, such as a
picture of the wrong size.

Keys are letters, digits and `_ . -`, never a number. The `default` may be a listed key.
Rules (`visible`, `label`, `dim`) may name fixed keys only, and a listed picker shows as a
`picker` or `cycler`. Because the files decide what is offered, a listed picker accepts any
well-formed saved key and delivers it unchanged: the template must fall back for a key whose
file is gone. ModCore Settings' reference describes what a list file may do, what happens when it
fails and what shows for a field left with fewer than two choices.

A field may declare `conditions`, in ModCore Settings' menu-data shapes:

```lua
{id='Bars', label='Bars', fields={
    {id='.A', label='Orientation', values={[7]='Horizontal', [5]='Vertical'}, default=7},
    {id='.KH', label='Key Indicators', values={[0]='Above', [1]='Below'}, default=0,
        conditions={visible={field='.A', values={7}}}},
    {id='.KV', label='Key Indicators', values={[0]='Left', [1]='Right'}, default=0,
        conditions={visible={field='.A', values={5}},
            label={field='.A', values={[5]='Side Key Indicators'}}}},
}},
```

- `visible={field=, values={...}, playerExists=}` shows the row only while every
  given part holds: `field` holds one of `values`, and a player is (`true`) or is
  not (`false`) in the world. `field` and `values` go together; either part may be
  left out.
- `label={field=, values={[value]='text'}}` shows that text instead of `label` while
  `field` holds the value. A key may list values sharing one text:
  `values={[{5,7}]='Keys'}`; each value appears once.
- `dim={value, ...}` fades the row while its own value is one of these.
- `field` resolves like a field ID: `.A` in group `Bars` is `BarsA`. A variation
  picker is named by its title-cased ID, such as `Style`. A standalone field must
  use an absolute ID.
- The source must be a picker declared earlier in the template. `values` lists
  its values, not its labels.
- A field in a variation branch must depend on a picker in the same branch.
- The template picker and variation conditions still apply. A hidden source
  hides its dependents.
- Conditions only affect presentation. Hidden fields keep their saved values and
  are still delivered in `params.settings`.

Conditions apply on slot pages too.

A field may also appear directly in the `menu` array when it needs no visual group.
Its ID must be absolute. It shows unheaded, in its place in the menu.

A group with `variation={style=1}` is a branch of that variation: it and all its fields
show only while that value is selected. A group without `variation` is shared. Variation values remain ordinary effective settings using
the title-cased variation ID (`style` becomes `Style`).

Categories declare shared fields in `menu.groups[].fields`. Their values are shared
and templates override matching keys. Category text fields are set in the config only.

Template `uniqueBy` controls selection multiplicity:

| `uniqueBy` | At most one enabled template per |
|---|---|
| `false` or omitted | no limit |
| `'category'` | category |
| `'priority'` | priority within the category (`priority`, 100 when omitted) |

Enabling a template detaches the enabled one in its group before the new one attaches,
and a failed detach holds the new one back. Groups are separate: a category-unique
template never displaces a priority-unique one, and templates without `uniqueBy` attach
alongside both. Categories do not declare `uniqueBy`.

### Live preview

A template may declare `preview={background='images/x.jpg', sound='Sound'}` (a picture in
its module folder; `sound` names the menu group, or a list of groups such as
`{'Sound','Options'}`, or `true` for every setting of the template, its Enabled toggle
included, whose settings make the preview sound when ModCore Settings' sound button is on
Auto). Its module page then gets ModCore Settings' live preview: while the page is open,
the page's selected templates that declare `preview` attach to the preview with the
page's current values, applied or not, and attach again on every change. Each gets its
own layer, `objects={hud=<the menu's widget>, cue=<layer>}`, and params with
`preview=true` and a 1920 by 1080 `screen`. They stack by `priority` as on the HUD:
lowest underneath, then by id.

A category plays a script into it in a loop: `preview={length=<ms>, events={{at=<ms>,
attack=<n>, event={...}}, ...}}`. Each event reaches the template's `update` callback with
`preview=true`, the menu widget as `indicator`, a `path` shared by one attack's events and
new each loop, a `sequence`, and `silent=true` when the sound button is Off, or on Auto
while none of the template's `sound` settings is selected. npc.attacks loops four attacks (left, right, ahead,
behind: arrow, then critical, then resolved) and one unblockable attack, 9.4 s in all.
A preview attachment receives only preview events, never the game's, and shows without
waiting for combat.

A module whose templates sit in another provider's slot (player.quickslots, in ModCore
Controls' Quickslots section) gets the preview on its own page too.

#### Lending the game's widgets

Templates that rearrange the game's own widgets, rather than draw their own, preview on
those widgets, lent to the preview. A category opts in with `preview={lend=true,
length=<ms>, events=...}`; it needs exactly one `sharedObjects` created object that
`adopt`s targets, and that object is lent with the widgets it adopted. Its optional
`unavailable` text shows over the preview's background when there is no game to lend
from (the main menu); player.quickslots says "Load a game to preview your Quickslots"
and lends both quickslot wheels.

While the page is open, the page's selected template of that category, if the page owns
it and it declares `preview`, attaches to the lent widgets with `preview=true`, the
game's `screen`, and the page's values over its defaults. The category's applied
template is detached meanwhile; changing a value or the template attaches the preview
again. The script's events reach only the preview, as its named event callbacks
(`callback(params, event, objects)`) with `event.preview=true` and `params.preview=true`;
a `group` or `global` in an event changes only the preview's copy of the state. When
the page closes, the widgets return to the HUD and the applied template attaches again,
with any Apply made while the page was open. If the HUD goes away while lent (a save
load), the preview shows nothing for that category until the page is opened again.

player.quickslots loops 8 s: the focus moves between the wheels every 2 s, as ModCore
Controls' `controls.group.focus`, and the consumable Top slot holds a Global key
(`controls.slots.global`) from 4 s to 6 s, so Double bars show their labels un-merging.

## Saved keys

Setting IDs are derived from the category, module and template, so they stay the same
when templates are added or reordered. The config saves a category's template pick as
`[Templates] <Category>`, a template's rows as `[<Module>.<Template>] <Setting>` and a
category's shared fields as `[<category>] <Setting>` (see [settings.md](settings.md)).
A template picker saves the template's full id (`<Module>_<Id>`), or `None`, such as
`[Templates] PlayerQuickslots=Fangdango_SingleUnderbar`. A saved id that is no longer
offered loads as the default. Missing keys are added; an invalid saved value is
replaced with its default and never stops startup.

## Apply behavior

Only Apply changes what templates see. Managed templates are restored and `attach`
runs again with the new settings; unmanaged templates receive `update`. Switching
templates detaches the outgoing one first. Templates whose effective settings did not
change are left as they are.

MCT keeps the latest ModCore Controls state for templates. The latest
`controls.group.focus` transition is `params.state.controls.group =
{from=<number>,to=<number>}`; it is empty (`{}`) until ModCore Controls reports a focus.
The latest `controls.slots.global` set is `params.state.controls.global =
{[1]={bool x4},[2]={bool x4}}`: wheel 1 abilities, wheel 2 consumables, slots Left,
Top, Right, Bottom; a slot is `true` while its Global key fires regardless of focus, and
every slot is `false` until ModCore Controls reports. The event carries the same table
as `event.global`. `params.state` is a copy. A transition never calls `attach` or
`update`: those run only when a template must be rebuilt (settings, selection or target
changes), and then read the current state.

A template reacts to a transition through an event callback, which MCT calls once
per live attachment to adjust it in place:

```lua
settings={focus={dim=0.7}}, -- template defaults, merged into params.settings
events={
    ['controls.group.focus']=function(params,event,objects)
        -- params matches attach's: settings and screen from the last attach,
        -- plus current state. event.group.to is numeric; from may be nil initially.
        -- objects has the same shape as attach's objects.
    end,
}
```

Only active templates receive callbacks, on the game thread; a template with nothing
attached is not called. A failing callback is reported and does not affect other
templates. Managed templates restore the captured originals on detach or rebuild, so
in-place changes to declared properties need no cleanup.

MCT publishes one event of its own, `templates.layout.changed`, for categories that
declare `layoutEvent = true` (today `player.quickslots`). Its payload is
`{category=<id>}`. It goes out at most once per pass that may have moved, shown or
hidden that category's widgets, never once per widget. Other mods that place widgets
beside the category's own, such as ModCore Controls' Hold underlines, re-read the
layout when it arrives. Per-frame update events do not send it, and neither does a
template's own callback for `templates.layout.changed`.
