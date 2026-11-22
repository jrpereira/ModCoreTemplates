# Changelog

## v1.10.0

- Requires UE4SS Lua Extensions 1.4.0 and ModCore Settings 1.10.0 or newer.
- Fixed: on a fresh install, ModCore Templates could not save its settings or show its
  menu, leaving the settings of every module using templates (Preymonition, Fangdango)
  greyed out in the mod menu.
- Templates follow a resolution, window size or UI scale change made mid-session: at the
  next loading-screen fade-out or combat start, attached templates are updated with the
  new `params.screen`.
- Template settings are saved per template: `[<Module>.<Template>] <Setting>` in the
  supplying mod's `config.ini` (for example `[Preymonition.Omens] ParryStyle=chevron`),
  the active template of each category under `[Templates]` in MCT's
  `Scripts/cache/config.ini` (for example `PlayerQuickslots=Fangdango_SingleUnderbar`),
  and shared category fields under `[<category>]` there. Templates declare nothing for
  it and menu ids are unchanged. Settings saved by 1.9.1 are not read: template picks
  and template settings start at their defaults once.
- Each value is stored in one place, whichever page shows it: module, category and slot
  pages alike (Fangdango's quickslot bars included). Two modules supplying one category
  share its picker instead of each keeping a copy.
- Quickslots on the Controls tab of the ModCore Settings page and on a merged module page
  (Fangdango): the template picker, labelled Quickslots, is the section's heading, and the
  chosen template's settings follow right under it. The heading repeating the template's
  name (Single Underbar, ...) is gone, and the slot's picker is no longer labelled
  Template.
- Log levels no longer come from `log_level.txt`. With UE4SS Lua Extensions installed
  they are set in the Logs section of the Extensions tab of the ModCore Settings page, or under `[Levels]` in the Log Bridge's `config.ini`; without it,
  WARN and above.
- A category that fails while MCT updates the HUD is reported with its id, and the other
  categories still attach, detach and wake their templates.
- The 256-setting limit applies to each settings page, as in ModCore Settings, not to all
  modules' template settings together.
- Fractional defaults are written to `config.ini` in their short form (`0.1`, not
  `0.10000000000000001`).
- Less work per HUD update.
- Template providers must load after MCT; the developer guide says how UE4SS orders mods.

## v1.9.1

- Template pickers, template toggles, the merged-settings notice and the Templates tab's rows have descriptions.
- The quickslots page in ModCore Controls reads like a module page: the Template picker,
  then the chosen template's settings under its own heading.
- A template picker's side panel describes the selected template, from its `description`.
- Requires ModCore Settings 1.9.0 or newer and UE4SSLuaEventBridge 1.3.0 or newer.
- Live previews on module pages: a template declaring `preview={background=<picture>}`
  gives its module page a preview in ModCore Settings' side panel. While the page is open,
  its selected preview templates attach to it with the page's current values (applied or
  not), stacked by priority as on the HUD, and its category's script plays in a loop; for
  npc.attacks, four attacks (left, right, ahead, behind) and one unblockable attack.
  Preview events carry `preview=true`, and `silent=true` when ModCore Settings' preview
  sound button is Off, or on Auto while none of the template's `preview.sound` settings
  is selected. `preview.sound` names a menu group, a list of groups, or `true` for all of
  the template's settings, its Enabled toggle included. A module whose templates sit in
  another provider's slot gets the preview on its own page.
- Live previews can lend the game's own widgets: a category declaring
  `preview={lend=true, ...}` (player.quickslots does) shows the game's widgets (both
  quickslot wheels) in the preview while its module page is open, with the page's
  selected template attached to them with `preview=true`, and returns them to the HUD on
  close, attaching the applied template again. Lending needs a loaded game. player.quickslots' preview loop moves the focus
  between the wheels every 2 s and gives one consumable slot a Global key for 2 s of each
  8 s loop.
- Template pickers are keyed: the config saves the template's id, such as
  `MCT_Template=Fangdango_SingleUnderbar`, and `None` for no template. Saved template
  choices from 1.7.0 reset to their default once.
- Template pickers can declare keyed choices, `{key=, label=, note=, sound=}`, saved and
  delivered as their keys. A keyed picker may hold `{from='choices/x.lua'}` entries, list
  files in the module's `Scripts/` that ModCore Settings runs each time the menu opens, so
  files added to the mod while the game runs become choices. List files get
  `context.head(path, count)` to read a file's first bytes. The settings reference lists a
  listed picker's choices from the module's folder.
