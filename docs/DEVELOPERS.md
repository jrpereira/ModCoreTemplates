# Developer guide

ModCoreTemplates provides the `mc.*` Lua runtime and generates menu identities
with the `MCT_` prefix.

For the current template declaration, target, lifecycle, and menu contracts,
use [Lifecycle draft](LIFECYCLE-DRAFT.md), [Template menus](MENUS.md), and
[Object source](OBJECT-SOURCE.md).

ModCoreControls owns native quickslot input and its `mcc.*` API.
ModCoreTemplates owns visual template selection and lifecycle. Enabled modules
declare managed templates in their own `Scripts/` directory and register their
entry from UE4SS `Scripts/main.lua`:

```lua
local M = require('mc')
M.addTemplate('layout') -- registers sibling mc_layout.lua
```

The public helper registers only the sibling path with the MCT instance already
in scope. The template owns `category`; MCT discovers `module`, `author`, and
`version` from the provider's `mod.json`, loads the template in its own state at
the startup barrier, and rejects conflicting duplicated metadata.
ModCoreTemplates does not scan modules.
