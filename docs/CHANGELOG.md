# Changelog

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