- `defaultEnabled = true` makes a template's Enabled toggle start on.
- MCT publishes `templates.layout.changed` (`{category="player.quickslots"}`) once after
  each pass that may move, show or hide the quickslot key indicators, so ModCore
  Controls can keep its Hold underlines under the keys. Categories opt in with
  `layoutEvent = true`. Templates also receive `controls.slots.global`.
- Template ids are unique within a module: loading prefixes each with its module id
  (`<Module>_<Id>`), so two modules can use the same id. `template.localId` keeps the
  declared id. Two templates whose setting names would match are not both loaded; the
  later provider file is rejected.
- `Scripts/cache/identity-catalog.lua` is no longer used and can be deleted.
- `MC_NPCAttackIndicator` needs UE4SSLuaEventBridge 1.3.0; with an older bridge it logs
  that it is unavailable.
- An Apply updates only the templates whose effective settings changed; the others in
  the same category stay attached as they are. A template's overlays no longer move above
  higher-priority layers, such as the quickslot wheels, when its settings change.
- A config file saved with a UTF-8 byte order mark keeps its first setting.
- A registered template file outside a mod's `Scripts` folder, such as one in
  `Scripts/templates/`, is reported as a registration error and skipped; other templates
  still load. Before, one such file stopped MCT from starting.
- A HUD widget removed and added back no longer leaves its templates detached.
- Quickslot templates attach at most 6 seconds after the HUD appears.
- Logged errors name the template and provider file they are about, such as
  `attach (Fangdango_Wheels): callback returned false`; `MCTOnError` receives them as
  `template` and `provider`.
- When MCT fails to start, it logs one CRITICAL line and closes template registration,
  so providers that load later are told registration is not open.
- Faster attach, update and layout passes.

## v1.7.0

- Requires ModCore Settings 1.6.0.
- `MC_NPCAttackIndicator` `arrow`, `critical` and `unblockable` (shown) events may carry
  `stub`: the attacking enemy's `DogwoodAIStub` path; a `critical` carries its arrow's
  stub. `stub` is nil when the attacker cannot be told. Requires UE4SS Lua Event
  Bridge 1.2.0. Consumers that ignore `stub` see no change.
- Quickslot templates leave the game's quickslot wheels as they found them on detach.
- Targets can save and restore `color`, a widget's own colour and opacity
  (`ColorAndOpacity`), which tints everything the widget draws.
- Created objects declare `adopt`, a list of objects they take in as children (with
  `adoptLayout` and `adoptOpacity`), replacing `reparent`, `destination`,
  `reparentLayout` and `reparentOpacity`.
- A category's templates show on the settings page in the order their module registers
  them (`MC.registerTemplate`), instead of by id. Priority does not affect this order.
- Created objects that share a parent stack in template order, priority then id, as a
  full attach leaves them. A template enabled while others are already shown slots its
  layers in beneath those that come after it, instead of on top of all of them.
- Fixed a visible stutter on the first hit in combat with a quickslot template enabled.
- Less work checking HUD widgets.

## v1.6.0

- Template fields declare what they hold and how they show, as ModCore Settings menu data
  does: `type` (`enum`, `integer` or `range`, inferred from `values` when left out),
  `widget` (`picker`, `tabs`, `cycler` or `switch` for an enum) and `style` (`title`,
  `category` or `notice`). `tab=true` becomes `widget='tabs'`; a menu group's `heading=false`
  becomes `style='none'`; `level` is removed. Generated menu data uses the same keys.
- Range fields: `type='range'`, `values={min=,max=,step=,suffix=,delta=}` and
  `default={low, high}`. `min` and `max` are edges or per-marker pairs, `delta` bounds
  `high-low`. Saved in the config as `<low>|<high>` and given to the template as
  `{low, high}`; a saved value the range cannot hold is replaced with the default. Category settings and slot categories take no range.
- Requires ModCore Settings 1.5.0. `tools/settings_reference.lua` describes ranges.

## v1.5.0

- Requires ModCore Settings 1.4.0 or later, for module ids, on/off switches and subgroups.
- Category `single` is replaced by template `uniqueBy`. `uniqueBy='category'` allows
  one enabled template of that kind per category, as `single` did; `uniqueBy='priority'`
  allows one per priority within the category. Enabling a template detaches the other
  one in its group first; templates without `uniqueBy` attach alongside. Category-unique
  templates share the Template picker, each priority gets its own picker, and the rest
  get Enabled toggles, so one category can have all three. A category that declares
  `uniqueBy` is rejected. Quickslots templates set `uniqueBy='category'`.
