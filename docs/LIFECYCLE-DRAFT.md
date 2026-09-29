# MCT lifecycle draft

This is the fresh implementation in `Scripts/mc/`. The previous runtime is preserved in
Git history. This draft is executable with a host adapter and
covered by offline tests. [Template menus](MENUS.md) route committed settings
to this lifecycle. The Lua startup adapter schedules initialization on UE4SS's
game thread and uses Lua references to check object validity and identity.

## Startup

1. Load category definitions once and construct the object source from them.
2. Accept explicitly registered provider template files without executing them.
3. Schedule the one-shot startup callback on the game thread.
4. Accept registrations from other modules while waiting.
5. At the barrier, close registration and execute all registered template files.
6. Validate definitions, generate menus, restore committed settings and subscribe to Apply.
7. Subscribe to lifecycle notifications before taking the initial object snapshot.
8. Process existing objects and then continue through lifecycle events.

`mc.bootstrap.new(options)` implements this sequence. Lua startup supplies the
already-loaded categories, `host`, and `subscribeLoopStart(callback)`. Standalone
hosts can supply those options directly, with optional initial
`selections` and committed `categorySettings`. File lists are explicit; this draft does not search directories.
`execute(path)` may be supplied for another loader; otherwise it uses `loadfile`.
Category sources live in `Scripts/categories`; providers normally keep template
sources directly in their own `Scripts` folder. Each category/template file returns
one definition. The bootstrap object's
`registerTemplate(path)` accepts registrations until the startup callback fires.
The callback subscription must return an unsubscribe function.

Installed providers use the public helper from `Scripts/main.lua`:

```lua
local M = require('mc')
M.addTemplate('layout')
```

`addTemplate` resolves `layout` to `mc_layout.lua` beside the calling file and
registers its path directly with MCT. The template declares `category`; MCT reads
the module ID, author, and version from the provider's `mod.json`. MCT executes the
file at the game-thread barrier. It does not enumerate installed directories.

Late template registration is rejected explicitly. Duplicate file registrations
are ignored. Loading errors fail startup before discovery begins.

After applying module metadata, MCT calls an optional `template.loaded()` once.
This happens before menu/runtime validation; an error fails startup.

## Declared objects

A category declares named objects in `.objects`:

```lua
return {
    name = 'player.quickslots',
    single = true,
    objects = {
        switcher = { source = 'lookup', object = 'WidgetSwitcher /Game/...:WidgetTree.QuickslotsSwitcher' },
        slots = { source = 'lookup', class = '/Game/.../WBP_Quickslot.WBP_Quickslot_C', within = 'switcher' },
        hud_root = { source = 'reference', from = 'switcher', member = '@owner.WidgetTree.RootWidget' },
        actions = { source = 'create', class = '/Script/UMG.CanvasPanel', outer = 'switcher', parent = 'hud_root' },
    },
}
```

The example paths are illustrative. A `reference` source uses `from` and
`member` to read a property from an already obtained object. A `create` source
accepts a native `/Script/Module.Class` path, an `outer` object, and an optional
visual `parent`. MCT uses the outer object's WidgetTree as the new object's
owner and adds it to the declared parent before calling managed
`attach(objects, params, original)`. Without `parent`, the created object remains
unattached. The template must request the created name and its dependencies in
`template.objects`.

- `object` identifies an object; `class` selects a group of class instances.
- `within` limits matches to descendants of every object selected by another entry.
  It traverses all parent levels, excludes the root itself and tolerates hierarchy cycles.
- Missing roots produce no descendants. Unknown selector names and dependency cycles
  are rejected before discovery.
- Each selector produces a set. The category uses their union; one object matching
  several selectors still receives one attachment per template.
- Root entries also belong to that union. Every selected template receives the root
  as well as matching descendants. Selector-specific template subscriptions are
  outside this draft.

Native path interpretation belongs to the host. In particular, a blueprint's
WidgetTree path is not automatically the full name of its live widget instance.
The host must resolve this correctly and exclude class defaults, archetypes and
objects from obsolete worlds. The runtime never guesses from a final object name.

## Template contract

