# UE4SS object source

`Scripts/main.lua` loads category names from `Scripts/categories/mc.lua` and
accepts template paths registered directly through `mc.addTemplate`. It performs
no installed-module scan.
`mc.lua_startup` creates the Lua object source and reference host, then schedules
startup on UE4SS's game thread.

The source subscribes to UE4SS notifications before the runtime's first
snapshot. The initial snapshot and new-world snapshots use `FindAllOf` once
per selector. An unloaded blueprint class may yield no candidates yet. Other
changes reevaluate cached candidates.

## Path matching

`mc.object_selector` interprets class selectors with `IsA` and resolves
`WidgetTree` object selectors against a live widget's outer chain. The
QuickslotsSwitcher selector must have the requested widget class and name,
its immediate outer must be a live `WidgetTree` instance (`WidgetTree` or
`WidgetTree_<number>`), and that tree's live owner must have
exactly the declared HUD blueprint class. Class defaults and objects belonging
to another blueprint with the same final widget name are excluded. A live
world token identifies the current map after `LoadMapPost`; an old HUD can
remain valid without attaching to the new world.

## Readiness and hierarchy

`NotifyOnNewObject` registers for declared classes and WidgetTree owners. A
creation notification retains an unready candidate; it does not trigger
attachment by itself. `UserWidget:AddToViewport` and `AddToPlayerScreen` mark the owner ready
and wake cached candidates. Nested HUD widgets can also become ready when
they have a live world and a valid panel parent; `IsInViewport()` is not a
usable signal for Dawnwalker's nested `WBP_GameHUD`. `Widget:RemoveFromParent`
marks a user-widget owner unready before removal and detaches valid matches.
An already parented HUD widget may attach from a snapshot.

For widget selectors, including `within` groups, hooks on reflected
`PanelWidget:AddChild`, `PanelWidget:RemoveChild` and
`PanelWidget:ClearChildren` wake cached candidates after hierarchy changes.
`Widget:RemoveFromParent` also wakes descendants after removal. An `AddChild`
callback clears a nested UserWidget's removal marker so it can attach again.
Non-root widgets require a valid panel parent even when their owner is ready.
`GetParent` supplies widget ancestry. Other object classes use `GetOuter`.
Map pre-load makes objects unready and detaches valid attachments; post-load
invalidates the old set, records the new world and starts one new snapshot.
Lua references check `IsValid` and object identity before callbacks. Identity
includes the UE4SSLuaEventBridge object lifetime token, which distinguishes a
reused address and full name through Unreal's object-item serial. The bridge
must expose API 5 and `lifetimes.captureObject`. A failed native ABI probe does
not prevent MCT startup; capture then fails and the source does not attach that
object. The source reports identity failure once. A live
hook survey found `UserWidget:Construct`, `Destruct` and `OnInitialized`
unavailable to `RegisterHook`. Viewport, parenting and removal hooks registered
successfully, but direct engine changes can bypass those reflected hooks.
Group parent changes and timely invalidation remain live validation limits.

Live gameplay acceptance for the current runtime remains unverified.