- Templates declare `id` and `label` in place of `name`. `id` is required (a letter,
  then letters, digits, `_` or `.`), is unique across modules and names the template's
  settings; `label` is what the menu and the Templates page show, defaulting to `id`.
  MCT no longer derives an id from the category and name.
- Generated setting ids name the module, then the template: `MCT_<Module>_<Id>_...`,
  such as `MCT_Fangdango_Wheels_Enabled`, where `<Module>` is the module id ModCore
  Settings gives the mod folder, else the folder name. Templates in a Template picker
  are named this way too.
- A template's Enabled toggle is now its heading: one on/off row named for the
  template, reading Disabled or Enabled, with its settings indented beneath. In a
  slot it stays a plain row named for the template.
- Under that heading the template's own groups are subgroups: headed in ModCore Settings'
  smaller subgroup style, without a rule, their rows indented a step further.

## v1.4.2

- Requires UE4SSLuaEventBridge 1.2.0 or later. Requirements follow minor versions
  now, so ModCore Settings 1.3.0 or later are enough. No change to templates or events.

## v1.4.1

- Requires ModCore Settings 1.3.1 or later. No change to templates or events.

## v1.4.0

- `MC_NPCAttackIndicator` follows the indicator's own state changes. `critical` is the
  game's parry window. Events arrive about one frame after the game's change;
  `indicator` is still live during the event.
- `early` is gone: the game's early warning arrives in the same frame as the attack's
  `arrow`. `resolve` reasons are `sword` and `hidden`; `dark` is gone.
- Requires UE4SSLuaEventBridge 1.1.0 or later (API 7, function hooks). Without its
  Blueprint hooks, `MC_NPCAttackIndicator` stays off and MCT logs why.

## v1.3.1

- Requires ModCore Settings 1.3.0 or later, which reads the `conditions` and choice sounds
  that MCT 1.3.0 writes into menu data.

## v1.3.0

- Emits `MC_NPCAttackIndicator`: each change of the game's combat target indicator
  reaches the awake templates of `npc.attacks` as their `update` event, in the frame
  the game shows it.
  Each event has a `kind`: `arrow` and `critical` (with `direction`, 1 top, 2 bottom,
  3 left, 4 right), `resolve` (`reason` sword, dark or hidden), `unblockable`
  (`active`) and `early` (the game's early warning, with `direction`, `unblockable`
  and `attacker`), plus the indicator's `path` and, for the call only, the live
  `indicator`.
- Categories may name an update event in `hooks.update`; its awake templates receive
  it as `update(params, event)`.
- Templates may declare a numeric `priority`. Within a category, templates attach, wake,
  sleep and receive events in priority order, lowest first, then by id; a template
  without one comes after those with one.
- `tools/settings_reference.lua` writes a template module's `docs/SETTINGS.md`, listing
  each template's settings with their options, defaults and saved keys, and a
  `MOD_SETTINGS.txt` that points players to it in place of a `mod_settings.ini`.
  `--check` fails when either is out of date.