```lua
local template = { id = 'example.quickslots', category = 'player.quickslots' }

function template.attach(object, settings)
    -- Save original state for this object; apply initial settings.
end

function template.update(object, settings)
    -- Apply changed effective settings to the existing attachment.
end

function template.detach(object, settings)
    -- Restore state while valid, using the last successfully applied settings.
end

return template
```

These are plain function calls, not colon methods. All three callbacks are required.
Templates may import `local MC = require('mc')` for `MC.valid(object)`,
`MC.same(a, b)`, and `MC.parent(object)`. `parent` returns a valid UMG panel
parent or nil; it does not traverse UObject outers. `same` compares valid wrappers
by full name and is not a lifetime token. `MC.call(object, method, ...)` returns
the first result, or nil when the method throws. Runtime hosts retain their
additional world/readiness and lifetime checks.

For widget helpers use `local Widget = MC('widget')` or
`local Widget = MC.load('widget')`. These calls return the same helper module.
The widget helper includes `appearance(widget, settings, prefix, position)` for
offset, scale, and opacity fields, plus `reparent(widget, parent)`,
`measure(widget)`, and `position(widget, bounds, x, y, scale)` for rendered layout.
From a template entry file, `MC.template('wheels')` loads its sibling
`mc_wheels.lua` and returns the template table. A name ending in `.lua`, such as
`MC.template('mc_wheels.lua')`, loads that exact sibling filename. Names cannot
contain path separators.
An optional second table supplies shared defaults. The loaded template's keys
override those defaults, and each call receives its own copy of nested tables.

All three callbacks receive effective settings: category values overlaid with
template values, with the template taking precedence. Each callback receives its
own copy. The same effective values are available on `template.settings` during
the call, so a callback that only accepts `object` can use that property.

Precedence is category settings → template-declared defaults → committed template
overrides. Overlays replace whole values by setting key; nested tables are copied
rather than recursively combined. `false` and `0` are real overrides. Omit a key
from the committed overrides to fall back to the template default, or to the
category value when the template has no default.

`runtime:setCategorySettings(categoryName, settings)` replaces the category's
committed values and updates its attached templates with their newly merged
settings. Definition `category.settings` supplies initial category values. Settings
passed to `select` are template overrides, not an already flattened merged table;
this preserves inheritance when category values change.

Each successful attachment/update records its effective settings. `detach`
receives that last successful snapshot, including if a later update failed.

Use `runtime:select(categoryName, { [templateId] = settings })` to commit a category's
selection/settings. An empty selection disables all its templates. Single categories
accept at most one selection. New templates attach to existing matches; changed
settings call `update(object, settings)`, not detach/attach. Each explicit select of an already enabled
template counts as a settings commit, even if the values are equal. Staged UI values
must not call this API. New objects receive the latest committed settings.

MCT tracks each template/object-instance pair. Templates own any original-state
records needed by their callbacks. Those records should not retain native objects
strongly; invalid objects do not receive a cleanup callback. Runtime settings are
plain acyclic Lua tables. Declare UI fields separately in `menu`, as described in
[Template menus](MENUS.md).

### Transitions

| Trigger | Action |
|---|---|
| Matching object ready, selected template not attached | `attach(object, settings)` |
| Committed template/category settings change on attached object | `update(object, settings)` |
| Valid object leaves the category set or loses readiness | `detach(object, settings)` |
| Template disabled, replaced, or runtime stopped; object valid | `detach(object, settings)` |
| Object invalid | Forget attachment; never call `detach` |
| World confirmed invalidated | Forget all objects and attachments; preserve selections |
| New world ready | Discover existing objects again and attach |

Outgoing detaches run before incoming attaches. If a single-category detach fails,
its replacement remains blocked on that object. Other objects/templates continue.
Callback throws and `false, reason` mean failure. `false, 'not_ready'` waits quietly
for another relevant event. Other returns, including no return, mean success.
Failed updates preserve the old attachment; failed detaches retain their records.
Callbacks must avoid partial mutation on failure or restore their own changes before
reporting failure. MCT cannot undo arbitrary Lua callback side effects.

