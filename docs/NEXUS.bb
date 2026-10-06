[b]ModCore Templates[/b]

ModCore Templates (MCT) provides an environment for modifying Dawnwalker's UI with Lua templates. Declare the objects and properties you want to change; MCT finds ready targets, manages their lifecycle and generates settings menus.

[b]Features and benefits[/b]
[list]
[*]Declare objects of interest and let MCT resolve their dependencies and supply the requested objects.
[*]Discovery uses an initial snapshot followed by creation/readiness notifications and cached candidates, avoiding repeated full scans.
[*]MCT manages readiness, references, validity checks and reattachment as targets change. Use supplied objects during callbacks instead of retaining widgets.
[*]Managed templates automatically capture declared properties and restore them on rebuild or valid detachment, including when selecting None.
[*]Focus on the visual change in an attach callback; MCT restores and reapplies it after committed settings changes.
[*]Declare settings, variations and conditional fields alongside the template; MCT handles generated menus, saved values and Apply.
[*]Place settings on module/category pages or in shared areas such as Controls' quickslot visuals.
[*]Declare event reactions; MCT shares subscriptions and delivers callbacks to active attachments on the game thread.
[/list]

[b]Requirements and installation[/b]

Requires The Blood of Dawnwalker, UE4SS with Lua 5.4, UE4SSLuaEventBridge API 5 or newer with lifetimes.captureObject, and ModCore Settings with Dawnwalker Mod Menu. Install and enable under Mods/3_ModCore_Templates and disable the former _UE4SSTemplatingEngine installation. Fully restart after changing Lua files. ModCore Controls supplies the Controls page for quickslot visual settings.

Preserve Scripts/cache/config.ini, Scripts/cache/identity-catalog.lua and template-provider config.ini files when updating. Automatic restoration covers declared properties on managed templates. Invalid objects are forgotten safely; if the bridge's native lifetime service is unavailable, fallback identity cannot distinguish reuse of the same address and name.

[b]The ModCore modules[/b]

ModCore Settings provides menu integration; ModCore Controls handles quickslot input; MCT manages visual templates and object lifecycle.

[b]Documentation[/b]

[url=https://github.com/jrpereira/ModCoreTemplates/blob/main/docs/README.md]Full README and installation details[/url]
[url=https://github.com/jrpereira/ModCoreTemplates/blob/main/docs/DEVELOPERS.md]Developer guide[/url]
[url=https://github.com/jrpereira/ModCoreTemplates/tree/main/examples/wheel-nudge]Runnable Wheel Nudge example[/url]
[url=https://github.com/jrpereira/ModCoreTemplates/blob/main/docs/MENUS.md]Template menus[/url]
[url=https://github.com/jrpereira/ModCoreTemplates/blob/main/docs/LIFECYCLE-DRAFT.md]Lifecycle reference[/url]
[url=https://github.com/jrpereira/ModCoreTemplates/blob/main/docs/OBJECT-SOURCE.md]Object discovery and limits[/url]
[url=https://github.com/jrpereira/ModCoreTemplates/blob/main/docs/CHANGELOG.md]Changelog[/url]
