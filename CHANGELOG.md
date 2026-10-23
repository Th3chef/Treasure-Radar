# Changelog

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
