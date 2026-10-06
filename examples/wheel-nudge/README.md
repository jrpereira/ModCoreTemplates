# Wheel Nudge example

A complete managed template that moves the ability wheel by a percentage of the
screen width and height. It uses MCT's `player.quickslots` category.

## Run it

1. Install the dependencies in the [MCT README](../../docs/README.md).
2. Put this example's `mod.json` and `Scripts/` in `Mods/WheelNudge/` and enable
   it through UE4SS (for example, add `enabled.txt`).
3. Restart. `Scripts/main.lua` registers sibling `mc_nudge.lua` before MCT's barrier.
4. Open **Controls → Visuals → Quickslots Visuals**, select **Wheel Nudge**, and Apply.
5. Change Horizontal offset to `10` and Apply. With screen width 1920, this adds
   192 local translation units. Parent scaling can change the visible distance.
6. Select None or another template to restore the original position.

If Controls' slot is unavailable, MCS lists the fallback category page under
ModCore Templates. Wheel Nudge's module page also edits its template values.
Both offsets default to zero. Quickslot slot settings use MCT's central
`Scripts/cache/config.ini`.

## Read the code

[main.lua](Scripts/main.lua) registers the template.
[mc_nudge.lua](Scripts/mc_nudge.lua) declares `abilities` and captures `position`,
then uses `original.abilities.position` as the offset baseline. MCT resolves
the switcher dependency, restores before repeated Apply, and restores on detach.
The template never needs to search for widgets or retain them.

For subscriptions and other cleanup, see the
[lifecycle reference](../../docs/LIFECYCLE-DRAFT.md#managed-callbacks-default).
