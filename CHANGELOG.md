# Changelog

## 0.7.1

- Fixed: Rare Samples showed red in game, close to the enemies' red. They're orange now, and Super Samples show pink
  instead of purple.
- The options menu (F9) groups Treasure Radar's rows under headings (Radar, World markers, Loot, Enemies, Friendlies,
  Keys, Weapons), with a hint on the less obvious rows. The headings need Chef Shared Loader 1.4.0 or newer; older
  versions show the same rows without them.
- The radar and the ledger hide while you ride the extraction shuttle out.
- Enemies now come before the enemy structures, and Double-Tap Tab To Hide sits with the keys, in the options menu and
  in your mod manager.

## 0.7.0

- New: **Enemies** (optional): enemies inside the radar's range as red dots (medium ones bigger), heavies with the
  game's skull. Pick All, Medium and heavy, or Heavy only. A killed enemy drops off; for many kinds right as it dies,
  and the radar learns more kinds' deaths as you play. Tank wrecks drop off too. Some enemies may linger on the radar
  for about 10 seconds after they die (Fleshmobs, Devastators, Berserkers and Harvesters among them).
- New: **SEAF Troopers and Civilians** (optional) as blue dots, and **Squadmates** (optional) as green dots, inside the
  radar's range. Each drops off when it dies; your own Helldiver is the radar's middle, never a dot.
- New: **Radar Position**: beside the map (as before), any corner, or mid height on either side. The options menu (F9)
  also has sliders to move it a little from there, and the ledger moves to the radar's other side when the radar is on
  the left.
- New: pick which support weapons show, each with its own row in the options menu (F9).
- Weapons SEAF troopers carry now count as carried, like a Helldiver's, instead of showing as lying on the ground.
- World Markers can now also reach 5, 10 or 15 m.
- The loot kinds now use the game's own icons.
- Fixed: fabricators destroyed before you joined a mission stayed on the radar.
- The options menu (F9) is reorganized: the look first, then what shows, then the keys, with the weapons last. The
  options in your mod manager follow the same order.
- A shorter log: treasure_radar.log keeps your settings, where the radar sits and one summary line per mission.

## 0.6.0

- **Now runs on the standalone Chef Shared Loader (1.0.0 or newer), which has to be installed as its own mod.** Treasure
  Radar no longer carries its own copy of the loader. Every setting can now be changed in game in its options menu
  (F9): radar, ledger, size, range, rotate, opacity, animation, world markers, double-tap Tab, each kind, and the keys
  (bound by pressing one).
- Its log is treasure_radar.log in %APPDATA%\Arrowhead\Helldivers2 (the game's own folder), next to the loader's
  chef_loader.log (start, errors and timings). treasure_radar_state.txt and treasure_radar_trace.txt aren't used
  anymore (the loader's crash guard replaces them).
- The radar now sits just left of where the game's map opens, level with it, instead of under it: the open map no
  longer covers it (and below native Render Scale it no longer draws over the map).
- New: **Weapons** (optional): support weapons and expendables lying on the ground, each with its own silhouette, on the
  radar and as world markers. Weapons someone holds or carries aren't shown, and neither are spent expendables.
- New: **Enemy Structures** (optional): bot fabricators, Bulk Fabricators, Illuminate warp ships and bug holes in deep
  red, in the ledger too; they drop off once destroyed (bug holes once closed).
- New: **Radar Animation** (ticked by default): untick it for a still radar with every pickup at full strength.
- New: the keys can be picked (Hide Key, Zoom Keys, Markers Key), or bound in game in the options menu.
- The ledger is now a set of tiles, one per kind with its icon and count; a cleared kind dims with a check mark.
- Hold Tab To Hide is now Double-Tap Tab To Hide: tap Tab twice within half a second to hide or show the radar.
- World Markers can reach 200 m or be endless.
- Icons are all about the same size: bigger near you, smaller toward the radar's edge, and zooming changes it.

## 0.5.1

- Fixed: the radar never showed in smaller missions. Any world under 5,000 units counted as the ship, and some missions come in under that; now the mod also looks for the mission's loot (samples, medals, Super Credits, Requisition Slips) to tell a mission from the ship.
- Fixed: on the way out of a mission the ledger could show everything as picked up for a moment.
- Fixed: with a very long mod list (over 513 patch files), the mod could miss its own files.

## 0.5.0

The first Treasure Radar: the successor of Treasure Map, rebuilt for the current game (the Lua 5.1 build) with its own
loader built in.

- A round sonar radar where the game's map opens, with every Super Credit, Medal, Common, Rare and Super Sample,
  Requisition Slip, ammo box, grenade pack and stim pack around you; a sweep turns every 3 seconds and lights each
  pickup up as it passes. Loot farther out sits on the edge, pointing the way.
- Loot Ledger: a pill for each kind with how many are left in the mission.
- World Markers: icons floating over the pickups near you, with how far they are (25, 50 or 100 m).
- Options: Opacity, Size, Range, Rotate With View, and each kind on its own.
- Keys: F7 or holding Tab hides the radar; the numpad's + and - zoom it; F8 hides the world markers.
- Follows your HUD Scale and HUD Edge Offset settings.
- No other loader needed.
