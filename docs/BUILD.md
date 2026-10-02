# Build guide

For the fresh `Scripts/mc/` runtime, use the [menu and lifecycle test command](MENUS.md#tests).
The previous runtime and its original test setup remain available in Git history.

- [Requirements](#requirements)
- [Generated menus](#generated-menus)
- [Offline tests](#offline-tests)
- [Validation limits](#validation-limits)

## Requirements

- Lua 5.4 for source checks and offline tests.
- Python 3 for the documented tooling.
- A compatible UE4SS/Dawnwalker installation for live integration checks.

The installed runtime is Lua-only.
Run the commands below from the repository root.

## Generated menus

MCT generates current category and module pages during startup, after loading
registered templates, and publishes them through ModCoreSettings. Preserve the identity catalog between runs
so settings keep their IDs. Edit template declarations rather than generated pages.

## Offline tests

The [test runner](../tools/run-tests.py) checks runtime Lua syntax and executes
the test suites from the repository root:

```sh
python3 tools/run-tests.py --lua lua5.4
```

MCT reaches the menu through ModCoreSettings, so the suites need no DMM
installation. To also check generated manifests against the real DMM parser and
Settings presentation, point both variables at compatible local installations:

```sh
export MCT_DMM_CHOICES="/path/to/ue4ss/Mods/DawnwalkerModMenu/Scripts/choices.lua"
export MCT_PRESENTATION="/path/to/ModCoreSettings/Scripts/presentation.lua"
python3 tools/run-tests.py --lua lua5.4
```

The runner verifies Lua 5.4 and uses a temporary directory for generated test data.
It runs the current suites in `tests/mc/`.

## Validation limits

Fixtures cover registration, metadata validation, generated menus, category
events, target readiness, and lifecycle transitions. They do not establish live
Unreal object validity, rendering, or garbage-collection behavior.

Validate repeated Apply, template switching, load/map changes, late events, and
restoration of the template's own mutations. A clean fixture is useful evidence;
the game still gets a vote.
