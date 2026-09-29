# Template menus

The fresh `mct` implementation reuses the menu generator, field validation,
DMM page extension, settings notification client and persistence helpers adapted
from the previous runtime. It generates menus after all registered templates load,
at the startup barrier, before attaching objects.

## Mod layout

```text
<Mod>/
├── Scripts/                  Lua entry points, runtime code, and mod data
│   ├── mc_<name>.lua         Explicitly registered template declarations
│   ├── categories/           Category source files
│   └── cache/
│       ├── config.ini        Saved settings; preserve this file
│       ├── identity-catalog.lua
│       └── menu-pages.lua
└── mod_settings.ini          Required here for DMM discovery
```

Generated catalogs, page metadata, and aggregate/category settings go into
`Scripts/cache`. DMM requires its discovery manifest at the mod root and supports
the relative `ConfigFile=Scripts/cache/config.ini` path. A module-target page instead
uses `ConfigFile=config.ini` with the provider rooted in that template module, so
Fangdango settings are stored in `_ModCore_X_Fangdango/config.ini`. On the first startup
after this change, matching values in the former shared config are copied to the
module config. Both locations contain user settings and must be preserved.

## Where pages appear

- **ModCore Templates:** category selectors, template toggles and shared category settings.
- **Category page:** fields for templates explicitly targeting `templates`.
- **Module page:** the default location for template fields; the module
  name comes from the registered `<Module>/Scripts/<file>.lua` path.

Set `menuTarget='templates'` on a template only when its fields belong on the
category page rather than its module page.

Single categories get a template picker with `None`. Other categories get a toggle
per template. A template with `enabled = false` remains represented in the
menu but cannot invoke lifecycle callbacks. This is declaration-level availability,
separate from the player's selection.

## Field declarations

Keep runtime values in `settings`. A template's `menu` is its ordered list of
groups; MCT renders variations first, the standard Control Layout link second,
and these groups last:

```lua
local template = {
    id = 'example.quickslots',
    name = 'Example quickslots',
    category = 'player.quickslots',
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
expands to the validated 0..100 integer range with a `%` suffix. `tab=true` renders
a picker as tabs. MCT infers the field type; templates do not declare `type`,
parallel `labels`, or field-level visibility metadata.

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

`mc.bootstrap.new` now exposes `menu`, `menuController` and `extension` after its
module-load barrier fires. In addition to the lifecycle host and registration
options, provide:

| Option | Purpose |
|---|---|
| `menuRoot` | Mod root; generated state goes into `Scripts/cache`, with only `mod_settings.ini` at root |
| `menuShared` | `ModRef` shared-variable interface for the cross-state handoff; Lua startup supplies it |
| `settingsApi` | Durable Apply subscriber; the copied client is `require('mc.settings_api')` |
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

For direct in-memory integration, pass `bootstrap.extension` to DMM's extension
installer once the barrier has completed. It adds generated pages, replaces a module's no-settings placeholder
when applicable, and handles repeat page builds without duplication. The restored `Scripts/dmm_extension.lua` entry point supports DMM's separate Lua
state through a lazy reader. The Lua startup adapter supplies the generation handoff.

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
receive `update` with category values overlaid by template values. Switching templates
detaches outgoing attachments first. Identical committed snapshots and replayed
provider revisions cause no extra callbacks. Category text values are reread from
committed config on Apply. Subscription teardown ignores already-queued events;
`bootstrap:stop()` closes both menu subscriptions and the object runtime.

Use menu values/config as the selection authority when `settingsApi` is supplied.
The bootstrap's direct `selections` / `categorySettings` options remain available for
standalone runtime fixtures and hosts without menu subscriptions. Do not mix direct
runtime edits with an active menu controller, whose saved snapshot would become stale.

## Tests

```sh
python3 tools/run-tests.py --lua lua5.4 \
  --dmm-choices /path/to/DawnwalkerModMenu/Scripts/choices.lua \
  --presentation /path/to/ModCoreSettings/Scripts/presentation.lua
```

The runner uses temporary output directories. It validates generated pages with the
actual DMM parser and ModCoreSettings presentation code, and exercises Apply routing,
merged settings, persistence, revisions, subscriptions and lifecycle transitions.
These offline checks do not establish in-game rendering or startup timing.
