# ModCore Templates

ModCore Templates (MCT) loads Lua templates, generates their settings menus, and
attaches them when their declared game objects are ready. A **category** defines
available objects; a **template** selects objects and changes their appearance or behavior.

## Choose the right module

| Module | Responsibility |
| --- | --- |
| ModCoreSettings (MCS) | Menu controls, pending edits and Apply |
| ModCoreControls (MCC) | Input bindings and quickslot actions |
| ModCoreTemplates (MCT) | Visual templates, settings and object lifecycle |

Start with the [developer guide](DEVELOPERS.md) and the runnable
[Wheel Nudge example](https://github.com/jrpereira/ModCoreTemplates/tree/main/examples/wheel-nudge).

## Requirements and installation

Use Dawnwalker, UE4SS with Lua 5.4, UE4SSLuaEventBridge API 5 or newer with
`lifetimes.captureObject`, and ModCoreSettings with Dawnwalker Mod Menu (DMM).
Install and enable MCT under `Mods/3_ModCore_Templates`. Disable the old
`_UE4SSTemplatingEngine` installation. Fully restart after changing Lua files.
MCC supplies the Controls page that hosts quickslot visual settings.

MCT installs its registration client as `Mods/shared/mc.lua`. Providers register
from their `Scripts/main.lua` before MCT's startup barrier; MCT does not scan
installed mods for templates.

## Settings and lifecycle

Managed templates declare the properties they change and implement
`attach(objects, params, original)`. Return `original` so MCT can restore those
properties. Apply restores the previous values and attaches again with the new
settings; selecting None restores the original state.

Keep `Scripts/cache/config.ini`, `Scripts/cache/identity-catalog.lua`, and provider
`config.ini` files when updating. Generated menu files can be rebuilt; edit Lua
menu declarations, not generated manifests.

If the bridge reports its native lifetime service unavailable, MCT falls back
to address/full-name identity. That fallback cannot distinguish an object recreated
with the same address and name. See [Object source](OBJECT-SOURCE.md) for limits.

## Logging

Logs appear in `UE4SS.log`. The default level is WARN. For more detail, put
`debug` in `Mods/3_ModCore_Templates/log_level.txt` and restart.

## Documentation

- [Developer guide](DEVELOPERS.md): first template and managed callbacks.
- [Template menus](MENUS.md): fields, variations, placement and storage.
- [Lifecycle reference](LIFECYCLE-DRAFT.md): registration, callbacks and host contracts.
- [Object source](OBJECT-SOURCE.md): UE4SS discovery and readiness.
- [Build guide](BUILD.md): offline tests and in-game checks.
- [Changelog](CHANGELOG.md): version history.
