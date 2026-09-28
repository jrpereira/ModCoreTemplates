# Template menus

The fresh `mct` implementation reuses the menu generator, field validation,
DMM page extension, settings notification client and persistence helpers adapted
from the previous runtime. It generates menus after all registered templates load,
at the startup barrier, before attaching objects.

## Mod layout

```text
<Mod>/
├── Scripts/                  Lua entry points, runtime code, and mod data
│   ├── templates/            Template source files
│   ├── categories/           Category source files
│   └── cache/
│       ├── config.ini        Saved settings; preserve this file
│       ├── identity-catalog.lua
│       └── menu-pages.lua
└── mod_settings.ini          Required here for DMM discovery
```

Generated files go into `Scripts/cache` unless the host requires another location.
DMM requires its discovery manifest at the mod root, but supports the relative
`ConfigFile=Scripts/cache/config.ini` path. The cache directory also contains user
settings and stable IDs, so its contents must not be discarded as disposable data.

## Where pages appear

- **ModCore Templates:** category selectors, template toggles and shared category settings.
- **Category page:** fields for templates explicitly targeting `templates`.
- **Module page:** the default location for template fields; the module
  name comes from the registered `<Module>/Scripts/templates/<file>.lua` path.

Single categories get a template picker with `None`. Other categories get a toggle
per template. A template with `menu.enabled = false` remains represented in the
menu but cannot invoke lifecycle callbacks. This is declaration-level availability,
separate from the player's selection.

## Field declarations

Keep runtime values in `settings` and UI declarations in `menu`. The field/group
schema is copied from the previous implementation:

```lua
local template = {
    id = 'example.quickslots',
    name = 'Example quickslots',
    category = 'player.quickslots',
    settings = {RestoreOriginal = true},
    menu = {
        enabled = true,
        -- target = 'templates' routes these fields to a category page instead.
        groups = {{id='Layout', label='Layout'}},
        fields = {
            {id='Size', label='Size', group='Layout', type='integer',
                min=10, max=200, default=100, suffix='%'},
            {id='Style', label='Style', group='Layout', type='picker',
                values={0,1}, labels={'Swap','Stack'}, default=0},
        },
    },
}

function template.attach(objects, params, original)
    return original
end
return template
```

Categories use the same `menu.groups` / `menu.fields` declarations, without
`target` or `enabled`. Their values are shared and templates override matching keys.
Numeric fields, choice fields, grouping, conditional visibility, tabs and navigation
pickers retain the copied schema. Category text fields remain config-only.
Navigation fields are neither persisted nor delivered to callbacks.

The prior `settings={target=..., enabled=..., groups=..., fields=...}` declaration
shape is also accepted at the bootstrap boundary. It is normalized into menu
metadata plus default runtime values before the lifecycle starts. This does not
adapt old callback signatures: templates still need the fresh attach/update/detach
contract. Category `single` controls selection multiplicity.

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

When `menuRoot` is supplied, its saved configuration takes precedence over
`menuValues`. Missing config keys are added; existing values and unrelated sections
are preserved. Invalid saved values are reported rather than silently overwritten.
Startup creates `Scripts/templates`, `Scripts/categories` and `Scripts/cache` as
needed. Generated config, identity catalog, and pages are stored directly in
`Scripts/cache`. Without `menuRoot`,
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
