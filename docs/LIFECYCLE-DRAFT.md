# Lifecycle reference

This describes the current `Scripts/mc/` implementation. The filename is retained
for existing links. Provider authors should start with the
[developer guide](DEVELOPERS.md); the host contract below is for runtime adapters.

## Startup and registration

1. Load category definitions and construct the object source.
2. Accept explicit provider paths through `MC.registerTemplate('name')`.
3. At the one-shot game-thread startup barrier, close registration and load files.
4. Validate metadata, templates and menus; restore settings and subscribe to Apply.
5. Subscribe to lifecycle notifications before the first object snapshot.
6. Attach selected templates when their objects are ready.

Each template file returns a table declaring `category` and `objects`. Its provider's
`mod.json` supplies module identity, author and version. Registration loads no template
code until the barrier. Late registrations are rejected, duplicates ignored, and a
failing provider file is reported and skipped. Invalid categories or shared startup
services fail startup.

An optional `template.loaded(onCleanup)` hook runs after metadata is applied.
Register cleanup functions with `onCleanup` or return one. MCT runs them in reverse
order on provider failure or session stop. Failed cleanup remains available for a
later stop attempt. MCT cannot undo effects whose cleanup was never registered.

For standalone hosts, `mc.bootstrap.new(options)` accepts categories, a host,
`subscribeLoopStart(callback)` returning an unsubscribe function, and optional
`execute(path)`. Its `registerTemplate(path)` accepts explicit paths until the
barrier. Installed providers use the public client instead.

## Objects

Categories declare named selectors in `objects`:

| Source | Required selector fields | Purpose |
| --- | --- | --- |
| `lookup` | `object` or `class` | Find a live object or class instances |
| Scoped `lookup` | `from`, `class` | Find children relative to another object |
| `reference` | `from`, `member` | Read a member of an already resolved object |
| `create` | Native `class` path, `outer`; optional `parent` | Construct a widget with the outer's WidgetTree as owner |

A lookup's `within` restricts matches to descendants of another selector.
Unknown names and dependency cycles are rejected. Templates request a subset in
`template.objects`; dependencies resolve automatically and only requested targets
are passed to callbacks. A created target must be explicitly included to receive it.
Groups preserve structure, for example `objects={buttons={'ability_left','ability_right'}}`.

Declare captured properties on category targets or template targets/groups.
For example, `abilities={properties={'position'}}` captures translation.
A category's `required=true` targets must be ready; its `sharedObjects` are
prepared before template attachment and restored after template detachment.
A template does not need to request shared objects just to activate that preparation.

Created objects require managed lifecycle. MCT attaches them to the declared
parent before calling `attach`, reuses them during updates and removes them on
cleanup. Templates own visual layout. See [Object source](OBJECT-SOURCE.md) for
native lookup and identity limits.

## Managed callbacks (default)

```lua
function template.attach(objects, params, original)
    -- Change only declared properties on the supplied objects.
    return original
end
```

Return the captured table, or equivalent original values in the same shape.
Returning nothing is an error. MCT captures declared properties, restores them
before rebuilding, and calls `attach` again for committed settings changes.
Managed `update` and `detach` callbacks are unnecessary.

`params` contains copied `settings`, `screen` and `state`. During managed attach,
`params.onCleanup(fn)` registers attachment cleanup. It runs before restoration
on rebuild/detach/failure and when invalid objects are forgotten. Cleanup must
not assume that the world or widgets still exist.

Settings precedence is category values → template defaults → committed template
overrides. Each key replaces the whole value; nested tables are copied rather
than recursively merged. `false` and `0` are real overrides.

## Unmanaged callbacks

Set `managed=false` and provide all three plain functions:

```lua
function template.attach(root, params, objects)
    -- Capture and apply your own state.
end
function template.update(root, params, objects)
    -- Reapply settings without accumulating the previous change.
end
function template.detach(root, params, objects)
    -- Restore your state while objects are valid.
end
```

`root` is the live attachment root; `objects` holds requested targets.
`params.settings` is the effective settings map. Detach receives the last
successfully applied settings and screen snapshot. Throws or `false, reason`
report failure; `false, 'not_ready'` waits for a relevant event. Other returns,
including no return, mean success for unmanaged callbacks.

## Transitions and failures

| Trigger | Managed | Unmanaged |
| --- | --- | --- |
| Selected template becomes ready | Capture and attach | `attach` |
| Committed settings change | Restore and attach again | `update` |
| Valid objects lose readiness, selection changes, or stop | Cleanup and restore | `detach` |
| Objects become invalid | Cleanup and forget; no property restoration | Forget; no `detach` |

Outgoing detaches precede incoming attaches. Failed detach can block a replacement
on that object. Other templates/objects continue. Managed failures attempt
restoration; unmanaged code must undo partial mutations itself. Repeating `stop()`
can retry failed detaches. Callbacks run serially; reentrant work is queued.

With menu subscriptions, use committed menu state as the selection authority.
Standalone hosts may use `runtime:select(category, {[templateId]=overrides})` and
`runtime:setCategorySettings(category, settings)`. An empty selection disables
all templates in that category. Do not mix direct edits with a menu controller's
saved snapshot. `runtime.errors` and `runtime:attachments(id)` expose diagnostics.

## Helpers and events

`local MC=require('mc')` exposes `valid`, `same`, `parent` and `call` helpers.
`same` compares valid full names, not lifetime tokens. `parent` returns a UMG
panel parent. `MC.call` returns the first method result or nil on failure.
`MC('widget')` and `MC.load('widget')` load the widget helper.

`MC.template('wheels', defaults)` loads sibling `mc_wheels.lua`, with template
keys overriding copied defaults; it does not register another template.
Names cannot contain path separators. An explicit `.lua` filename is also accepted.

Declared event callbacks receive `(params, event, objects)` once per live
attachment. Events update shared state without rebuilding templates; later attach
calls see that state. See [Template menus](MENUS.md#apply-behavior).

## Event host contract

| Operation | Responsibility |
| --- | --- |
| `valid(object)` | Safe validity check |
| `identity(object)` | String identifying a live instance and its generation |
| `ready(object)` | Whether callbacks may use it |
| `matches(object, selector)` | Object/class match before `within` filtering |
| `parent(object)` | Parent for descendant membership, or nil |
| `find(selector)` | Snapshot of candidates, including unready ones |
| `screen(object)` | Screen dimensions/reference points, or nil when not ready |
| `subscribe(sink, getEpoch)` | Subscribe to events; return unsubscribe |
| `onError(error)` | Report failures |
| `unwrap(object)` (optional) | Resolve the native object; nil suppresses callbacks |
| `mutate(callback)` (optional) | Run work inside the host's mutation scope |

Deliver events on the game thread. Capture the epoch before queuing work:

```lua
sink({kind='changed', object=object, epoch=capturedEpoch})
```

Old epochs are ignored. `changed` covers creation, readiness and parent changes.
There is no loss or world event: a destroyed object fails `valid` and is forgotten,
without a detach callback, at the next reconcile. Partial subscription failures must
release installed hooks.

Startup enumerates objects; later events reevaluate cached candidates. Missing native notifications cannot be inferred without polling.
Use the [build guide](BUILD.md) for validation; native hook coverage and timely
invalidation still require in-game checks.
