# Lifecycle reference

Provider authors should start with the [developer guide](DEVELOPERS.md); this page is
the reference for registration, objects, callbacks and events.

## Startup and registration

1. Providers register template files with `MC.registerTemplate('name')` from their
   `Scripts/main.lua`.
2. Once every Lua mod has started, MCT closes registration and loads the files.
3. MCT validates templates and menus and restores saved settings.
4. Selected templates attach when their objects are ready.

Each template file returns a table declaring `category` and `objects`. Its provider's
`mod.json` supplies module identity, author and version. No template code runs at
registration. Late registrations are rejected, duplicates ignored, and a failing
provider file is reported and skipped.

An optional `template.loaded(onCleanup)` hook runs after metadata is applied.
Register cleanup functions with `onCleanup` or return one. MCT runs them in reverse
order on provider failure or session stop. Failed cleanup remains available for a
later stop attempt. MCT cannot undo effects whose cleanup was never registered.

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
For example, `abilities={properties={'position'}}` captures translation. Properties are
`parent`, `order`, `slot`, `position`, `size`, `opacity`, `color` (the widget's own
`ColorAndOpacity`, which tints everything it draws), `widthOverride` and
`heightOverride` (a SizeBox override as `{enabled, value}`) and `activeIndex` (a
WidgetSwitcher's active child). `box` captures the widget's layout box
(`width`, `height`, `pivotX`, `pivotY`) for the template to read; it is not restored.
A category's `required=true` targets must be ready; its `sharedObjects` are
prepared before template attachment and restored after template detachment.
A template does not need to request shared objects just to activate that preparation.
A category declaring `layoutEvent=true` has MCT publish `templates.layout.changed`
after each turn that may have moved, shown or hidden its widgets; see
[Template menus](MENUS.md).

Created objects require managed lifecycle. MCT attaches them to the declared
parent before calling `attach`, reuses them during updates and removes them on
cleanup. Created objects that share a parent stack in template order (priority, then
id), whatever order the templates attach in. A created object may `adopt` a list of
existing objects: they move in as its children, optionally with `adoptLayout='canvas'`
and `adoptOpacity`, and return to their saved parent, order and slot when it is
released. Templates own visual layout. See [Object source](OBJECT-SOURCE.md) for
how objects are found and their limits.

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
not assume that the world or widgets still exist, and must not call a widget
kept from the attach call: hold it with `MC.hold(widget)` and read it with
`MC.get(handle)`, which returns nil once the widget was collected.

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

Outgoing detaches precede incoming attaches. A failed detach can block a replacement
on that object. Other templates and objects continue. Managed failures attempt
restoration; unmanaged code must undo partial changes itself. Callbacks run one at a
time.

## Helpers and events

`local MC=require('mc')` exposes `valid`, `same`, `parent`, `call`, `hold`, `get`
and `release` helpers. The first four take objects from the current call.
`same` tells whether two objects have the same full name. `parent` returns a UMG
panel parent. `MC.call` returns the first method result or nil on failure.
`MC.hold(object)` returns a handle, or nil and a reason;
`MC.get(handle)` returns the live object or nil once it died; `MC.release(handle)`
drops it early.
`MC('widget')` and `MC.load('widget')` load the widget helper.

`MC.template('wheels', defaults)` loads sibling `mc_wheels.lua`, with template
keys overriding copied defaults; it does not register another template.
Names cannot contain path separators. An explicit `.lua` filename is also accepted.

Declared event callbacks for ModCore events, such as `controls.group.focus`, receive
`(params, event, objects)` once per live attachment. Events update shared state
without rebuilding templates; later attach calls see that state. See
[Template menus](MENUS.md#apply-behavior). The template events `wake`, `sleep` and
`update` are called differently; see below.

## Category hooks and template events

A category's `hooks` time its templates with MCT's signals:

| Hook | Effect |
| --- | --- |
| `attach` | New attachments wait until this signal holds |
| `wake` | Selected templates are awake while it holds; defaults to `attach` |
| `sleep` | Puts them to sleep when it fires; defaults to the opposite of `wake` |
| `update` | Names an update event that awake templates receive |

| Signal | Fires when | Opposite |
| --- | --- | --- |
| `MC_PlayerReady` | The loading screen finishes fading out | `MC_PlayerUnready` |
| `MC_PlayerUnready` | A loading screen finishes fading in | `MC_PlayerReady` |
| `MC_CombatStart` | The player's combat starts | `MC_CombatEnd` |
| `MC_CombatEnd` | Combat ends, or a loading screen finishes fading in | `MC_CombatStart` |

A signal holds from when it fires until its opposite fires; none holds before it
first fires. When a signal is unavailable in the game, a start signal holds for good
and an end signal never fires. `player.quickslots` wakes on
`MC_PlayerReady`. `npc.attacks` attaches on `MC_PlayerReady`, wakes on
`MC_CombatStart`, sleeps on `MC_CombatEnd` and takes `MC_NPCAttackIndicator` updates.

Template events are declared in `template.events` and called once per template, not
per attachment, in priority order:

- `wake(params, event)` and `sleep(params, event)`: `params` holds copied `settings`
  and `state`; `event` is `{name='wake' or 'sleep', signal=<signal or nil>}`. There
  are no objects or screen. A failing callback is reported and the template still
  changes state, so a later sleep can undo a partial wake.
- `update(params, event)`: called as soon as the event's source reports it. For
  `MC_NPCAttackIndicator` that is about one frame after the game's change (see below). `params.settings` is the template's own table, not a copy: read it, do not
  change it. `event` is the update event with `name='update'` and `signal` set to
  its name. Objects in it are valid only during the call.

`MC_NPCAttackIndicator` turns the combat target indicator's icon changes into update
events. It needs UE4SS Lua Extensions 1.4.0; without its Event Bridge MCT logs that the indicator is
unavailable. Events follow the game
by about one frame and carry an increasing `sequence`:

| `kind` | Fields | Meaning |
| --- | --- | --- |
| `arrow` | `direction`, `path`, `indicator`, `stub` | An attack shows on an indicator |
| `critical` | `direction`, `path`, `indicator`, `stub` | That attack's parry window opened |
| `resolve` | `path`, `indicator`, `reason` | The indicator's attack ended: `'sword'` (defending) or `'hidden'` |
| `unblockable` | `path`, `indicator`, `active`, `stub` | The unblockable skull showed (`true`) or went (`false`) |

`direction` is 1 top, 2 bottom, 3 left, 4 right. `indicator` is the live widget,
valid only during the event; `path` names it for later. `stub` is the attacking
enemy's `DogwoodAIStub` path; it is nil when the attacker cannot be told, and
`unblockable` carries it only when `active`.
