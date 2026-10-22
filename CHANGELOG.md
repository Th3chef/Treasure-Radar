# Changelog

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
