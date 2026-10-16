# Changelog

## v1.4.1

- Requires ModCore Settings 1.3.1 or later. No change to templates or events.

## v1.4.0

- `MC_NPCAttackIndicator` now follows the indicator's own state change
  (`OnObservedStubIconTypeChanged`) through UE4SSLuaEventBridge function hooks, in
  place of every atlas image's styling call. `critical` is the game's parry window,
  not a second styling. Events arrive on the next engine tick, about one frame after
  the game's change, not inside its call; `indicator` is still live during the event.
- `early` is gone: the game's early warning arrives in the same frame as the attack's
  `arrow`. `resolve` reasons are `sword` and `hidden`; `dark` is gone.
- Requires UE4SSLuaEventBridge 1.1.0 or later (API 7, function hooks). Without its
  Blueprint hooks, `MC_NPCAttackIndicator` stays off and MCT logs why.

## v1.3.1

- Requires ModCore Settings 1.3.0 or later, which reads the `conditions` and choice sounds
  that MCT 1.3.0 writes into menu data.

## v1.3.0

- Emits `MC_NPCAttackIndicator`: MCT watches the game's combat target indicator and
  delivers each change to the awake templates of `npc.attacks` as their `update`
  event, inside the game's call, so a cue changes in the frame the game shows it.
  Each event has a `kind`: `arrow` and `critical` (with `direction`, 1 top, 2 bottom,
  3 left, 4 right), `resolve` (`reason` sword, dark or hidden), `unblockable`
  (`active`) and `early` (the game's early warning, with `direction`, `unblockable`
  and `attacker`), plus the indicator's `path` and, for the call only, the live
  `indicator`. The indicator is hooked only while such a template is awake.
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
- Generated menu data puts row and group rules under `conditions`, as ModCore Settings 1.2.0
  reads them; the vendored menu client is version 7.
- Without category pages, MCT's entry in the mod list links to the Templates tab.

## v1.2.0

- Requires ModCore Settings 1.2.0 or later, whose Templates tab holds the template list.
- Category definitions name their identity with `id` instead of `name`, like templates
  and settings; `name` is no longer read.
- The list of loaded templates moves to ModCore Settings' Templates tab: MCT publishes it
  as a hidden page whose rows fill the `settings:templates` slot, so MCT no longer has an
  entry of its own in the mod list unless category pages need one. Templates are grouped by
  the module supplying them, with a subgroup per category, and keep those groups in the
  slot; each template reads `Active` or stays blank. The list no longer opens with a link to
  choose the quickslot template.
- Provider fields take `heading=true` for the title-row picker instead of `level=1`;
  `level` now takes 0 or 2–6. Generated menu data marks title-row pickers the same way.
- Files are read and replaced through `safe_file.lua`, shared with the other ModCore modules
  (same `.new`/`.old` protocol as before). Reading a file that exists but cannot be read now
  raises instead of looking like a missing file.
- `Scripts/cache/config.ini` is read and edited through the shared `mc_ini.lua`: repairs and
  added settings keep each line's spacing, comment and line endings.
- Until ModCore Controls reports a focused group, templates see no focus (`group={}`), as
  MCT's own state already assumed.

## v1.1.0

- Requires ModCore Settings 1.1.0 or later.
- Widget hooks share one known-root check per game-thread dispatch. Before, every
  unrelated `RemoveChild`, `ClearChildren`, `RemoveFromParent` or viewport call in the
  game read every known root.
- Existing `Scripts/categories` and `Scripts/cache` folders are found with a probe
  file. Startup no longer starts a shell (cmd.exe on Windows) several times per boot.
- The loading screen's fade-out settles pending attach delays on the game thread
  after the hooked call returns, instead of attaching templates inside it.
- A category whose wake signal is unavailable no longer fails its reconcile when a
  different sleep signal fires.
- In categories that allow several templates, such as Player Notifications, each
  template's toggle now reads `Enabled` under a heading that names the template,
  and is saved as `MCT_<Template>_Enabled`. The former
  `MCT_CategorySeparator_<Template>` key is no longer read; set the toggle again.
- Faster startup with many template providers: all provider files are validated
  together once, instead of rebuilding the full menu after each file. A file that
  conflicts with an earlier one is still rejected on its own.
- Lifecycle trace details are no longer computed when the log level is above TRACE.
- Removed migrations from before the first release: slot values are no longer copied
  from module configs, retired slot settings are no longer cleaned, the central config
  no longer seeds new module configs, and leftover `mod_settings.ini`,
  `Scripts/cache/menu-pages.lua`, `.mc.bak` and `.mc.tmp` files are no longer
  removed or recovered.
