# Treasure Radar

![Treasure Radar](media/gallery.png)

https://github.com/user-attachments/assets/b9f28af4-796f-46c3-a233-ee650165ba50

*Every sample, medal, Super Credit, Requisition Slip and supply around you, on a sonar radar beside your map.*

**Download:** `Treasure-Radar-0.6.0.zip` from the [latest release](https://github.com/Th3chef/Treasure-Radar/releases/latest) (not the source code). **Needs [Chef Shared Loader](https://github.com/Th3chef/Chef-Shared-Loader) 1.0.0 or newer**, installed as its own mod.

A round sonar radar sits just left of where the game's map opens (bottom right) and shows the loot and supplies still lying around you, with a ledger of what's left in the mission and markers floating over the pickups near you. Sweep up the loot and restock before extraction instead of running back and forth looking for it. It's the successor of Treasure Map, rebuilt for the current game.

## Features

- **Sonar radar:** Super Credits, Medals, Common, Rare and Super Samples, Requisition Slips, ammo boxes, grenade packs and stim packs around you, each kind in its own color with the game's own pickup icons. A sweep turns every 3 seconds and each pickup lights up as it passes. North is up, with N, E, S and W on the rim, or the radar turns with you (Rotate With View).
- **Beside your map:** the radar sits just left of where the game's map opens, level with it, so the open map never covers it and it never covers the map. It follows your HUD Scale and HUD Edge Offset settings.
- **Loot farther out:** loot beyond the radar's range sits on its edge, pointing the way. Supplies only show inside the range.
- **Piles:** pickups of one kind lying together share one icon, with how many it stands for next to it.
- **Distance at a glance:** every kind's icon is about the same size; near you they're bigger, toward the edge smaller, and zooming the radar changes that with it.
- **Weapons (optional):** support weapons and expendables lying on the ground (a fallen Helldiver's, one set down, an unused drop), each with its own silhouette, on the radar and as world markers. Weapons someone holds or carries, and spent expendables, aren't shown.
- **Loot ledger (optional):** left of the radar, a tile for each kind with its icon and how many are still lying in the mission. It counts down as things are picked up, and a cleared kind dims with a check mark.
- **Enemy structures (optional):** fabricators, Bulk Fabricators and Illuminate warp ships in deep red; they drop off once destroyed. Bug holes too: they drop off once closed.
- **World markers (optional):** each pickup near you gets its icon floating over it in the world, with how far it is (25, 50, 100 or 200 m, or endless; F8 hides or shows them). Pickups lying together share one marker with a count.
- **Up to date:** a pickup near you that's picked up (by you or anyone else) leaves the radar, the markers and the ledger at once; farther away, within 3 seconds.
- **Zoom:** the numpad's + and - step the radar's range from 50 to 500 m; it remembers the last one.
- **Still or animated:** untick Radar Animation for a still radar with every pickup at full strength.
- **Hide it:** F7, or tapping Tab twice quickly, hides or shows the radar and the ledger (a single tap still just opens the map).
- **Your look:** Opacity (100, 75, 50, 25 or 0%: at 0 only the icons and counts are left), Size (Small, Medium or Large) and the radar's Range (75 to 300 m).
- **Pick what you want:** each kind is its own option.
- **Your keys:** pick the Hide Key, Zoom Keys and Markers Key in your mod manager, or bind them in game.
- **Change it in game:** every setting (and the keys) is also in Chef Shared Loader's options menu (F9), applied at once and saved.
- **Light and safe:** it only works in missions, lists the pickups every 3 seconds spread over several frames, pauses that while there's nothing to show, and reads the game without changing anything in it.

## Options

In your mod manager (Arsenal / HD2 Mod Manager), on the mod's row:

- **Treasure Radar (core)**: the radar. Keep this ticked.
- **Loot Ledger**: the tiles left of the radar with how many of each kind are left.
- **Opacity**: 100% (without it), 75, 50, 25 or 0%: how solid the radar's panel and sweep and the ledger's tiles are.
- **Size**: Medium (without it), Small or Large.
- **Rotate With View**: the radar turns with you instead of north up.
- **World Markers**: 50 m (default), 25, 100 or 200 m, or Endless (every pickup, however far).
- **Range**: 150 m (without it), 75, 100, 200, 250 or 300 m.
- **Radar Animation** (ticked by default): the sweep and the pickups lighting up; unticked, a still radar.
- **Double-Tap Tab To Hide** (ticked by default), **Hide Key** (F7), **Zoom Keys** (numpad + and -), **Markers Key** (F8): pick another key or turn one off.
- **Super Credits** (Super Credit blue), **Medals** (medal yellow), **Common Samples** (green), **Rare Samples** (orange), **Super Samples** (pink), **Requisition Slips** (requisition yellow), **Ammo Boxes** (the game's ammo yellow), **Grenade Packs** (olive green), **Stim Packs** (blue), **Weapons** (white silhouettes), **Enemy Structures** (deep red).

**In game:** F7 or double-tap Tab: hide or show the radar and the ledger. Numpad + / -: zoom the radar. F8: hide or show the world markers. F9 (Chef Shared Loader's options menu): every setting above, including the keys and each kind.

## Requirements

- **[Chef Shared Loader](https://github.com/Th3chef/Chef-Shared-Loader) 1.0.0 or newer**, installed and enabled as its own mod. It's the small loader that runs Treasure Radar; without it, Treasure Radar does nothing. (Up to 0.5.1 Treasure Radar carried its own copy of the loader; since 0.6.0 it uses the standalone one.)

## Install / update

1. Mod manager (Arsenal / HD2 Mod Manager): add Chef Shared Loader (1.0.0 or newer) and enable it.
2. Add `Treasure-Radar-0.6.0.zip` and enable it, tick Treasure Radar (core), the kinds you want and any options, then **Purge** and **Deploy**.
3. Updating from 0.5.1 or older: install Chef Shared Loader at the same time. Those versions had the loader built in; 0.6.0 doesn't.
4. Updating from Treasure Map: disable or remove Treasure Map first (it needs the old loaders, which no longer work on the current game).

## Uninstall

Disable it in your mod manager, then Purge and Deploy. Its log, `treasure_radar.log` in `%APPDATA%\Arrowhead\Helldivers2`, can be deleted, and so can `treasure_radar_zoom.txt`, `treasure_radar_state.txt` and `treasure_radar_trace.txt` in `%LOCALAPPDATA%`, left by older versions. Keep Chef Shared Loader if another mod uses it.

## Compatibility

- It runs on Chef Shared Loader, which replaces the game's empty `boot` script. Chef Shared Loader also runs the `boot` script of mods like Stratagem Balls Stay Put and Consistent Vaulting; with any other mod that replaces `boot`, only the one deployed last runs. Everything else, HUD mods included, is fine.
- Only you see the radar, the ledger and the markers. Nobody else needs the mod.
- Reads the game only; it never changes anything in it.
- Made and tested on the October 2026 game version (the Lua 5.1 build).

## Known limitations

- Side objectives and Bile Titan holes aren't shown: nothing the mod can read is known to change when one is done or closed, so they would stay on the radar for the whole mission.
- The radar's spot is measured for HUD Scale 0.75 to 1.25 and any HUD Edge Offset with the default Map Position; with another Map Position it may sit a little off the map.
- Loot shows up once the game has spawned it near you (the list refreshes every 3 seconds).

## How it works

Chef Shared Loader, a small Lua loader installed as its own mod, replaces the game's empty `boot` script, finds Treasure Radar's addon and options in the installed patch files and runs it. Every engine call it makes is guarded: the first time a call is made it leaves a breadcrumb, and if the game ever crashed in it, the next launch skips that call and says so in the log, instead of crashing again. The addon asks the loader for the units of the pickup kinds you picked every 3 seconds (the scan is spread over frames and stops at once when the world changes), works out where each sits relative to your camera, and draws the radar, ledger and markers with the game's own screen drawing, using its own small textures. The radar's spot comes from your HUD settings file.

## Troubleshooting

- Nothing shows: check that Chef Shared Loader (1.0.0 or newer) is installed and enabled, that Treasure Radar (core) and at least one kind are ticked, that you Purged and Deployed, and that no other mod replacing the game's boot script was deployed after Chef Shared Loader. It only shows in missions.
- The radar sits off the map: tell me your resolution and HUD settings (HUD Scale, HUD Edge Offset, Map Position) with a screenshot with the map open.
- Attach both logs to a bug report: *treasure_radar.log* and *chef_loader.log* in `%APPDATA%\Arrowhead\Helldivers2` (type that into the File Explorer address bar and press Enter). treasure_radar.log shows the options you picked, your HUD settings, what Treasure Radar found in each mission and any problems; chef_loader.log shows that it started, any Lua errors and its timings. If the game crashed in Treasure Radar, the next launch switches it off and says so on screen (CHEF_LOADER.LOG) and in chef_loader.log.

## Building from source

See [src/BUILDING.md](src/BUILDING.md).

## Support

If you like my mods, you can support me on [Patreon](https://www.patreon.com/c/Chefboiardee).

## Credits

- The pickup icons are copies of the game's own pickup icons.
- Thanks to plataodomo, whose [Objective Tracker](https://ayakamods.com/mods/objective-tracker.4667/) showed how to tell when an enemy structure is destroyed in plain Lua: reading a bot fabricator's animation state, checking that a unit has an animation state machine before reading its state (a colony fabricator without one crashes the game), and watching a structure's meshes. Ideas only; no code was copied.
- Fonts: Poppins, Anton and Barlow Condensed (SIL Open Font License).

## License

All rights reserved. See [LICENSE](LICENSE).
