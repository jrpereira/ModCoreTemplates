[b]ModCore Templates[/b]

[center][b]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/b]
[size=4][b]Tested for The Blood of Dawnwalker 1.2[/b][/size]
[b]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/b][/center]

ModCore Templates (MCT) provides an environment for modifying Dawnwalker's UI with Lua templates. Declare the objects and properties you want to change; MCT finds ready targets, manages their lifecycle and generates settings menus.

[b]Features and benefits[/b]

For players:
[list]
[*]Pick a template, or None, for each category (such as the quickslots or the attack indicators) on the module's page; the side panel describes the selected template.
[*]Live previews: module pages show a looping preview in ModCore Settings' side panel with the page's current values, applied or not. Quickslot templates preview on the game's own wheels while a game is loaded.
[*]Settings are saved per template, so switching templates and back keeps what you set.
[*]Resolution, window size and UI scale changes made mid-session are followed at the next loading screen or combat start.
[*]The Quickslots template picker heads the Quickslots section of the Controls tab, with the chosen template's settings right under it.
[/list]

For mod authors:
[list]
[*]Declare objects of interest and let MCT resolve their dependencies and supply the requested objects.
[*]MCT waits for ready targets, checks they are still alive and attaches again as they change. Use supplied objects during callbacks instead of retaining widgets.
[*]Managed templates automatically capture declared properties and restore them on rebuild or detachment, including when selecting None.
[*]Focus on the visual change in an attach callback; MCT restores and reapplies it after committed settings changes.
[*]Declare settings, variations and conditional fields alongside the template; MCT handles generated menus, saved values and Apply. Pickers can list choices from files in your mod.
[*]Place settings on module/category pages or in shared areas such as the Quickslots section of the Controls tab.
[*]Declare a preview with a background picture and the settings that play sound; MCT runs the category's preview loop on your page.
[*]Declare event reactions; active templates receive them on the game thread.
[*]MCT announces when the quickslot key indicators may have moved, shown or hidden, so ModCore Controls keeps its key outlines under the keys.
[/list]

[b]Requirements and installation[/b]

Requires The Blood of Dawnwalker, UE4SS with Lua 5.4, UE4SSLuaEventBridge 1.3.0 or newer (API 7: weak handles and function hooks), and ModCore Settings 1.9.0 or newer with Dawnwalker Mod Menu. Install and enable under Mods/3_ModCore_Templates and disable the former _UE4SSTemplatingEngine installation. Fully restart after changing Lua files. ModCore Controls supplies the Controls tab whose Quickslots section hosts quickslot template settings.

Preserve Scripts/cache/config.ini and template-provider config.ini files when updating. Automatic restoration covers declared properties on managed templates. If the bridge's lifetime service is unavailable, MCT attaches no templates and logs the reason once.

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
