# Changelog

- Isolate malformed or throwing provider files during startup, and let loaded
  hooks register cleanup for side effects.
- Retain partial session ownership and retry failed cleanup while reporting the
  original startup error.
- Parse module identity from top-level JSON fields, including surrogate pairs,
  while accepting provider manifests with optional author and version.
- Add caller-relative `mc.addTemplate(name)` registration, discover provider
  metadata from `mod.json`, and add the one-shot optional `template.loaded()` initializer.
- Load category definitions once and move menu/config/runtime assembly out of bootstrap.
- Tear down the current settings detail page before following a provider link, preventing the activating picker from repeatedly reopening its target.
- Store module-target template settings in that module's `config.ini` instead of ModCoreTemplates, migrating any matching values from the former shared config on first startup.
- Replace installed-module template scanning with explicit provider registration and support provider entries directly under `Scripts/`.
- Rename the installed mod folder to `_ModCore_3_Templates`.

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
