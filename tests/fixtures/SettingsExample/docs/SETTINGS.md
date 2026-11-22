# Settings Example settings

Settings Example has no `mod_settings.ini`: its settings are on its page in the mod menu, grouped by the parts listed below.

Change these settings in the mod menu and press Apply. Each template below names the `config.ini` that keeps its values, in a section of its own named after the module and the template, with the keys and numbers listed. The active template of a category is saved under `[Templates]`. A saved value that is not valid falls back to its default.

## Templates in this module

### Example Cue

Exercise every row the settings reference describes.

- **Category:** NPC Attacks. The settings appear on this module's page.
- **Turn on:** set Example Cue (`[SettingsExample.ExampleCue] Enabled=1`) to Enabled.
- **Saved in:** `SettingsExample/config.ini`, section `[SettingsExample.ExampleCue]`.

#### Variations

| Setting | Options | Default | Key |
|---|---|---|---|
| Style | Swap (`0`), Stack (`1`) | Swap | `Style` |

#### Bars

| Setting | Options | Default | Key |
|---|---|---|---|
| Orientation | Vertical (`5`), Horizontal (`7`) | Horizontal | `BarsA` |
| Key Indicators<br>*Shown when Orientation is Horizontal.* | Above (`0`), Below (`1`) | Above | `BarsKH` |
| Key Indicators<br>*Shown when Orientation is Vertical. Named Side Key Indicators when Orientation is Vertical.* | Left (`0`), Right (`1`) | Left | `BarsKV` |

#### Stacking

Shown when Style is Stack.

| Setting | Options | Default | Key |
|---|---|---|---|
| Gap | 0px to 40px, in steps of 4 | 8px | `StackGap` |

| Setting | Options | Default | Key |
|---|---|---|---|
| Opacity | 0% to 100%, in steps of 1 | 100% | `Opacity` |