Callbacks run serially. Reentrant selection/events are queued until the current
operation completes. Exceptions are reported through the host's error callback.
`runtime.errors` also retains diagnostics; `runtime:attachments(id)` exposes a copy
of attachment membership for inspection. `stop()` unsubscribes and detaches valid
objects. Repeating `stop()` can retry failed detaches.

## Event host contract

The draft deliberately requires these concrete host operations:

| Operation | Responsibility |
|---|---|
| `valid(object)` | Safe validity check, including invalid references |
| `identity(object)` | Stable string identifying a live instance, including its generation |
| `ready(object)` | Whether this object is ready for template callbacks |
| `matches(object, selector)` | Exact object/class match before applying `within` |
| `parent(object)` | Parent used for descendant membership, or nil |
| `find(selector)` | Snapshot array of live candidates, including unready candidates; ignore `within` here |
| `subscribe(sink, getEpoch)` | Subscribe to lifecycle events; return unsubscribe |
| `onError(error)` | Report runtime/template/startup failures |
| `unwrap(object)` (optional) | Return the actual UObject from a private reference before callbacks; nil suppresses delivery |

Never identify an instance only by its object path or a reusable address. Invalid
objects are checked before identity is read. The host should supply weak/native-safe
references so candidate bookkeeping does not prevent destruction.

Deliver events on the game thread. Capture `getEpoch()` **before** queuing a native
notification and include it in the event. Old-epoch events are ignored.

```lua
sink({kind='changed', object=object, epoch=capturedEpoch})
sink({kind='lost', id=capturedInstanceIdentity, epoch=capturedEpoch})
sink({kind='world_invalidated', epoch=capturedEpoch})
sink({kind='world_ready', epoch=currentEpoch})
```

- `changed` covers creation, readiness, parent changes and membership changes.
  A child discovered before parenting stays a candidate until a later event lets
  MCT reevaluate containment. A parent-change event reevaluates cached descendants.
- `lost` removes an instance from discovery, whether the reference is still valid
  or already invalid. Its ID must have been captured while valid. A later `changed`
  event may reintroduce an object that legitimately reenters the set.
- `world_invalidated` means the old world is already invalid, not about to unload.
  It increments the epoch and suspends attachment. Cleanup of valid objects before
  teardown must instead happen through loss events while they remain usable.
- `world_ready` resumes discovery using the new epoch. Capture it after invalidation
  has been delivered; the adapter owns event ordering.

Initial startup and new-world readiness enumerate objects. Subsequent events
reevaluate cached candidates, without periodic enumeration or timer retries.
A host must deliver creation events for all possible candidates and explicit
readiness/parent/loss notifications. Missing notifications cannot be inferred
without polling; this implementation does not conceal that gap.

## Live integration still to resolve

`Scripts/main.lua` wires the Lua startup adapter and
[UE4SS object source](OBJECT-SOURCE.md). Valid detach,
complete parent-change coverage, and timely object-loss delivery remain pending.
The adapter must clean up any partial
subscription if `subscribe` fails before returning its unsubscribe function.

UE4SS documents class-construction notifications through
[NotifyOnNewObject](https://docs.ue4ss.com/dev/lua-api/global-functions/notifyonnewobject.html).
That event alone does not establish readiness, parenting or destruction coverage.
The prior host also attempted widget construction and map-load hooks. Neither is
assumed to supply a complete lifecycle in this draft.

Existing template `render`, category contexts/events and legacy callback signatures
have not been carried into this fresh contract. They require explicit integration decisions; the draft is not a drop-in
replacement for the parked runtime.

## Validation

```sh
python3 tools/run-tests.py --lua lua5.4 \
  --dmm-choices /path/to/DawnwalkerModMenu/Scripts/choices.lua \
  --presentation /path/to/ModCoreSettings/Scripts/presentation.lua
```

This runs syntax checks for fresh runtime/category files and the draft lifecycle
and menu suites, including the actual DMM parser. The original `tools/run-tests.py` and legacy tests still refer to the old
`ket.*` module layout, which was moved aside before this draft. They are not evidence
for or against the new contract. Native hooks and game behavior remain unverified.
