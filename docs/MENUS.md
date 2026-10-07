# Template menus

MCT generates menus after registered templates load, before attaching objects.
Start with the [developer guide](DEVELOPERS.md) for a complete template. Examples
below focus on menu declarations; callbacks must still declare their targets.

## Mod layout

```text
3_ModCore_Templates/
└── Scripts/
    ├── categories/           Category definitions
    └── cache/
        ├── config.ini        Central saved settings
        ├── identity-catalog.lua
        └── mcs_menu.<generation>*.ini   Generated pages
YourProvider/
├── config.ini               Module-target settings, when generated
└── Scripts/
    ├── main.lua             Registers templates
    └── mc_<name>.lua         Template declaration
```

Generated catalogs, published pages, and aggregate/category settings go into
`Scripts/cache`. MCT publishes its pages through ModCoreSettings' menu-contribution
client (`vendor/menu_contributions.lua`, copied unchanged from ModCoreSettings) and writes nothing at the mod
root. Aggregate and category pages resolve `ConfigFile=Scripts/cache/config.ini` against
the MCT root. A module-target page instead uses `ConfigFile=config.ini` against that
template module's root, so
Fangdango settings are stored in `9_ModCore_Fangdango/config.ini`. On the first startup
after this change, matching values in the former shared config are copied to the
module config. Both locations contain user settings and must be preserved.

MCT replaces every file it writes (configs, the catalog and published pages) by
writing `<file>.new`, moving the current file to `<file>.old` and then renaming
`<file>.new` into place. `<file>.old` is kept as the previous version. After a crash,
the next read publishes a complete `<file>.new` whose original was already moved out,
and discards any other `<file>.new`. A file deleted on purpose is not restored from
its `.old`.

## Where pages appear

- **ModCore Templates:** category selectors, template toggles and shared category settings.
  It takes the place of the menu entry for MCT's own folder and is hidden when empty.
- **Category page:** fields for templates explicitly targeting `templates`, listed under
  ModCore Templates.
- **Module page:** the default location for template fields, in the ModCore group. It
  takes the place of the module's own entry when that entry has no settings. The module
  name comes from the registered `<Module>/Scripts/<file>.lua` path.

Set `menuTarget='templates'` on a template only when its fields belong on the
category page rather than its module page.

- **Slot:** a single category may name a slot on another provider's page:

  ```lua
  slot = { provider = 'controls', slot = 'visuals' },
  ```

  `provider` is the full provider id, or the lowercase short name of a `ModCore<Name>`
  provider. MCT publishes the category's Template picker, shared category fields and
  every template's fields on a hidden page (`ModCoreTemplates.slot.<category>`), and
  contributes those rows to the slot through ModCoreSettings. The category then has no
  aggregate, category or module rows. Slot rows carry no Category rules, so each row is
  gated by its own rule: the Template picker always shows; other rows show while their
  template is selected, or while their variation value is selected. Navigation links
  are left out. Values are stored in the central config. The first start after a
  category gains a slot copies its saved values from the template modules' configs
  (the last module wins, as before) and records `slot.<category>=1` under
  `[Migrations]`; module configs are left unchanged. A module whose templates all
  moved to slots keeps its page in the module group. The page edits the same rows,
  limited to its own templates, in the central config. It starts with a small notice,
  "These settings have been merged into Controls and can also be edited there", whose
  button (`mcLinkPage=<slot address>`) opens the slot. That notice is the page's only
  link; navigation rows are left out, as in the slot. When the
  slot is unavailable (its host is missing or does not declare it), ModCoreSettings shows
  the hidden page under ModCore Templates instead, with the same storage and Apply.

Single categories get a template picker with `None`. Each template choice notes its
module, the `id` from the module's `mod.json`, through `mcChoiceNotes`; ModCoreSettings
shows it on a second line under the template name. `None` and templates without a module
have no note. Other categories get a toggle per template. A template with `enabled = false` remains represented in the
menu but cannot invoke lifecycle callbacks. This is declaration-level availability,
separate from the player's selection.

## Field declarations

Keep runtime values in `settings`. A template's `menu` is its ordered list of
groups; MCT renders variations first and these groups after them. MCT adds no
link rows of its own: a slot template reaches its slot host through the merged
notice above.

