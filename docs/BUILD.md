# Build guide

## Requirements

Use Lua 5.4 and Python 3. MCT is Lua-only; no compilation is needed. Run commands
from this repository's root. In-game use requires the dependencies in the
[README](README.md).

## Offline tests

Run the tests:

```sh
python3 tools/run-tests.py --lua lua5.4
```

To also check the menus against an installed Dawnwalker Mod Menu and ModCore Settings:

```sh
python3 tools/run-tests.py --lua lua5.4 \
  --dmm-choices "/path/to/DawnwalkerModMenu/Scripts/choices.lua" \
  --presentation "/path/to/ModCoreSettings/Scripts/presentation.lua"
```

Supply both paths together, or set `MCT_DMM_CHOICES` and `MCT_PRESENTATION`. Without
them these checks are skipped.

## In-game checks

Restart after changing Lua. Check repeated Apply, template switching, loading saves
and changing maps, and restoration of every property the template changes. The tests
do not show in-game behaviour.
