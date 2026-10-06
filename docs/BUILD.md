# Build guide

## Requirements

Use Lua 5.4 and Python 3. MCT is Lua-only; no compilation is needed. Run commands
from this repository's root. Live integration requires the dependencies in the
[README](README.md).

## Offline tests

The runner checks runtime syntax and executes every suite in `tests/mc/`:

```sh
python3 tools/run-tests.py --lua lua5.4
```

To also parse generated manifests with the installed DMM parser and MCS presentation:

```sh
python3 tools/run-tests.py --lua lua5.4 \
  --dmm-choices "/path/to/DawnwalkerModMenu/Scripts/choices.lua" \
  --presentation "/path/to/ModCoreSettings/Scripts/presentation.lua"
```

Supply both optional paths together. The equivalent environment variables are
`MCT_DMM_CHOICES` and `MCT_PRESENTATION`. Tests write generated data to a temporary
directory. Edit template declarations, not generated menu files.

## In-game checks

Restart after changing Lua. Check repeated Apply, template switching, load/map
changes, late events and restoration of every property the template changes.
Fixtures cover registration, menus, settings and lifecycle transitions; they do
not establish native rendering, object validity or garbage-collection behavior.