- MCT publishes its pages as ModCoreSettings menu data instead of DMM manifests;
  ModCoreSettings builds them. The Templates page hooks return menu data too.
  Requires the ModCoreSettings build with menu data (contract 4).
- A template's module is the mod folder holding its provider file. MCT no longer
  reads `mod.json`: ModCoreSettings names the module and gives its page the
  module's author, version and icon, and lists it as a ModCore module from its
  `mod.json` group. Template choice notes and Templates page groups show the name
  ModCoreSettings gives the folder.
- The aggregate page no longer puts a template picker in its title row.
- Template fields no longer accept `tabNavigation`, which had no effect.

## v1.0.2

- Fix a crash when loading a save from a running game. MCT kept UE4SS object
  wrappers across garbage collection and later called them; UE4SS `IsValid`
  reads the freed object. Every object MCT keeps past one call, including known
  HUD roots, references, created and moved widgets, saved parents and cached
  slots, is now a UE4SSLuaEventBridge weak handle whose native lifetime is
  checked first.
- Require UE4SSLuaEventBridge 1.0.12 (API 6, weak handles). The address-identity
  fallback is gone: when the bridge's lifetime service is unavailable, MCT keeps
  nothing, attaches nothing and logs the bridge's reason once.
- `MC.hold`, `MC.get` and `MC.release` let templates keep a widget past a
  callback, for example in `onCleanup`, which also runs after world teardown.
- Wait for a new HUD to settle before attaching. A loading save creates the HUD with
  empty quickslot wheels and fills them a moment later; MCT could attach in between,
  so a quickslot bar laid out empty slots and kept the native layout. A category can
  now declare `attachDelay`: a newly found root stays hidden and attaches once no
  lifecycle event has reached it for that long (2 seconds for quickslots), or as
  soon as the loading screen finishes fading out.
- Fix providers failing at launch with "MCT template registration is not open".
  UE4SS starts Lua mods while the game thread is already ticking, so the first
  game-thread callback could close registration before later mods loaded. The
  startup barrier now waits for the bridge's loop start, which fires after every
  Lua mod has started, and then continues on the game thread.

## v1.0.1

- Template fields may declare `conditions`: `visible = {field, match}` shows a row
  only while a picker in the same template holds a matching value, and
  `label = {field, match, text}` swaps its label. Rows hide and relabel live,
  including on slot pages. Hidden values are kept and still delivered to
  templates.
- Release packages include `enabled.txt`, so the mod is enabled when installed.
- Log at levels TRACE, DEBUG, INFO, WARN, ERROR and CRITICAL, writing WARN and above
  by default; `log_level.txt` in the mod folder sets the level. Messages use the
  `[ModCoreTemplates]` prefix instead of `[MCT]`. Falling back to address identity
  when native object lifetimes are unavailable is a TRACE notice.
- Configuration never prevents startup: an invalid saved value, such as a
  selected template whose provider was removed, is rewritten with its default; a
  repeated key or section keeps its first value; a config that cannot be prepared
  or read is reported and its settings run on their defaults.
- Stop registering LoadMap hooks. On a map change the old world's objects become
  invalid and are forgotten; the new HUD is found through its creation
  notification and attaches once shown.
- Move the README and changelog into `docs/`. Release packages are built from
  `release-manifest.json` and publish every document from `docs/` at the mod
  root. `mod.json` reads the version from `VERSION` and declares
  UE4SSLuaEventBridge and ModCoreSettings. GitHub Actions build, test and
  publish the release archive and its checksum from a `release/vX.Y.Z` branch.
- A category may declare `slot = {provider=..., slot=...}` to show its Template
  picker and its templates' settings in another mod's menu slot. `player.quickslots`
  now appears in ModCore Controls' Visuals section (`controls:visuals`), and its
  templates leave their module pages. Each row shows only while its template (or
  variation) is selected. Values are stored in MCT's central config; on first start
  they are copied once from module configs, which are left untouched. A module whose
  templates all moved keeps its own page over the same settings and storage, headed
  by a notice that they were merged into Controls, with a button that opens the slot.
  Requires ModCoreSettings with slot rows and slot-address page links.

- No control group has focus at startup: `state.controls.group` stays empty until
  ModCore Controls reports one, instead of assuming abilities (group 1).
- Registered template files can `require` helper modules from their own folder.
  MCT appends that folder to the search path, after its own modules.
