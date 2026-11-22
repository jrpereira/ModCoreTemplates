# Object discovery and limits

MCT finds the objects a category declares and hands the ready ones to its templates.
Templates never search for widgets themselves. MCT does not scan installed mods for
templates: providers register them with `mc.registerTemplate`.

## Matching

- A class selector matches instances of that class and its subclasses.
- A widget selector inside a HUD blueprint matches a widget with the declared class and
  name that belongs to exactly the declared blueprint class. Class defaults and
  same-named widgets in other blueprints never match.
- A blueprint class the game has not loaded yet has no instances to match; they are
  found once the game creates them.
- `within` restricts a match to descendants of another selector.

## When objects are ready

- Only categories with at least one registered template are watched.
- A HUD widget is ready once it is shown. A template does not attach in the main menu
  or on a loading screen.
- A widget removed from its panel detaches its templates; added back, they attach
  again.
- On a map change or save load, the old world's attachments are forgotten without a
  detach callback, and templates attach to the new HUD once it is shown.

## Keeping objects

Use the objects passed to a callback during that callback only. To keep one, hold it
with `MC.hold(object)` and read it back with `MC.get(handle)`, which returns nil once
the object is gone. Calling an object kept from an earlier callback after a save load
can crash the game, and `pcall` does not catch it.

MCT requires UE4SSLuaEventBridge 1.3.0 or newer. Without its weak handles or its
loop-start barrier, MCT does not start; without its function hooks, only
`MC_NPCAttackIndicator` is unavailable. If the bridge reports its lifetime service
unavailable, MCT attaches no templates and logs the bridge's reason once.

## Limits

- Some changes the game makes to its widgets are not reported to MCT, so a template
  may not follow every change of a widget's parent at once.
- An object that dies is noticed at the next lifecycle event, not immediately.
- Offline tests cannot show in-game behaviour; check your templates in game.
