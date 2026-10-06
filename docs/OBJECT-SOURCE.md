# UE4SS object source

`Scripts/main.lua` loads category names from `Scripts/categories/mc.lua` and
accepts template paths registered directly through `mc.registerTemplate`. It performs
no installed-module scan.
`mc.lua_startup` creates the Lua object source and reference host, then schedules
startup on UE4SS's game thread.

The source subscribes to UE4SS notifications before the runtime's first
snapshot. The initial snapshot uses `FindAllOf` once per selector, and an
owner's creation notification looks up its declared children. An unloaded blueprint class may yield no candidates yet. Other
changes reevaluate cached candidates.

## Path matching

`mc.object_selector` interprets class selectors with `IsA` and resolves
`WidgetTree` object selectors against a live widget's outer chain. The
QuickslotsSwitcher selector must have the requested widget class and name,
its immediate outer must be a live `WidgetTree` instance (`WidgetTree` or
`WidgetTree_<number>`), and that tree's live owner must have
exactly the declared HUD blueprint class. Class defaults and objects belonging
to another blueprint with the same final widget name are excluded.

## Readiness and hierarchy

Only categories with at least one registered template are watched: the runtime
ignores the others, and the source registers its notifications once templates
are loaded, before the first snapshot. `NotifyOnNewObject` registers for those
categories' root classes and WidgetTree owners, never for a WidgetTree child's
widget class. An owner notification looks up its
declared children on the next three game-thread dispatches. A creation
notification retains an unready candidate; it does not trigger attachment by
itself. `from` targets register nothing: they are read again from their root
on every reconcile.

## Game state

Widget hooks exist only while a root is live:

- idle (boot, main menu, loading): no widget hooks, only root-class
  notifications, whose classes exist only in a loaded world;
- waiting (a live root is not ready): all widget hooks, including `AddChild`;
- ready (every live root is ready): all except `AddChild`.

Hook changes run on the next game-thread dispatch, never inside a callback. A
hooked call that finds every known root invalid returns the source to idle, so
leaving a world needs no LoadMap hook. Filters are lookups on known root and
owner addresses and on the panels that hold them; only `within` groups walk
widget ancestry. `UserWidget:AddToViewport` and `AddToPlayerScreen` mark the owner ready
and wake cached candidates. Nested HUD widgets can also become ready when
they have a live world and a valid panel parent; `IsInViewport()` is not a
usable signal for Dawnwalker's nested `WBP_GameHUD`. `Widget:RemoveFromParent`
marks a user-widget owner unready before removal and detaches valid matches.
An already parented HUD widget may attach from a snapshot.

For widget selectors, hooks on reflected `PanelWidget:AddChild`,
`PanelWidget:RemoveChild` and `PanelWidget:ClearChildren` wake cached
candidates when a known root, or a panel holding one, changes. `within` groups
also wake for changes beneath a known root, and `Widget:RemoveFromParent`
wakes their descendants after removal. An `AddChild` callback clears a known
UserWidget's removal marker so it can attach again.
Non-root widgets require a valid panel parent even when their owner is ready.
`GetParent` supplies widget ancestry. Other object classes use `GetOuter`.
MCT registers no LoadMap hooks. On a map change the old world's objects become
invalid, and their attachments are forgotten at the next lifecycle event; the
new HUD is found through its creation notification and attaches once shown.
UE4SS `IsValid` reads the object, so calling it on a wrapper kept across garbage
collection, as when a save loads from a running game, reads freed memory and
crashes beyond the reach of `pcall`. MCT therefore keeps every object that
outlives one call, including known roots, Lua references, created and moved
widgets, saved parents and cached slots, as a UE4SSLuaEventBridge weak handle,
and reads it back with `get()`, which checks the native lifetime first. Only a
`get()` result or a fresh hook argument or lookup result is ever called.
Identity includes the bridge's lifetime token, which distinguishes a reused
address and full name through Unreal's object-item serial. The bridge must
expose API 6 with `lifetimes.weak` and `lifetimes.captureObject`. If the bridge's
lifetime service is unavailable, nothing is kept or attached and the bridge's
reason is reported once; there is no address fallback. A live
hook survey found `UserWidget:Construct`, `Destruct` and `OnInitialized`
unavailable to `RegisterHook`. Viewport, parenting and removal hooks registered
successfully, but direct engine changes can bypass those reflected hooks.
Group parent changes and timely invalidation remain live validation limits.

Offline tests do not establish live gameplay acceptance; validate the affected
hooks and templates in game.