- Control state changes no longer rebuild templates. Event callbacks run once per
  live attachment as `(params, event, objects)`, where `params` matches attach's,
  and adjust it in place; templates that relied on the reapply must move that work
  into the callback.
- Remove the quickslot host buttons: the category baits now move both wheels
  directly into the `actions` canvas. Drop the created-object `content` and
  `clickRelay` fields, which only the hosts used.
- Isolate malformed or throwing provider files during startup, and let loaded
  hooks register cleanup for side effects.
- Retain partial session ownership and retry failed cleanup while reporting the
  original startup error.
- Parse module identity from top-level JSON fields, including surrogate pairs,
  while accepting provider manifests with optional author and version.
- Add caller-relative `mc.registerTemplate(name)` registration, discover provider
  metadata from `mod.json`, and add the one-shot optional `template.loaded()` initializer.
- Load category definitions once and move menu/config/runtime assembly out of bootstrap.
- Tear down the current settings detail page before following a provider link, preventing the activating picker from repeatedly reopening its target.
- Store module-target template settings in that module's `config.ini` instead of ModCoreTemplates, migrating any matching values from the former shared config on first startup.
- Replace installed-module template scanning with explicit provider registration and support provider entries directly under `Scripts/`.
- Rename the installed mod folder to `3_ModCore_Templates`.

## 0.0.20

- Align category and lifecycle tests with visual-only quickslot ownership.

- Refine template metadata, generated menus, and lifecycle handling.
- Keep wheel mutation and restoration with the consuming template.
- Add focused developer and build guides with project metadata.

- Use the ModCoreTemplates provider and `_ModCore_Templates` installation folder, retaining the `ket.*` API and `KET_` setting IDs.
- Keep visual template selection separate from ModCoreControls input handling.
- Preserve `tabNavigation=1` on navigation tabs and expose their generated IDs through `definition.navigation` without a config binding.

## 0.0.19 - 2026-09-23

- Load category objects directly at boot and generate category and template menus with shared quickslot controls.
- Merge category and template settings before delivering them to lifecycle hooks.
- Generate Advanced quickslot group bindings and require group selection before slot activation.
- Support template fields whose visibility follows another picker, and place a single template picker in the page header.
- Retry Enhanced Input attachment when the pawn input component is created or a map finishes loading.

## 0.0.18 - 2026-09-22

- Remove the obsolete `collection` field and use category/name identities for templates.
- Let a template's `single` value override category metadata, with category metadata as the fallback when omitted.
- Rebuild generated DMM category pages idempotently after loading a game.
- Add heading-free provider groups and align the Input Method tabs with the template picker.
- Give the first group activation binding `Tap | Hold | Default` (`0|2|-1`) while preserving sustain-style `Tap | Hold` (`0|2`) for later groups and `0|1` for regular slots.
- Require boolean `settings.enabled`; bundled templates default to `true`, and TE skips lifecycle methods while disabled.

- Validate category event interests and route declared events through service-first template callbacks.
- Retry pending attachments when a declared category event arrives.
- Validate committed provider settings before template attachment.
- Name template declarations `settings` and deliver committed values as `configuration.settings` while preserving persisted setting identities.
- Add `te.widget` helpers for safe UE property reads, transforms, opacity, and slot snapshots.
- Resolve category targets in TE and pass them to `attach`, removing target discovery from template services.
- Add `npc.attacks` and declarative native-class creation events owned and scheduled by TE.
- Add the inert `menu.fixes` template category.
- Split template selection into an aggregate `Templates` DMM page and generated category pages that own each template's detailed controls.
- Add the DMM startup extension that injects generated category pages while keeping their settings rooted in TE's shared `config.ini`.
- Add the `menu.controls` and `menu.templates` template categories.
- Add the `other` category family with the `other.unknown` fallback category.
- Store registered subcategories as `_categories[module][category]`, initialized with `visible`, `count`, and `templates`.
- Add `setCategory(category, values)` for category metadata such as `visible`.
- Track each successfully loaded template in its category's `count` and `templates` fields.

## 0.0.17

- Register individual template files or folders containing Lua templates.
- Validate one template object or nested dense arrays of templates.
- Generate persistent Adaptive Mod Menu controls for `player.quickslots` templates.
- Provide protected, service-first `attach`, `render`, and `detach` lifecycle calls.
- Preserve historical Quickslots setting identifiers across the category rename.
- Recognize the built-in `player.*` and `npc.*` category families.
- Include the menu-test host used while native discovery, input, and visual cutover remain under development.
