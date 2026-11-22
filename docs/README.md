# ModCore Templates

ModCore Templates (MCT) loads Lua templates, generates their settings menus, and
attaches them when their declared game objects are ready. A **category** defines
available objects; a **template** selects objects and changes their appearance or behavior.

## Features and benefits

- **Declare objects of interest:** select category objects and the properties you
  change; MCT resolves their dependencies and supplies the requested objects.
- **Let MCT manage object lifecycle:** it waits for ready targets, checks they are
  still alive before callbacks, and attaches again as targets change. Use supplied
  objects during callbacks; keep one past a callback only as an `Objects.hold` handle.
- **Let managed templates track changes:** MCT captures declared properties and
  restores them on rebuild or detachment. Selecting None restores the original
  state; objects that died are forgotten safely.
- **Implement the visual change in one callback:** managed templates need only
  `attach`; MCT handles restoration and reruns it after committed settings changes.
- **Generate settings menus from the template:** declare fields, variations and
  conditions alongside the visual behavior; MCT handles menus, saved values and Apply.
- **Place settings where players need them:** use module/category pages or a
  declared slot such as Controls' quickslot visuals area.
- **React to declared events:** active templates receive callbacks on the game
  thread, and one failing callback does not affect the others.
- **Keep companion widgets in place:** MCT announces `templates.layout.changed`
  whenever the quickslot key indicators may have moved, shown or hidden, so
  ModCore Controls can keep its Hold underlines under the keys.
- **Preview templates live:** a template declaring `preview` gives its module page
  a looping live preview in ModCore Settings' side panel, with the page's current
  values. Templates that rearrange the game's own widgets, such as the quickslot
  wheels, preview on those widgets while the page is open; this needs a loaded game. See [Template menus](MENUS.md#live-preview).

## Choose the right module

| Module | Responsibility |
| --- | --- |
| ModCoreSettings (MCS) | Menu controls, pending edits and Apply |
| ModCoreControls (MCC) | Input bindings and quickslot actions |
| ModCoreTemplates (MCT) | Visual templates, settings and object lifecycle |

Start with the [developer guide](DEVELOPERS.md) and the runnable
[Wheel Nudge example](https://github.com/jrpereira/ModCoreTemplates/tree/main/examples/wheel-nudge).

## Requirements and installation

Use Dawnwalker, UE4SS with Lua 5.4, UE4SSLuaEventBridge 1.3.0 or newer (API 7,
weak handles and function hooks), and ModCoreSettings 1.9.0 or newer with Dawnwalker Mod Menu (DMM).
Install and enable MCT under `Mods/3_ModCore_Templates`. Disable the old
`_UE4SSTemplatingEngine` installation. Fully restart after changing Lua files.
MCC supplies the Controls page that hosts quickslot visual settings.

Providers register their templates with `require('mc')` from their
`Scripts/main.lua`; MCT does not scan installed mods for templates. A provider must load after MCT: UE4SS starts the mods in
`mods.txt` first, then mod folders alphabetically, so a provider's folder sorts after
`3_ModCore_Templates` and stays out of `mods.txt`.

## Settings and lifecycle

Managed templates declare the properties they change and implement
`attach(objects, params, original)`. Return `original` so MCT can restore those
properties. Apply restores the previous values and attaches again with the new
settings; selecting None restores the original state.

Keep `Scripts/cache/config.ini` and provider `config.ini` files when updating; they
hold the player's settings. Edit Lua menu declarations to change a page.

If the bridge reports its lifetime service unavailable, MCT attaches no templates and
logs the bridge's reason once. See [Object discovery and limits](OBJECT-SOURCE.md).

## Logging

Logs appear in `UE4SS.log`. The default level is WARN. For more detail, install the
UE4SS Lua Log Bridge and raise ModCoreTemplates's level on its Logs page, or set
`ModCoreTemplates=DEBUG` under `[Levels]` in the bridge's `config.ini`.

## Documentation

- [Nexus description](https://github.com/jrpereira/ModCoreTemplates/blob/main/docs/NEXUS.bb): condensed, paste-ready module description in BBCode.
- [Developer guide](DEVELOPERS.md): first template and managed callbacks.
- [Template menus](MENUS.md): fields, variations, placement and storage.
- [Lifecycle reference](LIFECYCLE-DRAFT.md): registration, callbacks and events.
- [Object discovery and limits](OBJECT-SOURCE.md): which objects templates get, and when.
- [Changelog](CHANGELOG.md): version history.