```lua
local template = {
    id = 'example.quickslots',
    name = 'Example quickslots',
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

The leading dot makes a child ID relative and is removed when IDs are composed:
`Layout + .Size` becomes the existing flat key `LayoutSize`. An absolute child ID
is left unchanged. A group under a variation may likewise use a relative ID, but
an absolute group ID is usually clearer and preserves existing keys.

`values` defines the field domain and `default` remains a separate, explicit field
property. A range table such as `{min=-1000,max=1000,step=10}` produces an integer.
A numeric-keyed label map such as `{[85]='Small',[100]='Medium'}` produces a picker,
ordered by numeric value. A named internal domain such as `values='percent'`
expands to the validated 0..100 integer range with a `%` suffix. Pickers use DMM's
arrow selector by default; set `tab=true` for a picker with up to eight choices.
MCT infers the field type; templates do not declare `type` or
parallel `labels`.

A field may declare `conditions` that depend on a picker in the same template:

```lua
{id='Bars', label='Bars', fields={
    {id='.A', label='Orientation', values={[7]='Horizontal', [5]='Vertical'}, default=7},
    {id='.KH', label='Key Indicators', values={[0]='Above', [1]='Below'}, default=0,
        conditions={visible={field='.A', match={7}}}},
    {id='.KV', label='Key Indicators', values={[0]='Left', [1]='Right'}, default=0,
        conditions={visible={field='.A', match={5}},
            label={field='.A', match={5}, text='Side Key Indicators'}}},
}},
```

- `visible` shows the row only while `field` holds one of the `match` values.
- `label` shows `text` instead of `label` while `field` holds one of the `match`
  values.
- `field` resolves like a field ID: `.A` in group `Bars` is `BarsA`. A variation
  picker is named by its title-cased ID, such as `Style`. A standalone field must
  use an absolute ID.
- The source must be a picker declared earlier in the template. `match` lists
  its values, not its labels.
- A field in a variation branch must depend on a picker in the same branch. A
  slot row carries one visibility condition, so it inherits the branch through
  its source.
- The template picker and variation conditions still apply. A hidden source
  hides its dependents.
- Conditions only affect presentation. Hidden fields keep their saved values and
  are still delivered in `params.settings`.

Conditions compile to `VisibleWhen`/`VisibleValues` and `mcLabelWhen`/`mcLabels`
on the generated row. Both apply on slot pages too; `label` there needs the
ModCoreSettings release that copies slot label rules.

A field may also appear directly in the `menu` array when it needs no visual group.
Its ID must be absolute. MCT places it in an unheaded generated section while
preserving its position in the menu declaration.

A group with `variation={style=1}` is a branch of that variation. MCT applies the
condition to the generated group; all its fields inherit it. A group without
`variation` is shared. Variation values remain ordinary effective settings using
the title-cased variation ID (`style` becomes `Style`).

Categories retain their shared `menu.groups[].fields` declaration. Their values
are shared and templates override matching keys. Category text fields remain
config-only. Generated navigation fields are neither persisted nor delivered to
callbacks.

Category `single` controls selection multiplicity.

## Startup integration

`mc.bootstrap.new` exposes `menu` and `menuController` after its
module-load barrier fires. In addition to the lifecycle host and registration
options, provide:

| Option | Purpose |
|---|---|
| `menuRoot` | Mod root (absolute); generated state and published pages go into `Scripts/cache` |
| `menuShared` | `ModRef` shared-variable interface for publishing pages to ModCoreSettings; Lua startup supplies it |
| `settingsApi` | Durable Apply subscriber; the copied client is `require('settings_api')`, from `Scripts/vendor` |
| `queue` | Game-thread dispatcher for settings callbacks |
| `menu` | Generator options, such as `description` or an in-memory identity catalog |
| `menuValues` | Initial committed setting-ID values for an in-memory host without `menuRoot` |

When `menuRoot` is supplied, saved central and module configurations take precedence
over `menuValues`. Missing config keys are added; existing values and unrelated
sections are preserved. Invalid saved values are reported rather than silently
overwritten.
Startup creates `Scripts/categories` and `Scripts/cache` as
needed. The central config, identity catalog, and pages are stored directly in
`Scripts/cache`; module-target configs are stored at their module roots. Without `menuRoot`,
generation and Apply routing work in memory and do not write any files.

With `menuShared`, MCT publishes its pages once the barrier has completed and withdraws
them on stop. A failed publish is reported and the templates keep running on their saved
settings. Startup also removes `mod_settings.ini` and `Scripts/cache/menu-pages.lua` left by
the former DMM handoff: a leftover `mod_settings.ini` would claim the `ModCoreTemplates` page
id and make ModCoreSettings skip every MCT page.

Saved setting IDs use `MCT_`. Keep the identity catalog:
choice numbers and named setting reservations survive subsequent regeneration,
including adding a template before an existing one. The catalog is persisted before
manifests using its IDs are written.

## Apply behavior

Only committed Apply notifications affect the lifecycle. The controller validates
the provider payload, copies values belonging to that page into its complete saved
snapshot, and decodes category settings separately from template overrides.
Unowned fields are omitted from routed pages; their committed values are preserved.

The controller calls `runtime:commit` once for a coherent batch. Existing attachments
receive effective category/template settings. Managed templates restore and rerun
`attach`; unmanaged templates receive `update`. Switching templates
detaches outgoing attachments first. Identical committed snapshots and replayed
provider revisions cause no extra callbacks. Category text values are reread from
committed config on Apply. Subscription teardown ignores already-queued events;
`bootstrap:stop()` closes both menu subscriptions and the object runtime.

MCT also subscribes to category-independent ModCore events through
`Scripts/vendor/mc_events.lua`, copied unchanged from ModCoreControls. The latest `controls.group.focus` transition is owned by
MCT as `bootstrap.state.controls.group = {from=<number>,to=<number>}`; it is empty
(`{}`) until ModCore Controls reports a focus. Template
callbacks receive a copied snapshot at `params.state`. A transition never calls
`attach` or `update`: those run only when a template must be rebuilt (settings,
selection or target changes), and then read the current state. The callback copy
cannot mutate MCT's stored state.

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

MCT validates and registers these declarations only after the provider's load
hook and full template validation succeed. One transport subscription serves all
templates declaring the same event. Only active templates receive callbacks, on
the game thread inside the host's mutation scope; a template with nothing attached
is not called. Callback failures are isolated and reported.
Managed templates restore the captured originals on detach or rebuild, so
in-place changes to declared properties need no cleanup.

Use menu values/config as the selection authority when `settingsApi` is supplied.
The bootstrap's direct `selections` / `categorySettings` options remain available for
standalone runtime fixtures and hosts without menu subscriptions. Do not mix direct
runtime edits with an active menu controller, whose saved snapshot would become stale.

## Tests

```sh
python3 tools/run-tests.py --lua lua5.4
```

The runner uses temporary output directories. It validates the published contribution
with the vendored ModCoreSettings client and exercises Apply routing,
merged settings, persistence, revisions, subscriptions and lifecycle transitions.
Passing `--dmm-choices` and `--presentation` also parses generated pages with the actual
DMM parser and ModCoreSettings presentation code. These offline checks do not establish
in-game rendering or startup timing.