- Template `conditions` take ModCore Settings' menu-data shapes: `visible={field=,values=,
  playerExists=}`, `label={field=,values={[value]='text'}}` (a key may list values) and `dim`.
  `match` and `text` are gone.
- A picker choice may be `{label=,note=,sound=}`: a note under it, and a sound played when the
  row changes to it.
- Without category pages, MCT's entry in the mod list links to the Templates tab.

## v1.2.0

- Requires ModCore Settings 1.2.0 or later, whose Templates tab holds the template list.
- Category definitions name their identity with `id` instead of `name`, like templates
  and settings; `name` is no longer read.
- The list of loaded templates moves to ModCore Settings' Templates tab, so MCT no longer
  has an entry of its own in the mod list unless category pages need one. Templates are grouped by
  the module supplying them, with a subgroup per category, and keep those groups in the
  slot; each template reads `Active` or stays blank. The list no longer opens with a link to
  choose the quickslot template.
- Provider fields take `heading=true` for the title-row picker instead of `level=1`;
  `level` now takes 0 or 2–6. Generated menu data marks title-row pickers the same way.
- Edits to `Scripts/cache/config.ini` keep each line's spacing, comments and line endings.
- Until ModCore Controls reports a focused group, templates see no focus (`group={}`).

## v1.1.0

- Requires ModCore Settings 1.1.0 or later.
- Less work while the game changes its HUD.
- Startup no longer opens a command window (cmd.exe) several times.
- A category whose wake signal is unavailable no longer fails when a different sleep
  signal fires.
- In categories that allow several templates, such as Player Notifications, each
  template's toggle now reads `Enabled` under a heading that names the template,
  and is saved as `MCT_<Template>_Enabled`. The former
  `MCT_CategorySeparator_<Template>` key is no longer read; set the toggle again.
- Faster startup with many template providers. A file that conflicts with an earlier
  one is still rejected on its own.
- Settings from builds before the first release are no longer carried over, and
  leftover `mod_settings.ini` and `Scripts/cache/menu-pages.lua` files are ignored.
- ModCore Settings builds MCT's pages. Requires the ModCore Settings build with menu
  data.
- A template's module is the mod folder holding its provider file. ModCore Settings
  names the module, gives its page the module's author, version and icon, and lists it
  as a ModCore module from its `mod.json` group. Template choice notes and Templates
  page groups show that name.
- The aggregate page no longer puts a template picker in its title row.
- Template fields no longer accept `tabNavigation`, which had no effect.

## v1.0.2

- Fix a crash when loading a save from a running game.
- Require UE4SSLuaEventBridge 1.0.12 (API 6, weak handles). When the bridge's lifetime
  service is unavailable, MCT attaches no templates and logs the bridge's reason once.
- `MC.hold`, `MC.get` and `MC.release` let templates keep a widget past a
  callback, for example in `onCleanup`, which also runs after world teardown.
- Fix a quickslot bar sometimes keeping the game's layout after loading a save. A
  category can now declare `attachDelay`: a new HUD attaches once it has been quiet
  for that long (2 seconds for quickslots), or as soon as the loading screen finishes
  fading out.
- Fix providers failing at launch with "MCT template registration is not open".

## v1.0.1

- Template fields may declare `conditions`: `visible = {field, match}` shows a row
  only while a picker in the same template holds a matching value, and
  `label = {field, match, text}` swaps its label. Rows hide and relabel live,
  including on slot pages. Hidden values are kept and still delivered to
  templates.
- Release packages include `enabled.txt`, so the mod is enabled when installed.
- Log at levels TRACE, DEBUG, INFO, WARN, ERROR and CRITICAL, writing WARN and above
  by default; `log_level.txt` in the mod folder sets the level. Messages use the
  `[ModCoreTemplates]` prefix instead of `[MCT]`.
- Configuration never prevents startup: an invalid saved value, such as a
  selected template whose provider was removed, is replaced with its default; a
  repeated key or section keeps its first value; a config that cannot be prepared
  or read is reported and its settings run on their defaults.
- Templates attach to the new HUD after a map change once it is shown.
- Release packages carry the documentation at the mod root, and `mod.json` declares
  UE4SSLuaEventBridge and ModCoreSettings.
- A category may declare `slot = {provider=..., slot=...}` to show its Template
  picker and its templates' settings in another mod's menu slot. `player.quickslots`
  now appears in ModCore Controls' Visuals section (`controls:visuals`), and its
  templates leave their module pages. Each row shows only while its template (or
  variation) is selected. Values are stored in MCT's central config. A module whose
  templates all moved keeps its own page over the same settings and storage, headed
  by a notice that they were merged into Controls, with a button that opens the slot.
  Requires ModCoreSettings with slot rows and slot-address page links.

- No control group has focus at startup: `state.controls.group` stays empty until
  ModCore Controls reports one, instead of assuming abilities (group 1).
- Registered template files can `require` helper modules from their own folder.
- Control state changes no longer rebuild templates. Event callbacks run once per
  live attachment as `(params, event, objects)`, where `params` matches attach's,
  and adjust it in place; templates that relied on the reapply must move that work
  into the callback.
- Created objects no longer take `content` or `clickRelay`.
- A malformed or failing provider file is reported and skipped at startup; loaded hooks
  can register cleanup for their side effects.
- Provider `mod.json` files may leave out author and version.
- Add `mc.registerTemplate(name)` registration, relative to the calling file, and the
  optional one-shot `template.loaded()` initializer.
- Fix a template picker repeatedly reopening the page it links to.
- Module-target template settings are stored in that module's `config.ini`.
- Templates are registered by their providers instead of found by scanning installed
  mods; provider entries may sit directly under `Scripts/`.
- Rename the installed mod folder to `3_ModCore_Templates`.

## 0.0.17 to 0.0.20

- Development builds before the first release.
