# Settings Example settings

Settings Example does not ship a `mod_settings.ini`. Compatibility with `mod_settings.ini` is implemented by ModCore Templates.

Templates are reusable components. A module that uses a template gains the template's settings and shows them as its own. When the game starts, ModCore Templates collects the settings of every installed template and ModCore Settings builds the menu pages from them, so the pages always match what is installed.

Change these settings in the mod menu and press Apply. Each template below names the `config.ini` that keeps its values, in the `[Templates]` section, with the keys and numbers listed. A saved value that is not valid falls back to its default.

## Templates in this module

### Example Cue

Exercise every row the settings reference describes.

- **Category:** NPC Attacks. The settings appear on this module's page.
- **Turn on:** set Enabled (`MCT_ExampleCue_Enabled`) to Yes (`1`).
- **Saved in:** `SettingsExample/config.ini`, section `[Templates]`.

#### Variations

| Setting | Options | Default | Key |
|---|---|---|---|
| Style | Swap (`0`), Stack (`1`) | Swap | `MCT_ExampleCue_Style` |

#### Bars

| Setting | Options | Default | Key |
|---|---|---|---|
| Orientation | Vertical (`5`), Horizontal (`7`) | Horizontal | `MCT_ExampleCue_BarsA` |
| Key Indicators<br>*Shown when Orientation is Horizontal.* | Above (`0`), Below (`1`) | Above | `MCT_ExampleCue_BarsKH` |
| Key Indicators<br>*Shown when Orientation is Vertical. Named Side Key Indicators when Orientation is Vertical.* | Left (`0`), Right (`1`) | Left | `MCT_ExampleCue_BarsKV` |

#### Stacking

Shown when Style is Stack.

| Setting | Options | Default | Key |
|---|---|---|---|
| Gap | 0px to 40px, in steps of 4 | 8px | `MCT_ExampleCue_StackGap` |

| Setting | Options | Default | Key |
|---|---|---|---|
| Opacity | 0% to 100%, in steps of 1 | 100% | `MCT_ExampleCue_Opacity` |
