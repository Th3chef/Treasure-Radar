-- HD2-Addon: mods/chef/treasure_radar
-- Treasure Radar, a Chef Shared Loader addon.
-- A round sonar radar just left of where the game's map opens (bottom right), with an icon for every pickup around me,
-- a ledger of tiles counting what's left of each kind, and markers floating over the pickups near me. Optional: weapons
-- on the ground (each with its own silhouette, picked one by one in the options menu), enemy structures, and on the
-- radar only, inside its range: enemies (all, medium and heavy, or heavy only), SEAF troopers and civilians, and my
-- squadmates.
-- The settings are Arsenal options, and can be changed in game in the loader's options menu (F9).
-- How: the loader lists my kinds' units every 3 s (spread over frames) and I draw everything with its screen drawing.
-- Nothing Lua can read says the map is open, so the radar sits beside it, level with it, where neither covers the
-- other. Its spot follows the game's HUD Scale and HUD Edge Offset (read from the player's settings file).
-- Idle: nothing runs outside a mission; while the radar is hidden and the world markers are off, the unit list pauses.

local chef = ...
-- my log is treasure_radar.log next to the loader's; a loader without own_log keeps my lines in chef_loader.log
if type(chef.own_log) == 'function' then chef.own_log('treasure_radar') end
local M = { version = '0.7.0' }
local floor, sqrt, max, min, atan2, exp, pi = math.floor, math.sqrt, math.max, math.min, math.atan2, math.exp, math.pi

-- Fallback icons, 9 x 9 (X = the kind's color, o = dark outline, . = empty), for when the textures can't be used.
local ICON = {
  coin = { '...ooo...', '.ooXXXoo.', '.oXXXXXo.', 'oXXXXXXXo', 'oXXXoXXXo', 'oXXXXXXXo', '.oXXXXXo.', '.ooXXXoo.', '...ooo...' },
  star = { '....o....', '...oXo...', 'oooXXXooo', 'oXXXXXXXo', '.oXXXXXo.', '..oXXXo..', '.oXXoXXo.', '.oXo.oXo.', '.oo...oo.' },
  vial = { '..ooooo..', '..oXXXo..', '...oXo...', '..oXXXo..', '.oXXXXXo.', '.oXXXXXo.', '.oXXXXXo.', '.oXXXXXo.', '..ooooo..' },
  diamond = { '....o....', '...oXo...', '..oXXXo..', '.oXXXXXo.', 'oXXXXXXXo', '.oXXXXXo.', '..oXXXo..', '...oXo...', '....o....' },
  crystal = { '...ooo...', '..oXXXo..', '.oXXXXXo.', '.oXXoXXo.', '.oXXoXXo.', '.oXXXXXo.', '.oXXXXXo.', '..oXXXo..', '...ooo...' },
  slip = { 'oooooooo.', 'oXXXXXXo.', 'oXooooXoo', 'oXXXXXXXo', 'oXooooXXo', 'oXXXXXXXo', 'oXoooXXXo', 'oXXXXXXXo', 'ooooooooo' },
  ammo = { '.X.X.X...', '.X.X.X...', 'ooooooooo', 'oXXXXXXXo', 'oXoooooXo', 'oXXXXXXXo', 'oXXXXXXXo', 'oXXXXXXXo', 'ooooooooo' },
  grenade = { '....oo...', '...oXXo..', '..ooooo..', '.oXXXXXo.', 'oXXXXXXXo', 'oXXoXXXXo', 'oXXXXXXXo', '.oXXXXXo.', '..ooooo..' },
  cross = { '...ooo...', '...oXo...', '...oXo...', 'oooXXXooo', 'oXXXXXXXo', 'oooXXXooo', '...oXo...', '...oXo...', '...ooo...' },
  gun = { '.........', '.........', 'ooooooooo', 'XXXXXXXXo', 'oXXXXXooo', 'o.oXo....', '..oXo....', '..ooo....', '.........' },
  fab = { '......oo.', '......Xo.', 'o..o..Xo.', 'XooXooXo.', 'XXXXXXXXo', 'XXXXXXXXo', 'XXXoooXXo', 'XXXo.oXXo', 'ooooooooo' },
  bfab = { '......o.o', '......XoX', 'o.o.o.XoX', 'XoXoXoXoX', 'XXXXXXXXX', 'XXXXXXXXX', 'XXoooooXX', 'XXo...oXX', 'ooooooooo' },
  ship = { '.........', '...ooo...', '..oXXXo..', '.oXXXXXo.', 'oXXXXXXXo', 'oooooooo.', '.X..X..X.', '.X..X..X.', '.........' },
  hole = { '.........', '..ooooo..', '.oXXXXXo.', 'oXXoooXXo', 'oXo...oXo', 'oXo...oXo', 'oXo...oXo', 'ooooooooo', '.........' },
  skull = { '.ooooooo.', 'oXXXXXXXo', 'oXXXXXXXo', 'oXoXXXoXo', 'oXoXXXoXo', 'oXXXoXXXo', '.oXXXXXo.', '.oXoXoXo.', '.ooooooo.' },
}
local CHECK = { '........X', '.......XX', '......XX.', 'X....XX..', 'XX..XX...', '.XXXX....', '..XX.....', '.........', '.........' }

-- The kinds, in ledger order (the most valuable first, supplies last), with their units' resource ids. Pickups of a
-- kind within `stack` meters of each other share one icon on the radar, with a count.
-- An enemy structure drops off once it looks destroyed (its meshes or its animation state, per kind below). Bile Titan
-- holes aren't here: a closed one showed no change I can read.
local KINDS = {
  { id = 'credit', icon = 'coin', rgb = { 115, 233, 242 }, stack = 2, units = { 'bd6f4de16b9aedcd' } },
  { id = 'medal', icon = 'star', rgb = { 255, 221, 31 }, stack = 2, units = { '773c4184e4bad0df' } },
  { id = 'common', icon = 'vial', rgb = { 95, 220, 60 }, stack = 2,
    units = { '307e09e7698881ba', '294eda665270ac42', 'cf1ad44dedd1f257', '5016ee397fdcfb6c', '64b49b9d8a445266',
              '700e9500e95541bf', '86f3cb87d97942b4', '4efcb7e844be9e93', 'a2414ed6e129c19f', 'b39fcf5c73d5c383',
              'beb2a0f09e36bf72', 'd463836441cd0ba7', 'e4eeb96023df6a99' } },
  { id = 'rare', icon = 'diamond', rgb = { 255, 151, 64 }, stack = 2,
    units = { '8208ea6cb095be54', 'ad972a2e815a49aa', 'bd30758426ed2566', 'defe062c2567c23d' } },
  { id = 'super', icon = 'crystal', rgb = { 255, 114, 211 }, stack = 2, units = { '9d4935fa69b6b41a', 'b4d6f2f83bde45a9' } },
  { id = 'requisition', icon = 'slip', rgb = { 244, 247, 56 }, stack = 2, units = { 'da3c547d0e0e442f' } },
  { id = 'ammo', icon = 'ammo', rgb = { 255, 234, 128 }, stack = 10, supply = true, units = { '79ccffd281e3f3a9' } },
  { id = 'grenade', icon = 'grenade', rgb = { 135, 170, 45 }, stack = 10, supply = true, units = { '97af34fbf093409c' } },
  { id = 'stim', icon = 'cross', rgb = { 60, 140, 255 }, stack = 10, supply = true, units = { 'b4ca4c5b922f7965' } },
  -- Enemy Structures, in deep red. A destroyed bot fabricator stays in the world: its animation state goes to 3, then
  -- 4, and its 21 meshes swap from whole (1-4 and 17-21 show) to rubble (12-16 show). One destroyed before I joined
  -- arrives as rubble but its state never moves, so the hidden first mesh counts too (`dead_mesh`).
  { id = 'fabricator', say = 'fabricator', icon = 'fab', rgb = { 190, 20, 30 }, stack = 5, structure = true, dead_state = 3, dead_mesh = 1, units = { 'a57ae2a703c02899' } },
  -- The Bulk Fabricator (colony_cyborg_spawner). Its state stays 0 when destroyed, but its meshes swap: whole, meshes
  -- 1-3 and 17-20 show; destroyed, 1-3 hide and the rubble (4-16) shows. So it's destroyed once mesh 1 hides.
  { id = 'bulkfab', say = 'Bulk Fabricator', icon = 'bfab', rgb = { 190, 20, 30 }, stack = 8, structure = true, dead_mesh = 1, units = { 'a2a86454f67fbc47' } },
  -- A destroyed warp ship stays in the world too. It has no state machine, but its 16 meshes swap: whole, meshes 4-6
  -- and 12-16 show (0001110000011111); destroyed, 1-3 and 7-11 show (1110001111100000). Destroyed once mesh 4 hides.
  { id = 'ilship', say = 'warp ship', icon = 'ship', rgb = { 190, 20, 30 }, stack = 5, structure = true, dead_mesh = 4, units = { 'f5f3207ca1b3a5d6' } },
  -- Bug holes (small, medium, large and ceiling). A closed hole swaps its meshes exactly like a destroyed warp ship
  -- (no state machine, 16 meshes, open 0001110000011111, closed 1110001111100000), so it's closed once mesh 4 hides.
  { id = 'bughole', say = 'bug hole', icon = 'hole', rgb = { 190, 20, 30 }, stack = 5, structure = true, dead_mesh = 4,
    units = { '2e454bd4d24eb04a', 'a83587cbff25c79e', 'd6a27adb179ad4ff', '3b3327050e8c2c23' } },
  -- Support weapons and expendables lying on the ground (a fallen Helldiver's, one set down, an unused drop), each
  -- drawn with its own silhouette; never in the ledger. The same weapon within `stack` meters shares an icon.
  { id = 'weapon', icon = 'gun', rgb = { 235, 235, 235 }, stack = 1, weapon = true,
    units = { '6cfcc7f8801a0266', 'a8cffb316f0b5c5f', '89c5493e08ca4207', '96de9cd50f7306e6', '78a8185f63a70795',
              '80932fa0ed6901d3', '7617642765ac38c7', 'b2b5e0d185605f9e', '25aa2fd4643cf4ee', '39ab99895147a3bf',
              '02eecd0b1fa49630', '88c2d09ad85a7c9f', 'fe3b29b2cfa63f9b', '9f80d67a12a7e40f', 'd54b9505c0f72873',
              '35a61296619cc47e', '43a58cb89cfa197c', 'a6a735accb4a327f', '2152d5147b0ac418', '11c27d3babb38956',
              'b16c9d490aa59b77', '5990123d142b16cb', 'e8d5f49ad7780e54', '26e40437ea275296', '2e9d0bdc48b09e60',
              '3828e2051aa9e897', 'cc786f6491fe7e65', '43b2d7766120203b', '52071f49263415e4' },
    -- each weapon's name, for its row in the options menu (the player picks which weapons show)
    names = { ['6cfcc7f8801a0266'] = '40-K Meltagun', ['a8cffb316f0b5c5f'] = 'AC-8 Autocannon', ['89c5493e08ca4207'] = 'APW-1 Anti-Materiel Rifle',
      ['96de9cd50f7306e6'] = 'ARC-3 Arc Thrower', ['78a8185f63a70795'] = 'B/FLAM-80 Cremator', ['80932fa0ed6901d3'] = 'EAT-17 Expendable Anti-Tank',
      ['7617642765ac38c7'] = 'EAT-411 Leveller', ['b2b5e0d185605f9e'] = 'EAT-700 Expendable Napalm', ['25aa2fd4643cf4ee'] = 'FAF-14 Spear',
      ['39ab99895147a3bf'] = 'FLAM-40 Flamethrower', ['02eecd0b1fa49630'] = 'GL-21 Grenade Launcher', ['88c2d09ad85a7c9f'] = 'GL-28 Belt-Fed Grenade Launcher',
      ['fe3b29b2cfa63f9b'] = 'GL-52 De-Escalator', ['9f80d67a12a7e40f'] = 'GR-8 Recoilless Rifle', ['d54b9505c0f72873'] = 'LAS-98 Laser Cannon',
      ['35a61296619cc47e'] = 'LAS-99 Quasar Cannon', ['43a58cb89cfa197c'] = 'M-1000 Maxigun', ['a6a735accb4a327f'] = 'M-105 Stalwart',
      ['2152d5147b0ac418'] = 'MG-206 Heavy Machine Gun', ['11c27d3babb38956'] = 'MG-43 Machine Gun', ['b16c9d490aa59b77'] = 'MGX-42 Bullet Storm',
      ['5990123d142b16cb'] = 'MLS-4X Commando', ['e8d5f49ad7780e54'] = 'PLAS-45 Epoch', ['26e40437ea275296'] = 'RL-77 Airburst Rocket Launcher',
      ['2e9d0bdc48b09e60'] = 'RS-422 Railgun', ['3828e2051aa9e897'] = 'S-11 Speargun', ['cc786f6491fe7e65'] = 'StA-X3 W.A.S.P. Launcher',
      ['43b2d7766120203b'] = 'TX-41 Sterilizer', ['52071f49263415e4'] = 'SG-88 Break-Action Shotgun' } },
  -- Enemies, in bright red, only inside the radar's range and never in the ledger or as world markers: the heavies
  -- with the game's skull, the rest as the game's enemy dot (medium ones bigger). Each one's main body unit (its guns,
  -- arms, turrets, legs and packs are units of their own and left out, so nothing counts twice). Gun emplacements are
  -- left out too (harmless until an enemy mans one); the bunker turret fires on its own, so it's in. The Enemies option
  -- picks how many tiers show (`tier`: 3 heavy, 2 medium, 1 light); a tier not shown isn't listed at all. They move,
  -- so I keep reading where they are while the radar shows (see foe_update), not only at each list.
  { id = 'enemy', say = 'enemy', icon = 'skull', rgb = { 255, 70, 50 }, stack = 0, enemy = true,
    units = {
              '1a7fcdff98c664b0', '3aff5fd7d5450b99', '6b202392f4ab605e', '0ab7b92b131c228c', 'dcf8e74212fbee3b',
              '9e2e17f2ccccafdd', 'ef04cb84d097a497', '960b48a421a3faaa', 'd465d9c7f77a07cb', '36aa99cce5e60146',
              'ccae5264acd591b7', 'cc7022fdd172089b', 'a381a11c07d3eb94', 'd522fd4748d443a5', 'f79cd8bb654397df',
              'a1f37bf2a40fbde4', 'f540ca9d9d4a422e', 'a35207c6f2150806', '09872e66d1276e1f', 'be39e313a1e46bb9',
              '10081acef6163ef6', '1baeef36a88ae579', 'a478d36a62a861f4', 'd7e2c78b1ef4a8e1', 'c28b3482e73d1ea9',
              'aab438596f5e8fd9', 'c14e0e887e7d2106', '5b968cd78f8bc7a0', 'db964631be1cf501', '72a83e49ced6db3d',
              '64090088502435dd', '846bc06c6b213a06', 'b16493b009eec762', '00bcf8247a544cdc', 'd37e8d120d2836e3',
              'ef570293245a17c2', 'bc242702fb46b7e7', 'ae63e525853d7044', 'c626d2bb495a202d', 'db7139323c40ae6f',
              '3d9c95bd03c0c7cf', 'a6a68d8af177f3a1', '54e107dacf6929cb', 'f8131632aa867107', '282eb766c1ffa6a1',
              'db90077e76faa025', 'b2b3056bdf28e57b', '64ba5f030b114ec1', '9821303bd499cd62', '9f57782f00e6ed20',
              'a71aafd82c6ebc92', '746a7f3beda32699', '1338b552afe68f0a', '9f44121c554dae89', '67381f685e9b69a8',
              '965eae5a51acdd4a', '453fe22c634eb30f', 'f22d027b37bef107', 'da40bb347c7447f2', '604a794ec45bb820',
              'e8f19a0aa958e46d', '905809a4c28d8a45', 'cc188f0c80505c6c', '20b9c7734daead65', 'ac60e78435098c9d',
              '67dc32dca4f02d33', '19e18b46ec55d94a', '74e2285c01da4f71', '78e1497571012c47', '0adc9f9173ad8e1d',
              '44458a2c52b002fb', '34dfd23365472e9e', 'f735a51a991e4bda', '9926876b2375a1bb' },
    names = {
      ['1a7fcdff98c664b0'] = 'Charger', ['3aff5fd7d5450b99'] = 'Charger Behemoth', ['6b202392f4ab605e'] = 'Spore Charger',
      ['0ab7b92b131c228c'] = 'Rupture Charger', ['dcf8e74212fbee3b'] = 'Impaler', ['9e2e17f2ccccafdd'] = 'Bile Titan',
      ['ef04cb84d097a497'] = 'Spore Burst Bile Titan', ['960b48a421a3faaa'] = 'Dragonroach', ['d465d9c7f77a07cb'] = 'Hive Lord',
      ['36aa99cce5e60146'] = 'Bile Spewer', ['ccae5264acd591b7'] = 'Bile Spewer', ['cc7022fdd172089b'] = 'Nursing Spewer',
      ['a381a11c07d3eb94'] = 'Rupture Spewer', ['d522fd4748d443a5'] = 'Brood Commander', ['f79cd8bb654397df'] = 'Alpha Commander',
      ['a1f37bf2a40fbde4'] = 'Hive Guard', ['f540ca9d9d4a422e'] = 'Stalker', ['a35207c6f2150806'] = 'Rupture Warrior',
      ['09872e66d1276e1f'] = 'Warrior', ['be39e313a1e46bb9'] = 'Warrior', ['10081acef6163ef6'] = 'Bile Warrior',
      ['1baeef36a88ae579'] = 'Spore Burst Warrior', ['a478d36a62a861f4'] = 'Hunter', ['d7e2c78b1ef4a8e1'] = 'Predator Hunter',
      ['c28b3482e73d1ea9'] = 'Spore Burst Hunter', ['aab438596f5e8fd9'] = 'Pouncer', ['c14e0e887e7d2106'] = 'Scavenger',
      ['5b968cd78f8bc7a0'] = 'Scavenger', ['db964631be1cf501'] = 'Spore Burst Scavenger', ['72a83e49ced6db3d'] = 'Bile Spitter',
      ['64090088502435dd'] = 'Shrieker', ['846bc06c6b213a06'] = 'Hulk', ['b16493b009eec762'] = 'Hulk Scorcher',
      ['00bcf8247a544cdc'] = 'Tank', ['d37e8d120d2836e3'] = 'Factory Strider', ['ef570293245a17c2'] = 'War Strider',
      ['bc242702fb46b7e7'] = 'Vox Engine', ['ae63e525853d7044'] = 'Devastator', ['c626d2bb495a202d'] = 'Devastator',
      ['db7139323c40ae6f'] = 'Rocket Devastator', ['3d9c95bd03c0c7cf'] = 'Heavy Devastator', ['a6a68d8af177f3a1'] = 'Berserker',
      ['54e107dacf6929cb'] = 'Berserker', ['f8131632aa867107'] = 'Scout Strider', ['282eb766c1ffa6a1'] = 'Gunship',
      ['db90077e76faa025'] = 'Dropship', ['b2b3056bdf28e57b'] = 'Trooper', ['64ba5f030b114ec1'] = 'Marauder',
      ['9821303bd499cd62'] = 'Trooper', ['9f57782f00e6ed20'] = 'Trooper', ['a71aafd82c6ebc92'] = 'Commissar',
      ['746a7f3beda32699'] = 'Radical', ['1338b552afe68f0a'] = 'Radical', ['9f44121c554dae89'] = 'Agitator',
      ['67381f685e9b69a8'] = 'Agitator', ['965eae5a51acdd4a'] = 'Harvester', ['453fe22c634eb30f'] = 'Gatekeeper',
      ['f22d027b37bef107'] = 'Leviathan', ['da40bb347c7447f2'] = 'Overseer', ['604a794ec45bb820'] = 'Elevated Overseer',
      ['e8f19a0aa958e46d'] = 'Crescent Overseer', ['905809a4c28d8a45'] = 'Crusher', ['cc188f0c80505c6c'] = 'Wretch',
      ['20b9c7734daead65'] = 'Veracitor', ['ac60e78435098c9d'] = 'Watcher', ['67dc32dca4f02d33'] = 'Fleshmob',
      ['19e18b46ec55d94a'] = 'Stingray', ['74e2285c01da4f71'] = 'Warp Ship', ['78e1497571012c47'] = 'Voteless',
      ['0adc9f9173ad8e1d'] = 'Voteless', ['44458a2c52b002fb'] = 'Voteless', ['34dfd23365472e9e'] = 'Obtruder',
      ['f735a51a991e4bda'] = 'Warp Ship', ['9926876b2375a1bb'] = 'Bunker Turret' },
    tier = {
      ['1a7fcdff98c664b0'] = 3, ['3aff5fd7d5450b99'] = 3, ['6b202392f4ab605e'] = 3, ['0ab7b92b131c228c'] = 3, ['dcf8e74212fbee3b'] = 3,
      ['9e2e17f2ccccafdd'] = 3, ['ef04cb84d097a497'] = 3, ['960b48a421a3faaa'] = 3, ['d465d9c7f77a07cb'] = 3, ['36aa99cce5e60146'] = 2,
      ['ccae5264acd591b7'] = 2, ['cc7022fdd172089b'] = 2, ['a381a11c07d3eb94'] = 2, ['d522fd4748d443a5'] = 2, ['f79cd8bb654397df'] = 2,
      ['a1f37bf2a40fbde4'] = 2, ['f540ca9d9d4a422e'] = 2, ['a35207c6f2150806'] = 2, ['09872e66d1276e1f'] = 1, ['be39e313a1e46bb9'] = 1,
      ['10081acef6163ef6'] = 1, ['1baeef36a88ae579'] = 1, ['a478d36a62a861f4'] = 1, ['d7e2c78b1ef4a8e1'] = 1, ['c28b3482e73d1ea9'] = 1,
      ['aab438596f5e8fd9'] = 1, ['c14e0e887e7d2106'] = 1, ['5b968cd78f8bc7a0'] = 1, ['db964631be1cf501'] = 1, ['72a83e49ced6db3d'] = 1,
      ['64090088502435dd'] = 1, ['846bc06c6b213a06'] = 3, ['b16493b009eec762'] = 3, ['00bcf8247a544cdc'] = 3, ['d37e8d120d2836e3'] = 3,
      ['ef570293245a17c2'] = 3, ['bc242702fb46b7e7'] = 3, ['ae63e525853d7044'] = 2, ['c626d2bb495a202d'] = 2, ['db7139323c40ae6f'] = 2,
      ['3d9c95bd03c0c7cf'] = 2, ['a6a68d8af177f3a1'] = 2, ['54e107dacf6929cb'] = 2, ['f8131632aa867107'] = 2, ['282eb766c1ffa6a1'] = 2,
      ['db90077e76faa025'] = 2, ['b2b3056bdf28e57b'] = 1, ['64ba5f030b114ec1'] = 1, ['9821303bd499cd62'] = 1, ['9f57782f00e6ed20'] = 1,
      ['a71aafd82c6ebc92'] = 1, ['746a7f3beda32699'] = 1, ['1338b552afe68f0a'] = 1, ['9f44121c554dae89'] = 1, ['67381f685e9b69a8'] = 1,
      ['965eae5a51acdd4a'] = 3, ['453fe22c634eb30f'] = 3, ['f22d027b37bef107'] = 3, ['da40bb347c7447f2'] = 2, ['604a794ec45bb820'] = 2,
      ['e8f19a0aa958e46d'] = 2, ['905809a4c28d8a45'] = 2, ['cc188f0c80505c6c'] = 2, ['20b9c7734daead65'] = 2, ['ac60e78435098c9d'] = 2,
      ['67dc32dca4f02d33'] = 3, ['19e18b46ec55d94a'] = 2, ['74e2285c01da4f71'] = 2, ['78e1497571012c47'] = 1, ['0adc9f9173ad8e1d'] = 1,
      ['44458a2c52b002fb'] = 1, ['34dfd23365472e9e'] = 1, ['f735a51a991e4bda'] = 2, ['9926876b2375a1bb'] = 2 } },
  -- Friendlies: SEAF troopers (both kinds) and civilians (an evacuation's), as blue dots inside the radar's range,
  -- tracked like the enemies (they move, and a body loses its state machine, so one drops off when it dies).
  { id = 'friend', say = 'SEAF trooper', icon = 'skull', rgb = { 80, 170, 255 }, stack = 0, enemy = true, friendly = true, dot = 'frienddot',
    units = { '7a3637cd33a54e4c', '75f7e96af7dcd303', 'b08f09d64e228427', 'e71dbcb6a50f321b' },
    names = { ['7a3637cd33a54e4c'] = 'SEAF trooper', ['75f7e96af7dcd303'] = 'SEAF trooper', ['b08f09d64e228427'] = 'civilian',
      ['e71dbcb6a50f321b'] = 'civilian' },
    tier = { ['7a3637cd33a54e4c'] = 2, ['75f7e96af7dcd303'] = 2, ['b08f09d64e228427'] = 2, ['e71dbcb6a50f321b'] = 2 } },
  -- Squadmates: the other Helldivers, as green dots inside the radar's range (not me: I'm the radar's middle). One who
  -- dies drops off; reinforced, he's a new unit and shows again.
  { id = 'squad', say = 'Helldiver', icon = 'skull', rgb = { 60, 230, 120 }, stack = 0, enemy = true, friendly = true, dot = 'squaddot',
    units = { '4d1c334d294dfa97' }, names = { ['4d1c334d294dfa97'] = 'Helldiver' }, tier = { ['4d1c334d294dfa97'] = 2 } },
}
-- A Helldiver (any player). A weapon held or on someone's back sits up at their hands or back, a dropped one on the
-- ground (also next to a body), so a weapon near a carrier and CARRY_UP above their feet is carried, not shown.
local DIVER = '4d1c334d294dfa97'
-- Everyone who can carry a support weapon: Helldivers (avatar_helldiver; fp_cha_avatar, the first-person one) and SEAF
-- troopers (cha_seaf, cha_battlefront_seaf: their specialists carry EATs and machine guns).
local CARRIERS = { [DIVER] = true, ['d0cf4d493ca08bed'] = true, ['7a3637cd33a54e4c'] = true, ['75f7e96af7dcd303'] = true }
local CARRY_NEAR, CARRY_UP_MIN, CARRY_UP_MAX = 1.2, 0.5, 2.3
-- A trooper's weapon can sit 0.4-1.9 m from him and -0.7 to 0.4 m up from his position. So in this wider reach of a
-- living carrier (one with an animation state machine: a body loses it) a weapon counts as carried, still or not; in
-- that reach of a body it's lying on the ground (a fallen Helldiver's or trooper's).
local NEAR_REACH, NEAR_DOWN, NEAR_UP = 2.5, -1.5, 2.5
-- My textures (resource ids, filled in by the build): the icons, the radar panel, the sweep's frames, the ledger's
-- tile, the check mark, the blip glow, and the characters for numbers at six sizes.
local TEXTURES = { weapons = {} }       -- weapons: unit id -> its silhouette (128 x 48); weapon_generic for the rest
local GLYPHS, GLYPH_PAD = {}, 2
local TEXTURES_UI = {}                  -- texture -> its copy for the UI world (below native Render Scale)
-- texture -> its ladder of pre-shrunk sizes (the UI material has no mipmaps, so a texture shrunk by half or more draws
-- with stair-step edges): the loader draws the one nearest the size I ask for
local TEXTURE_SIZES = {}
--@@ICON_TEXTURES@@
if chef.ui_textures then chef.ui_textures(TEXTURES_UI) end
if chef.texture_sizes then chef.texture_sizes(TEXTURE_SIZES) end
for i, k in ipairs(KINDS) do
  k.texture = TEXTURES[k.id]; k.rank = i
  k.dot_tex = TEXTURES[k.dot or 'enemydot']       -- the small dot, in its own color (the tint is white)
  if k.enemy and not k.friendly then M.foe_kind = k elseif k.weapon then M.weapon_kind = k end
end
local WEAPON_ASPECT = 128 / 48

-- ------------------------------------------------------------------ options (Arsenal)
-- Every kind, the ledger and the core are their own option; each ships a small options file the loader merges.
-- With no options file at all (a plain test install) everything is on.
local opt = chef.options or {}
local any_options = next(opt) ~= nil
local function kind_on(id) if not any_options then return true end return type(opt.kinds) == 'table' and opt.kinds[id] == true end
local SHOW_RADAR = not any_options or opt.radar ~= false
local SHOW_LEDGER = not any_options or opt.ledger == true
local RANGE = max(25, min(1000, tonumber(opt.range) or 150))   -- meters from me to the radar's edge
local MAP_SCALE = ({ small = 0.6, medium = 0.75, large = 1.0 })[opt.size or ''] or 0.75   -- Size, of the map circle
local ROTATE = opt.rotate == true                                -- Rotate With View: my view is always up
local MARKERS = tonumber(opt.markers)                            -- World Markers: their range in meters, or nil
local OPACITY = max(0, min(1, tonumber(opt.opacity) or 1))       -- the panels' opacity; icons and counts stay solid
-- Radar Animation (ticked by default in Arsenal): the sweep and the pickups lighting up; unticked, a still radar with
-- every pickup at full strength
local STILL = any_options and opt.animation ~= true
-- The settings as they are now: the Arsenal options above to start with, then whatever the player changes in the
-- loader's options menu (F9; saved between launches). Everything below reads cfg, so a change shows at once. One
-- table rather than a local each also keeps the drawing functions under Lua 5.1's 60 upvalues.
local cfg = { radar = SHOW_RADAR, ledger = SHOW_LEDGER, scale = MAP_SCALE, rotate = ROTATE, markers = MARKERS,
              opacity = OPACITY, still = STILL, kinds = {}, weapons_off = {},
              -- Enemies: the lowest tier shown (1 all, 2 medium and heavy, 3 heavy only)
              enemy_tier = max(1, min(3, tonumber(opt.enemy_tier) or 1)),
              -- Position: where the radar sits (beside the game's map by default), and the player's nudge from there in
              -- steps of half a percent of the screen's height
              pos = opt.position or 'map', nudge_x = 0, nudge_y = 0 }
for _, k in ipairs(KINDS) do cfg.kinds[k.id] = kind_on(k.id) end
local ENDLESS = 10000                   -- World Markers at this range or more: no limit
local function A(a) return floor(a * cfg.opacity + 0.5) end

-- ------------------------------------------------------------------ keys (Arsenal: Hide Key, Zoom Keys, Markers Key)
-- A key is a list of the engine's names for it (the same names the game's own input settings use), tried in order.
local KEYS = {
  f1 = { 'f1' }, f2 = { 'f2' }, f3 = { 'f3' }, f4 = { 'f4' }, f5 = { 'f5' }, f6 = { 'f6' }, f7 = { 'f7' }, f8 = { 'f8' },
  f9 = { 'f9' }, f10 = { 'f10' }, f11 = { 'f11' }, f12 = { 'f12' },
  insert = { 'insert' }, home = { 'home' }, ['end'] = { 'end' }, delete = { 'delete' },
  pageup = { 'page up', 'pageup', 'page_up', 'prior' }, pagedown = { 'page down', 'pagedown', 'page_down', 'next' },
  pause = { 'pause' }, scrolllock = { 'scroll lock', 'scroll_lock', 'scrolllock' },
  numpad0 = { 'numpad 0', 'num 0' }, numpad2 = { 'numpad 2', 'num 2' }, numpad8 = { 'numpad 8', 'num 8' },
  numpaddot = { 'numpad .', 'numpad decimal', 'num .' }, numpadmul = { 'numpad *', 'numpad multiply', 'num *' },
  numpaddiv = { 'numpad /', 'numpad divide', 'num /' },
  numpadplus = { 'numpad +', 'num +', 'numpad plus' }, numpadminus = { 'numpad -', 'num -', 'numpad minus' },
  lbracket = { 'open bracket', '[' }, rbracket = { 'close bracket', ']' },
}
local KEY_LABEL = { insert = 'Insert', home = 'Home', ['end'] = 'End', delete = 'Delete', pageup = 'Page Up', pagedown = 'Page Down',
  pause = 'Pause', scrolllock = 'Scroll Lock', numpad0 = 'Numpad 0', numpad2 = 'Numpad 2', numpad8 = 'Numpad 8',
  numpaddot = 'Numpad .', numpadmul = 'Numpad *', numpaddiv = 'Numpad /', numpadplus = 'Numpad +', numpadminus = 'Numpad -',
  lbracket = '[', rbracket = ']' }
local function key_label(id) return id == 'off' and 'off' or KEY_LABEL[id] or id:upper() end
local ZOOM_PAIRS = { numpad = { 'numpadplus', 'numpadminus' }, page = { 'pageup', 'pagedown' }, homeend = { 'home', 'end' },
  insdel = { 'insert', 'delete' }, numpad82 = { 'numpad8', 'numpad2' }, brackets = { 'rbracket', 'lbracket' } }
local function pick_key(v, default)
  if v == 'off' then return 'off' end
  return (type(v) == 'string' and KEYS[v]) and v or default
end
local HIDE_KEY = pick_key(opt.hide_key, 'f7')
local MARKER_KEY = pick_key(opt.marker_key, 'f8')
local ZOOM = (opt.zoom_keys == 'off') and 'off' or (ZOOM_PAIRS[opt.zoom_keys or ''] and opt.zoom_keys or 'numpad')
-- Double-Tap Tab To Hide (ticked by default). The option keeps the old Hold Tab To Hide folder (tabhold) and key
-- (tab_hold), so a player's tick carries over.
local TAB_DOUBLE = not any_options or opt.tab_hold == true
local HIDE_NAMES = HIDE_KEY ~= 'off' and KEYS[HIDE_KEY] or nil
local MARKER_NAMES = MARKER_KEY ~= 'off' and KEYS[MARKER_KEY] or nil
local ZOOM_IN_KEYS = ZOOM ~= 'off' and KEYS[ZOOM_PAIRS[ZOOM][1]] or nil
local ZOOM_OUT_KEYS = ZOOM ~= 'off' and KEYS[ZOOM_PAIRS[ZOOM][2]] or nil
cfg.tab, cfg.hide, cfg.mark, cfg.zin, cfg.zout = TAB_DOUBLE, HIDE_NAMES, MARKER_NAMES, ZOOM_IN_KEYS, ZOOM_OUT_KEYS
local DOUBLE_TAP = 0.5                  -- two Tab presses this close (seconds) hide or show the radar (one opens the map)
local SWEEP_T = 3                       -- seconds for one turn of the sweep
local ALIVE_EVERY = 0.1                 -- how often I check that the pickups near me are still there
local HUD_EVERY = 30                    -- how often I read the HUD settings again in a mission (first at its start)
local MARK_STACK = 2                    -- meters: pickups of a kind this close share one world marker
local EYE = 1.6                         -- my camera sits about this high above my feet
local RIM_LETTERS = { { 'N', 0, 1 }, { 'E', 1, 0 }, { 'S', 0, -1 }, { 'W', -1, 0 } }
local GREEN, GLOW = { 150, 255, 180 }, { 150, 255, 180 }

-- ------------------------------------------------------------------ zoom (the Zoom Keys; numpad + and - by default)
-- The range steps through ZOOMS, starting at the Arsenal range. The last zoom is remembered between launches by the
-- options menu's Range row, or, on a loader without the menu, in a file next to my log ("<range> <the Arsenal range
-- it was zoomed from>", so a new Arsenal pick starts over).
local ZOOMS = { 50, 75, 100, 150, 200, 250, 300, 400, 500 }
local ZOOM_FILE = nil
-- the loader's options menu saves the range itself; the zoom file is only for a loader without one
local HAS_MENU = type(chef.has) == 'function' and chef.has('menu') and type(chef.option) == 'function'
if not HAS_MENU then
  -- the loader's folder (chef.log_directory), else %LOCALAPPDATA%
  local dir = type(chef.log_directory) == 'string' and chef.log_directory or nil
  if not dir or dir == '' then
    local ok, d = pcall(os.getenv, 'LOCALAPPDATA')
    dir = ok and type(d) == 'string' and d ~= '' and d or nil
  end
  if dir then ZOOM_FILE = dir .. '\\treasure_radar_zoom.txt' end
end
local range_now = RANGE
local zoom_note = { text = nil, until_t = 0 }
if ZOOM_FILE then
  local okf, f = pcall(io.open, ZOOM_FILE, 'r')
  if okf and f then
    local v, base = (f:read('*l') or ''):match('^(%d+)%s+(%d+)')
    f:close()
    v, base = tonumber(v), tonumber(base)
    if v and base == RANGE and v >= 25 and v <= 1000 then range_now = v end
  end
end
local function set_range(v)
  range_now = v
  if cfg.on_range then cfg.on_range(v) end
  zoom_note.text, zoom_note.until_t = v .. ' M', chef.time() + 2
  if ZOOM_FILE then
    local okf, f = pcall(io.open, ZOOM_FILE, 'w')
    if okf and f then f:write(tostring(v), ' ', tostring(RANGE), '\n'); f:close() end
  end
  chef.log('radar range: %d m', v)
end
local function zoom_step(dir)
  if dir < 0 then
    for i = #ZOOMS, 1, -1 do if ZOOMS[i] < range_now then set_range(ZOOMS[i]); return end end
  else
    for i = 1, #ZOOMS do if ZOOMS[i] > range_now then set_range(ZOOMS[i]); return end end
  end
end
local function any_key(list)
  if not list then return false end
  for _, k in ipairs(list) do if chef.key_pressed(k) then return true end end
  return false
end
-- once, at the first mission: say if a picked key isn't one the game knows (then it does nothing)
local function check_keys()
  if not chef.key_known then return end
  local bad = {}
  local function chk(id)
    if id == 'off' or not KEYS[id] then return end
    for _, n in ipairs(KEYS[id]) do if chef.key_known(n) then return end end
    bad[#bad + 1] = key_label(id)
  end
  chk(HIDE_KEY); chk(MARKER_KEY)
  if ZOOM ~= 'off' then chk(ZOOM_PAIRS[ZOOM][1]); chk(ZOOM_PAIRS[ZOOM][2]) end
  if #bad > 0 then chef.log('keys the game does not know (they do nothing): %s', table.concat(bad, ', ')) end
end

-- ------------------------------------------------------------------ where the game's map opens
-- The game anchors its HUD's bottom-right corner 70 px from the right and 44 px from the bottom (at 1440 px; 0.0486
-- and 0.0306 screen heights). HUD Edge Offset slides that corner between the right edge of the 16:9 area in the middle
-- of the screen (1) and the screen's own edge (0). The map is a circle with a 296 px radius to its rim (0.2056
-- heights), the same at any HUD Scale. Its center sits MAP_DX left of and MAP_DY above the corner at HUD Scale 0.85,
-- and moves a little with HUD Scale (measured at 0.75, 0.85 and 1.25).
local CORNER_RIGHT, CORNER_BOTTOM, BASE_SCALE = 70 / 1440, 44 / 1440, 0.85
local MAP_DX, MAP_DY = 254.4 / 1440, 301.3 / 1440
local DX_PER_SCALE, DY_PER_SCALE = 34 / 1440, 63 / 1440
local MAP_RIM, MY_RADIUS = 0.2056, 0.19
-- Nothing readable tells me the map is open (a stratagem code and chat show in my Helldiver's pose, the map never
-- does), so the radar sits just left of the map's rim, its center level with the map's, and follows the HUD settings
-- the same way. MAP_GAP: the space between the two rims, in screen heights.
local MAP_GAP = 0.012

-- The game's HUD settings: saves\<player id>_user_settings.config in the game's folder in %APPDATA%.
local hud = {}
local function hud_scale()
  local s = hud.scale
  if type(s) ~= 'number' or s < 0.3 or s > 3 then return BASE_SCALE end
  return s
end
local function read_hud()
  local ok, appdata = pcall(os.getenv, 'APPDATA')
  local peer = chef.call('Network.peer_id')
  if not (ok and type(appdata) == 'string' and peer) then
    if not hud.no_id then hud.no_id = true; chef.log('hud settings: not found yet (no player id)') end
    return
  end
  local okf, f = pcall(io.open, appdata .. '\\Arrowhead\\Helldivers2\\saves\\' .. tostring(peer) .. '_user_settings.config', 'r')
  if not (okf and f) then
    if not hud.no_file then hud.no_file = true; chef.log('hud settings: the settings file could not be opened; using the defaults') end
    return
  end
  local text = f:read('*a') or ''
  f:close()
  local function num(key) return tonumber(text:match('\n%s*' .. key .. '%s*=%s*([%-%d%.]+)')) end
  hud.offset, hud.scale, hud.map_position, hud.curve = num('hud_offset'), num('hud_scale'), num('hud_map_position'), num('hud_curve')
  local key = string.format('%s %s %s %s', tostring(hud.offset), tostring(hud.scale), tostring(hud.map_position), tostring(hud.curve))
  if key == hud.key then return end
  hud.key = key
  chef.log('hud settings: edge offset %s, scale %s, map position %s, curve %s%s', tostring(hud.offset), tostring(hud.scale),
    tostring(hud.map_position), tostring(hud.curve),
    (hud.map_position == 0 or hud.map_position == nil) and '' or ' (this map position is not measured: the radar may sit a little off the map)')
end

-- Where the radar's center goes (screen pixels from the bottom left), and whether the ledger goes on its right (when
-- the radar sits on the left). 'map': beside the game's map, not under it: left of the map's rim by MAP_GAP, its
-- center level with the map's. The others sit in a corner or at mid height on either side, POS_MARGIN screen heights
-- in from the HUD's own edges (HUD Edge Offset, as the game's HUD), then the player's nudge on top.
local POS_MARGIN = 0.035
function M.place(w, h, R)
  local cx, cy
  local left = false
  if cfg.pos == 'map' or not cfg.pos then
    cx, cy = M.layout(w, h)
    cx = cx - MAP_RIM * h - MAP_GAP * h - R
  else
    local area = min(w, h * 16 / 9)
    local off = hud.offset
    if type(off) ~= 'number' or off < 0 or off > 1 then off = 1 end
    local edge = off * (w - area) / 2 + POS_MARGIN * h
    local side, row = cfg.pos:sub(1, 1), cfg.pos:sub(2, 2)     -- 'tl' = top left, 'mr' = middle right ...
    left = row == 'l'
    cx = left and edge + R or w - edge - R
    cy = (side == 't' and h - POS_MARGIN * h - R) or (side == 'b' and POS_MARGIN * h + R) or h / 2
  end
  -- the sliders move it from there in steps of half a percent of the screen height, but never past an edge
  cx = max(R, min(w - R, cx + cfg.nudge_x * 0.005 * h))
  cy = max(R, min(h - R, cy + cfg.nudge_y * 0.005 * h))
  return cx, cy, left
end

-- the map's center on screen (pixels, bottom-left origin)
local function layout(w, h)
  local area = min(w, h * 16 / 9)
  local off = hud.offset
  if type(off) ~= 'number' or off < 0 or off > 1 then off = 1 end
  local ds = hud_scale() - BASE_SCALE
  local right = w - off * (w - area) / 2 - CORNER_RIGHT * h
  return right - (MAP_DX + ds * DX_PER_SCALE) * h, CORNER_BOTTOM * h + (MAP_DY + ds * DY_PER_SCALE) * h
end
M.layout = layout

-- ------------------------------------------------------------------ the pickups
local kind_of_unit, watch_kinds, active = {}, {}, {}
local WEAPONS_ON = false
-- The kinds that are on (cfg.kinds), again whenever the options menu changes one. watch_kinds is changed in place:
-- the loader's unit watch keeps that very table and reads it at every list.
local function apply_kinds()
  active = {}
  for u in pairs(kind_of_unit) do kind_of_unit[u] = nil end
  for u in pairs(watch_kinds) do watch_kinds[u] = nil end
  WEAPONS_ON = false
  for _, k in ipairs(KINDS) do
    if cfg.kinds[k.id] then
      local n = 0
      for _, u in ipairs(k.units) do
        -- a weapon the player switched off in the options menu, or an enemy below the tier shown, isn't listed at all
        if not (k.weapon and cfg.weapons_off[u]) and not (k.enemy and not k.friendly and k.tier[u] < cfg.enemy_tier) then kind_of_unit[u] = k; watch_kinds[u] = true; n = n + 1 end
      end
      if n > 0 then
        active[#active + 1] = k
        if k.weapon then WEAPONS_ON = true end
      end
    end
  end
  -- with Weapons on, the Helldivers are listed too (only to tell a carried weapon from a dropped one)
  if WEAPONS_ON then for id in pairs(CARRIERS) do watch_kinds[id] = true end end
end
apply_kinds()
-- Every loot kind, ticked or not, tells the loader a small mission from the ship (which never has loot). Supplies,
-- weapons, structures and enemies don't count: the ship might have them.
if chef.mission_kinds then
  local loot = {}
  for _, k in ipairs(KINDS) do
    if not k.supply and not k.weapon and not k.structure and not k.enemy then for _, u in ipairs(k.units) do loot[u] = true end end
  end
  chef.mission_kinds(loot)
end

local watch = nil
local mission_id = 0

-- ------------------------------------------------------------------ the loader's options menu (F9)
-- Every setting again in the menu, when the loader has one. Each row starts at the Arsenal pick; a change applies at
-- once and the loader saves it. The keys are rows the player binds by pressing a key; their defaults are the
-- Arsenal keys.
do
  if HAS_MENU then
    chef.title('Treasure Radar')
    local function said(what, v) if not cfg.zooming then chef.log('menu: %s %s', what, tostring(v)) end end
    local function toggle(id, label, now, set)
      local v = chef.option(id, { type = 'toggle', label = label, default = now == true })
      if v ~= nil then set(v == true) end
      chef.on_change(id, function(x) set(x == true); said(label, x) end)
    end
    local function choice(id, label, names, values, now, set)
      local def = 1
      for i, val in ipairs(values) do if val == now then def = i end end
      local v = chef.option(id, { type = 'choice', label = label, choices = names, default = def })
      if type(v) == 'number' then set(values[v]) end
      chef.on_change(id, function(x) set(values[x]); said(label, names[x]) end)
    end
    toggle('radar', 'Show radar', cfg.radar, function(v) cfg.radar = v end)
    toggle('ledger', 'Show ledger', cfg.ledger, function(v) cfg.ledger = v end)
    choice('size', 'Size', { 'Small', 'Medium', 'Large' }, { 0.6, 0.75, 1.0 }, cfg.scale, function(v) cfg.scale = v end)
    choice('position', 'Position', { 'Beside the map', 'Top left', 'Top right', 'Middle left', 'Middle right', 'Bottom left',
      'Bottom right' }, { 'map', 'tl', 'tr', 'ml', 'mr', 'bl', 'br' }, cfg.pos, function(v) cfg.pos = v end)
    local function nudge(id, label, field)
      local v = chef.option(id, { type = 'slider', label = label, min = -60, max = 60, step = 1, default = 0 })
      if type(v) == 'number' then cfg[field] = v end
      chef.on_change(id, function(x) cfg[field] = x; said(label, x) end)
    end
    nudge('nudge_x', 'Move sideways', 'nudge_x')
    nudge('nudge_y', 'Move up or down', 'nudge_y')
    local rnames, rvals = {}, {}
    for i, z in ipairs(ZOOMS) do rnames[i], rvals[i] = z .. ' M', z end
    choice('range', 'Range', rnames, rvals, range_now, function(v) if v ~= range_now then set_range(v) end end)
    -- the zoom keys move the menu's row along with the range
    cfg.on_range = function(v)
      cfg.zooming = true
      for i, z in ipairs(ZOOMS) do if z == v then chef.set('range', i) end end
      cfg.zooming = false
    end
    toggle('rotate', 'Rotate with view', cfg.rotate, function(v) cfg.rotate = v end)
    local op = chef.option('opacity', { type = 'slider', label = 'Opacity (%)', min = 0, max = 100, step = 5,
                                        default = floor(cfg.opacity * 100 + 0.5) })
    if type(op) == 'number' then cfg.opacity = op / 100 end
    chef.on_change('opacity', function(x) cfg.opacity = x / 100; said('opacity', x) end)
    toggle('animation', 'Radar animation', not cfg.still, function(v) cfg.still = not v end)
    -- (a choice is saved by its place in the list, so this row's values never change order)
    choice('world_markers', 'World markers', { 'Off', '5 M', '10 M', '15 M', '25 M', '50 M', '100 M', '200 M', 'Endless' },
      { false, 5, 10, 15, 25, 50, 100, 200, ENDLESS * 10 }, cfg.markers or false, function(v) cfg.markers = v or nil end)
    toggle('tab', 'Double-tap Tab to hide', cfg.tab, function(v) cfg.tab = v end)
    -- The rows in groups, top to bottom (the menu has rows only, no headings): the look (above), then what shows (loot
    -- in ledger order, supplies, enemy structures, enemies, friendlies), then the keys, and the weapons last, as they
    -- bring a row for every weapon. Arsenal lists its options in the same order.
    local NAMES = { credit = 'Super Credits', medal = 'Medals', common = 'Common Samples', rare = 'Rare Samples',
      super = 'Super Samples', requisition = 'Requisition Slips', ammo = 'Ammo Boxes', grenade = 'Grenade Packs',
      stim = 'Stim Packs', fabricator = 'Fabricators', bulkfab = 'Bulk Fabricators', ilship = 'Warp Ships',
      bughole = 'Bug Holes', weapon = 'Weapons', enemy = 'Enemies', friend = 'SEAF Troopers and Civilians', squad = 'Squadmates' }
    local ORDER = { 'credit', 'medal', 'requisition', 'common', 'rare', 'super', 'ammo', 'grenade', 'stim',
      'fabricator', 'bulkfab', 'ilship', 'bughole', 'enemy', 'friend', 'squad' }
    local by_id = {}
    for _, k in ipairs(KINDS) do by_id[k.id] = k end
    local function kind_row(k)
      toggle('kind_' .. k.id, 'Show ' .. (NAMES[k.id] or k.id), cfg.kinds[k.id], function(v)
        if cfg.kinds[k.id] ~= v then
          cfg.kinds[k.id] = v
          apply_kinds()
          if watch then watch.refresh() end
        end
      end)
    end
    for _, id in ipairs(ORDER) do
      local k = by_id[id]
      if k then
        kind_row(k)
        -- right under Show Enemies: which tiers
        if k.enemy and not k.friendly then
          choice('enemy_tier', 'Enemies shown', { 'All', 'Medium and heavy', 'Heavy only' }, { 1, 2, 3 }, cfg.enemy_tier, function(v)
            if cfg.enemy_tier ~= v then
              cfg.enemy_tier = v
              apply_kinds()
              if watch then watch.refresh() end
            end
          end)
        end
      end
    end
    -- keys: the first of an Arsenal key's names the game knows
    local function engine_name(list)
      if not list then return 'off' end
      if chef.key_known then for _, n in ipairs(list) do if chef.key_known(n) then return n end end end
      return list[1]
    end
    local function key_row(id, label, list, set)
      local b = chef.bind(id, engine_name(list), label)
      if not b then return end
      local function use(k) set(k ~= 'off' and { k } or nil) end
      use(b.key())
      chef.on_change(id, function(k) use(k); said(label, k) end)
    end
    key_row('hide_key', 'Hide key', cfg.hide, function(l) cfg.hide = l end)
    key_row('marker_key', 'World markers key', cfg.mark, function(l) cfg.mark = l end)
    key_row('zoom_in', 'Zoom in key', cfg.zin, function(l) cfg.zin = l end)
    key_row('zoom_out', 'Zoom out key', cfg.zout, function(l) cfg.zout = l end)
    -- last: Show Weapons, then a row for each weapon (all on to start), sorted by name
    local wk = M.weapon_kind
    if wk then
      kind_row(wk)
      local ids = {}
      for _, u in ipairs(wk.units) do ids[#ids + 1] = u end
      table.sort(ids, function(x, y) return wk.names[x] < wk.names[y] end)
      for _, u in ipairs(ids) do
        toggle('weapon_' .. u, '  ' .. wk.names[u], true, function(v)
          if cfg.weapons_off[u] ~= (not v or nil) then
            cfg.weapons_off[u] = not v or nil
            apply_kinds()
            if watch then watch.refresh() end
          end
        end)
      end
    end
    chef.log('options menu: every setting is in the loader\'s options menu too (Treasure Radar)')
  end
end
-- the settings as they stand (at start, after the options menu's saved values are in)
local function log_settings(from)
  local n = 0
  for _, on in pairs(cfg.kinds) do if on then n = n + 1 end end
  chef.log('%s: kinds on %d of %d | radar %s (size %.2f%s%s) | ledger %s | range %d m | opacity %d%% | world markers %s', from, n, #KINDS,
    tostring(cfg.radar), cfg.scale, cfg.rotate and ', turning with my view' or '', cfg.still and ', still' or '',
    tostring(cfg.ledger), range_now, floor(cfg.opacity * 100 + 0.5),
    cfg.markers and (cfg.markers >= ENDLESS and 'endless' or (cfg.markers .. ' m')) or 'off')
  local off = {}
  for u in pairs(cfg.weapons_off) do off[#off + 1] = M.weapon_kind.names[u] or u end
  if #off > 0 then table.sort(off); chef.log('weapons switched off (%d): %s', #off, table.concat(off, ', ')) end
  local function keys(l) return l and table.concat(l, '/') or 'off' end
  chef.log('keys: hide %s%s | zoom %s / %s | world markers %s', keys(cfg.hide), cfg.tab and ' (or double-tap Tab)' or '',
    keys(cfg.zin), keys(cfg.zout), keys(cfg.mark))
end
log_settings(HAS_MENU and 'settings (Arsenal, then the options menu)' or 'settings (Arsenal)')
local last_gen = -1
local hidden, markers_on = false, true
local tab_last = nil                    -- when Tab was last pressed (for the double tap)
local seen_max, counts = {}, {}         -- per kind: the most seen at once this mission, how many in the last list
local stacks = {}                       -- the radar's piles: { kind, x, y, z, n }
local pickups = {}                      -- the world markers' piles (within MARK_STACK): { kind, units, x, y, z }
local stack_of = {}                     -- unit -> its radar pile
local gone, gone_n = {}, {}             -- picked up since the last list: unit -> true, kind id -> how many
local listed_at = {}                    -- a weapon unit -> where the last list had it (each unit of a pile its own spot)
-- structure units the game has shown destroyed (kept for the mission); struct_uk: each listed structure unit's own
-- resource id (from the last list), for its crash key
local dead = { mission = nil, units = {} }
local struct_uk = {}
local next_alive = 0

-- Has this enemy structure been destroyed? Its kind's dead_mesh hides, or its animation state reaches dead_state (a
-- kind can have both: a fabricator's state moves only when it's destroyed while I'm there, its meshes always swap).
-- I ask a unit whether it has a state machine before reading its state: asking one without crashes the game, and
-- some colony fabricators have none. Each call runs under its own unit kind's crash key, so one bug hole type that
-- misbehaves can't silence the other three.
local function is_destroyed(u, k, uk)
  if dead.mission ~= chef.world_id() then dead.mission, dead.units = chef.world_id(), {} end
  if dead.units[u] then return true end
  local key = 's' .. (uk or k.id)
  if k.dead_mesh then
    local m = chef.call_kind('Unit.mesh', key, u, k.dead_mesh)
    if m ~= nil and chef.call_kind('Mesh.visibility', key, m) == false then
      dead.units[u] = true
      return true
    end
  end
  if not k.dead_state then return false end
  if chef.call_kind('Unit.has_animation_state_machine', key, u) ~= true then return false end
  local st = chef.call_kind('Unit.animation_get_state', key, u)
  if type(st) ~= 'number' then return false end
  if st >= k.dead_state then
    dead.units[u] = true
    return true
  end
  return false
end

-- a weapon up at a Helldiver's hands or back (near them, CARRY_UP above their feet) is carried
-- Expendables (EAT-17, EAT-700, EAT-411, MGX-42, MLS-4X) are thrown down once spent and keep their unit.
local EXPENDABLE = { ['80932fa0ed6901d3'] = 'EAT-17', ['b2b5e0d185605f9e'] = 'EAT-700', ['7617642765ac38c7'] = 'EAT-411',
  ['b16c9d490aa59b77'] = 'MGX-42', ['5990123d142b16cb'] = 'MLS-4X' }
-- A loaded EAT-17 on the ground is in animation state 2; once fired and thrown down it's in state 0, every mesh still
-- showing. So an expendable on the ground in state 0 is a spent tube and isn't shown. I take the others to work the
-- same way.
local function spent(it)
  if not EXPENDABLE[it.kind] then return false end
  local key = 'x' .. it.kind
  if chef.call_kind('Unit.has_animation_state_machine', key, it.unit) ~= true then return false end
  return chef.call_kind('Unit.animation_get_state', key, it.unit) == 0
end
local function carried(it, divers)
  local z = it.z or 0
  for i = 1, #divers do
    local d = divers[i]
    local up = z - (d.z or 0)
    local h2 = (d.x - it.x) ^ 2 + (d.y - it.y) ^ 2
    if up >= CARRY_UP_MIN and up <= CARRY_UP_MAX and h2 <= CARRY_NEAR * CARRY_NEAR then return true end
    -- in the wider reach of someone alive: in their hands or on their back, even standing still
    if d.live and up >= NEAR_DOWN and up <= NEAR_UP and h2 <= NEAR_REACH * NEAR_REACH then return true end
  end
  return false
end

local function rebuild(items)
  counts, stacks, gone, gone_n, pickups, stack_of, listed_at, struct_uk = {}, {}, {}, {}, {}, {}, {}, {}
  -- which Helldiver is me (the one nearest my camera, within 6 m): the radar's middle, so never one of its squad dots
  M.me = nil
  local cam, near = chef.camera(), 36
  for _, it in ipairs(items) do
    if it.kind == DIVER then
      local d2 = cam and (it.x - cam.x) ^ 2 + (it.y - cam.y) ^ 2
      if d2 and d2 < near then near, M.me = d2, it.unit end
    end
  end
  local divers, n_carried, n_spent, n_bodies = {}, 0, 0, 0
  -- the enemies: their own list (not in the piles, the ledger or the markers), keeping where each was last seen
  local old_hv, hv = {}, {}
  for _, h in ipairs(M.foes) do if not h.gone then old_hv[h.unit] = h end end
  if WEAPONS_ON then
    for _, it in ipairs(items) do
      if CARRIERS[it.kind] then
        local live = chef.call_kind('Unit.has_animation_state_machine', 'c' .. it.kind, it.unit) == true
        divers[#divers + 1] = { x = it.x, y = it.y, z = it.z, live = live }
        if not live then n_bodies = n_bodies + 1 end
      end
    end
  end
  for _, it in ipairs(items) do
    local k = kind_of_unit[it.kind]
    if k and k.weapon and spent(it) then
      n_spent = n_spent + 1
      k = nil
    elseif k and k.weapon and carried(it, divers) then
      n_carried = n_carried + 1
      k = nil
    end
    if k and k.enemy then
      if not M.foe_dead[it.unit] and it.unit ~= M.me then
        hv[#hv + 1] = old_hv[it.unit] or { unit = it.unit, uk = it.kind, k = k, x = it.x, y = it.y, tier = k.tier[it.kind] or 1 }
      end
      k = nil
    end
    if k and k.structure then struct_uk[it.unit] = it.kind end
    if k and k.structure and is_destroyed(it.unit, k, it.kind) then k = nil end
    if k then
      counts[k.id] = (counts[k.id] or 0) + 1
      local x, y, z = it.x, it.y, it.z or 0
      -- weapons pile up only with the same weapon (each has its own silhouette)
      local wid = k.weapon and it.kind or nil
      if wid then listed_at[it.unit] = it end
      local joined = false
      for _, s in ipairs(stacks) do
        if s.kind == k and s.wid == wid and (s.x - x) ^ 2 + (s.y - y) ^ 2 <= k.stack * k.stack then
          s.n = s.n + 1; stack_of[it.unit] = s; joined = true; break
        end
      end
      if not joined then
        stacks[#stacks + 1] = { kind = k, wid = wid, x = x, y = y, z = z, n = 1 }
        stack_of[it.unit] = stacks[#stacks]
      end
      local near = nil
      for _, p in ipairs(pickups) do
        if p.kind == k and p.wid == wid and (p.x - x) ^ 2 + (p.y - y) ^ 2 + (p.z - z) ^ 2 <= MARK_STACK * MARK_STACK then near = p; break end
      end
      if near then near.units[#near.units + 1] = it.unit
      else pickups[#pickups + 1] = { kind = k, wid = wid, units = { it.unit }, x = x, y = y, z = z } end
    end
  end
  M.foes, M.foe_i = hv, 0
  for _, k in ipairs(active) do
    local c = counts[k.id] or 0
    if c > (seen_max[k.id] or 0) then seen_max[k.id] = c end
  end
  -- drawn from the least important up, so where icons overlap the more important one is on top
  table.sort(stacks, function(a, b) return a.kind.rank > b.kind.rank end)
  local parts = {}
  for _, k in ipairs(active) do
    if not k.weapon and not k.enemy and (seen_max[k.id] or 0) > 0 then parts[#parts + 1] = k.id .. ' ' .. (counts[k.id] or 0) .. '/' .. seen_max[k.id] end
  end
  -- (a release logs the ledger once, at the mission's end)
  local line = table.concat(parts, ', ')
  M.last_line = line
end

-- has this weapon left the spot it was listed at (more than half a meter)? Each unit has its own spot: two of a weapon
-- lying together (an EAT drop) share one marker but not one spot. Asked with the scan's own call and key.
local function moved(u, p)
  local at = listed_at[u]
  if not at then return false end
  local v = chef.call_kind('Unit.world_position', p.wid or p.kind.id, u, 1)
  if v == nil then return false end
  local x, y, z = chef.call('Vector3.to_elements', v)
  if type(x) ~= 'number' then return false end
  local d2 = (x - at.x) ^ 2 + (y - at.y) ^ 2 + (z - (at.z or 0)) ^ 2
  if d2 > 0.25 then
    return true
  end
  return false
end

-- A picked-up pickup drops out at once (from its marker, its radar pile and the ledger), without waiting for the next
-- list. Only the ones near me are checked, ALIVE_EVERY seconds apart.
local function check_alive(cam)
  if chef.time() < next_alive then return end
  next_alive = chef.time() + ALIVE_EVERY
  local reach = min(cfg.markers or 0, 150) + 5      -- (farther ones go at the next list, as with Endless markers)
  local r2 = reach * reach
  for _, p in ipairs(pickups) do
    if (p.x - cam.x) ^ 2 + (p.y - cam.y) ^ 2 <= r2 then
      for _, u in ipairs(p.units) do
        -- a weapon picked up stays alive (it's in someone's hands now): it counts as gone once it has moved
        if not gone[u] and (chef.call_kind('Unit.alive', p.kind.id, u) ~= true or (p.kind.weapon and moved(u, p))
            or ((p.kind.dead_state or p.kind.dead_mesh) and is_destroyed(u, p.kind, struct_uk[u]))) then
          gone[u] = true
          gone_n[p.kind.id] = (gone_n[p.kind.id] or 0) + 1
          local s = stack_of[u]
          if s then s.n = s.n - 1 end
        end
      end
    end
  end
end

-- The enemies move, so while the radar shows I keep reading where they are: each one inside the radar's range (and
-- FOE.NEAR meters past it) every FOE.EVERY_NEAR seconds, the rest every FOE.EVERY_FAR, at most FOE.BUDGET reads a
-- frame. Each is checked alive first: asking a removed unit's position crashes the game. One that's gone drops off.
-- A killed enemy's body stays in the world, but its animation state machine goes away (a Hulk goes to state 12, then
-- has none). So once a kind of enemy has been seen with a state machine, one without is a body: it drops off and stays
-- off for the mission. A kind never seen with one stays shown (a live enemy is never hidden on a guess).
M.foes, M.foe_i, M.foe_dead = {}, 0, {}
-- kinds seen with a state machine while alive (SEAF troopers, Hulk, Hulk Scorcher, Tank, Factory Strider); others are
-- learned as seen
M.foe_asm = { ['7a3637cd33a54e4c'] = true, ['75f7e96af7dcd303'] = true, ['846bc06c6b213a06'] = true, ['b16493b009eec762'] = true, ['00bcf8247a544cdc'] = true, ['d37e8d120d2836e3'] = true,
  ['4d1c334d294dfa97'] = true }
local FOE = { BUDGET = 30, NEAR = 40, EVERY_NEAR = 0.1, EVERY_FAR = 1 }
-- The dying: an enemy keeps its state machine while it plays its death, so a dead one would linger a few seconds.
-- The last state each kind's dead were in before theirs went is its death state (seen DEATH_SEEN times, it counts):
-- one in it is hidden at once.
-- Some kinds die without leaving the state they stand around in (Nursing Spewers and Hunters go from state 0 straight
-- to no state machine): state 0 on the first layer is never learned as a death state, nor is the state one was in when
-- I first read it, or every live one standing in it would be hidden.
-- A state one is seen leaving for another (still with its state machine) is one the living use: it's never a death
-- state for that kind again (M.foe_live), so a live one isn't hidden every time it passes through it (Devastators
-- and SEAF troopers often end in a state they also walk around in).
-- The state call answers one state per animation layer (up to 4). Each layer is learned the same way, its states kept
-- as layer * M.LAYER + state (layer 1 as the bare state): a body layer that only the dead switch to shows a death the
-- first layer doesn't (SEAF troopers' layers 3 and 4 go to 197 and 43 as they die).
-- A body layer (2 to 4) that drops to 0 as one dies can show a death too (an Overseer's layer 3 sits at 3 its whole
-- life and goes to 0 when it dies), but only one I know from the start and only for one that wasn't at 0 when I first
-- read it. 0 is never learned: kinds like the Harvester switch a layer to 0 and back while alive.
-- So does the whole set of layers together (M.combo, a negative key), for kinds whose dead end in states the living
-- each use on their own but never all at once.
-- Only deaths that weren't already hidden teach anything: a kind whose dead are caught doesn't need more death
-- states, and every extra one is a chance to hide a live one.
-- And one still "dying" after M.DYING_MAX seconds is alive (a body loses its state machine within about 10 s): it
-- shows again, and that state is one the living use from then on.
-- Learned through the game session; known from the start: Hulk 12, Trooper 60, Commissar 60, Warrior 26, Hive Guard
-- 26, Brood Commander 24, Scavenger 18, Voteless 31 (all three), the SEAF trooper's layers 3 = 197, 4 = 43, the
-- Overseer's layer 3 = 0, the Crescent Overseer's layer 2 = 9 and the Elevated Overseer's layers 2 = 5, 3 = 2.
M.LAYER, M.DYING_MAX = 100000, 15
M.foe_death = { ['846bc06c6b213a06'] = { [12] = 2 }, ['b2b3056bdf28e57b'] = { [60] = 2 }, ['a71aafd82c6ebc92'] = { [60] = 2 },
  ['09872e66d1276e1f'] = { [26] = 2 }, ['a1f37bf2a40fbde4'] = { [26] = 2 }, ['d522fd4748d443a5'] = { [24] = 2 },
  ['c14e0e887e7d2106'] = { [18] = 2 }, ['78e1497571012c47'] = { [31] = 2 }, ['0adc9f9173ad8e1d'] = { [31] = 2 },
  ['44458a2c52b002fb'] = { [31] = 2 }, ['75f7e96af7dcd303'] = { [300197] = 2, [400043] = 2 },
  ['da40bb347c7447f2'] = { [300000] = 2 }, ['e8f19a0aa958e46d'] = { [200009] = 2 },
  ['604a794ec45bb820'] = { [200005] = 2, [300002] = 2 } }
M.foe_live = {}
M.lay = {}   -- the layer states of the enemy being read (one table for all)
-- every layer's state as one key (states 0-1023), or nil for a kind that answers one layer
function M.state_ok(s) return type(s) == 'number' and s >= 0 and s <= 1023 and s % 1 == 0 end
function M.combo(s1, s2, s3, s4)
  if type(s2) ~= 'number' then return nil end
  s3, s4 = s3 or 0, s4 or 0
  local ok = M.state_ok
  if not (ok(s1) and ok(s2) and ok(s3) and ok(s4)) then return nil end
  return -1 - (s1 + s2 * 1024 + s3 * 1048576 + s4 * 1073741824)
end
-- a layer state as I log it: "state 60", "layer 3 at 197" or "layers 4/10/1/1"
function M.say_state(k)
  if k < 0 then
    local c, s = -1 - k, {}
    for i = 1, 4 do s[i] = c % 1024; c = floor(c / 1024) end
    return 'layers ' .. table.concat(s, '/')
  end
  if k < M.LAYER then return 'state ' .. k end
  return string.format('layer %d at %d', floor(k / M.LAYER), k % M.LAYER)
end
local DEATH_SEEN = 2
-- Wrecks: a destroyed tank stays in the world with its state machine, settled in state 0 for good (every tank turret
-- rides the same hull). One that was in another state before is a wreck while it's in that state; one that's in it
-- from the start may be a live tank waiting, so it stays shown.
M.foe_wreck = { ['00bcf8247a544cdc'] = 0 }
M.learned = 0       -- death states learned this game session (for the mission summary)
local function foe_update(cam)
  local fs = M.foes
  local n = #fs
  if n == 0 then return end
  local now = chef.time()
  local near2 = (range_now + FOE.NEAR) ^ 2
  local reads = 0
  for _ = 1, n do
    M.foe_i = M.foe_i % n + 1
    local h = fs[M.foe_i]
    if not h.gone and (h.next or 0) <= now then
      reads = reads + 1
      local key = 'h' .. h.uk
      local alive = chef.call_kind('Unit.alive', key, h.unit) == true
      if alive then
        if chef.call_kind('Unit.has_animation_state_machine', key, h.unit) == true then
          M.foe_asm[h.uk] = true
          local s1, s2, s3, s4 = chef.call_kind('Unit.animation_get_state', key, h.unit)
          local lay = M.lay
          lay[1], lay[2], lay[3], lay[4], lay[5] = s1, s2, s3, s4, M.combo(s1, s2, s3, s4)
          -- (each enemy keeps its layer states, and the ones I first read it in, in two tables of its own; the
          -- combination of all its layers is the fifth)
          local ls, lf, lt = h.ls, h.lf, h.lt
          if not ls then ls, lf, lt = {}, {}, {}; h.ls, h.lf, h.lt = ls, lf, lt end
          local wk = M.foe_wreck[h.uk]
          local ds, lv = M.foe_death[h.uk], M.foe_live[h.uk]
          local was = h.dying
          h.dying = false
          for l = 1, 5 do
            local s = lay[l]
            local k = type(s) == 'number' and ((l == 1 or l == 5) and s or l * M.LAYER + s) or nil
            local old = ls[l]
            if h.lf_done == nil then lf[l] = k or false end
            -- it left old alive, so the living use old (a tank's wreck state counts only once it has moved before)
            if old and k and k ~= old and (old ~= wk or h.woke) then
              if not lv then lv = {}; M.foe_live[h.uk] = lv end
              if not lv[old] then
                lv[old] = true
              end
            end
            if k ~= old then lt[l] = now end
            ls[l] = k
            -- in one of its kind's death states: hidden now, though only for good once its state machine goes
            -- (a layer at 0 only if it wasn't at 0 when I first read this one)
            if k and not (lv and lv[k]) and ds and (ds[k] or 0) >= DEATH_SEEN and (k % M.LAYER ~= 0 or k ~= lf[l]) then
              h.dying = k
            end
          end
          h.lf_done = true
          h.st = ls[1]
          if wk and h.st and h.st ~= wk then h.woke = true end
          if h.woke and h.st == wk and not (lv and lv[wk]) then h.dying = wk end
          -- dying for too long: alive after all (a tank's wreck stays for good, so not a wreck)
          if not h.dying or h.dying ~= h.dk then h.dk, h.dt = h.dying, now end
          if h.dying and h.dying ~= wk and now - h.dt > M.DYING_MAX then
            if not lv then lv = {}; M.foe_live[h.uk] = lv end
            lv[h.dying] = true
            h.dying, h.dk = false, nil
          end
        elseif M.foe_asm[h.uk] then
          alive = false
          M.foe_dead[h.unit] = true
          -- the states it was in last are its kind's death states; each counts after DEATH_SEEN deaths. Only a state
          -- it went into in its last 30 s: a body lies at most about 20 s, and one it held longer is a live one.
          -- (Nothing to learn from one already hidden while dying.)
          local ls, lf, lt, lv = h.ls, h.lf, h.lt, M.foe_live[h.uk]
          for l = 1, (ls and not h.dying) and 5 or 0 do
            local k = ls[l]
            -- (a layer at 0 never, the first one included: that's where the idle stand)
            if k and not (k >= 0 and k % M.LAYER == 0) and k ~= lf[l] and not (lv and lv[k]) and now - (lt[l] or now) <= 30 then
              local ds = M.foe_death[h.uk] or {}
              M.foe_death[h.uk] = ds
              ds[k] = (ds[k] or 0) + 1
              if ds[k] == DEATH_SEEN then
                M.learned = M.learned + 1
              end
            end
          end
        end
      end
      local v = alive and chef.call_kind('Unit.world_position', key, h.unit, 1)
      local x, y, z
      if v then x, y, z = chef.call('Vector3.to_elements', v) end
      if type(x) == 'number' then h.x, h.y, h.z = x, y, z else h.gone = true end
      -- read again soon if it's on the radar or close to its edge, else in a while
      h.next = now + (((h.x or 0) - cam.x) ^ 2 + ((h.y or 0) - cam.y) ^ 2 <= near2 and FOE.EVERY_NEAR or FOE.EVERY_FAR)
      if reads >= FOE.BUDGET then break end
    end
  end
end

-- ------------------------------------------------------------------ drawing helpers
-- Colors only live for one frame in the engine. Each kind keeps one palette table, and its colors are made again on
-- its first use in a frame.
local pals = {}
local frame_no = 0
local function palette(k)
  local p = pals[k]
  if not p then p = { frame = -1 }; pals[k] = p end
  if p.frame ~= frame_no then
    p.frame = frame_no
    p.X, p.back, p.tint = chef.color(k.rgb[1], k.rgb[2], k.rgb[3], 255), chef.color(10, 10, 12, 200), chef.color(255, 255, 255, 255)
  end
  return p
end

-- Numbers and short labels: one bitmap per character, each at its own width, from the glyph size nearest what's drawn.
-- The text is 7 cells tall (the loader's pixel font's height), so everything lines up with it either way. Anything
-- else, or if the textures can't be used, goes to the loader's pixel font.
local glyph_ok = nil
local GAP = 0.14                        -- between characters, in cap heights
local function glyph_set(cap)
  local best = GLYPHS[#GLYPHS]
  for _, g in ipairs(GLYPHS) do if g.cap >= cap * 0.9 then best = g; break end end
  return best
end
local function glyph_ok_for(str) return glyph_ok ~= false and GLYPHS[1] ~= nil and not str:find('[^0-9MKX%.NESW ]') end
local function tw(str, size)
  if not glyph_ok_for(str) then return chef.text_width(str, size) end
  local cap, g = 7 * size, glyph_set(7 * size)
  local w = 0
  for i = 1, #str do
    local ch = str:sub(i, i)
    w = w + (ch == ' ' and 0.4 or g[ch][2]) * cap + (i > 1 and GAP * cap or 0)
  end
  return w
end
local function btext(x, y, str, size, c, layer)
  if glyph_ok_for(str) then
    local cap = 7 * size
    local g = glyph_set(cap)
    local pad = GLYPH_PAD * cap / g.cap
    local cx = x
    for i = 1, #str do
      local ch = str:sub(i, i)
      if ch == ' ' then cx = cx + 0.4 * cap + GAP * cap
      else
        local e = g[ch]
        local w = e[2] * cap
        if not chef.bitmap(e[1], cx - pad, y - pad, w + 2 * pad, cap + 2 * pad, c, layer) then
          glyph_ok = false
          chef.log('glyph textures not usable; numbers use the pixel font')
          break
        end
        cx = cx + w + GAP * cap
      end
    end
    if glyph_ok ~= false then glyph_ok = true; return end
  end
  chef.text(x, y, str, size, c, layer)
end
local function dist_text(d)
  if d < 1000 then return floor(d + 0.5) .. 'M' end
  return string.format('%.1fK', d / 1000)
end

-- ------------------------------------------------------------------ the radar
local rot_fx, rot_fy = 0, 1            -- my view on the ground, for Rotate With View
local function turn(dx, dy)
  if not cfg.rotate then return dx, dy end
  return dx * rot_fy - dy * rot_fx, dx * rot_fx + dy * rot_fy
end
local on_rim = {}
local function draw_radar(px, cam, cx, cy, R)
  local scale = (R - 8 * px) / range_now
  local fx, fy = cam.fx, cam.fy
  local len = sqrt(fx * fx + fy * fy)
  if len > 0.01 then fx, fy = fx / len, fy / len else fx, fy = 0, 1 end
  rot_fx, rot_fy = fx, fy
  -- the panel (with N E S W in it when north is up); without textures, a disc of rects
  local disc = cfg.rotate and TEXTURES.disc_plain or TEXTURES.disc
  if cfg.opacity > 0 and not (disc and chef.bitmap(disc, cx - R, cy - R, 2 * R, 2 * R, chef.color(255, 255, 255, A(255)), 900)) then
    local back, step = chef.color(8, 10, 12, A(150)), 4 * px
    for y = -R, R - step, step do
      local m = y + step / 2
      local half = sqrt(max(0, R * R - m * m))
      chef.rect(cx - half, cy + y, 2 * half, step, back, 900)
    end
    if not cfg.rotate then btext(cx - tw('N', px) / 2, cy + R - 12 * px, 'N', px, chef.color(255, 255, 255, A(160)), 945) end
  end
  if cfg.rotate then
    local lc = chef.color(GREEN[1], GREEN[2], GREEN[3], 175)
    for _, l in ipairs(RIM_LETTERS) do
      local nx, ny = turn(l[2], l[3])
      btext(cx + nx * R * 0.9 - tw(l[1], px) / 2, cy + ny * R * 0.9 - 3.5 * px, l[1], px, lc, 945)
    end
  end
  -- the sweep: one of its frames, a turn every SWEEP_T s, under the pickups. sweep = how far round it is, clockwise
  -- from the top, as drawn; each pickup lights up just after it passes.
  local sweep = nil
  local frames = TEXTURES.sweep
  if cfg.opacity > 0 and frames and frames[1] and not cfg.still then
    local n = #frames
    local i = floor((chef.time() % SWEEP_T) / SWEEP_T * n) % n
    if chef.bitmap(frames[i + 1], cx - R, cy - R, 2 * R, 2 * R, chef.color(255, 255, 255, A(255)), 905) then sweep = i / n * 2 * pi end
  end
  -- the pickups: beyond the range they sit on the edge, smaller (loot only, one per kind per spot), pointing the way
  local small = max(1, floor(px * 2 / 3))
  local rim_n = 0
  for _, s in ipairs(stacks) do
    local k = s.kind
    local dx, dy = s.x - cam.x, s.y - cam.y
    local d = sqrt(dx * dx + dy * dy)
    local edge = d > range_now
    if s.n > 0 and cfg.kinds[k.id] and not (edge and k.supply) then
      if edge then dx, dy = dx / d * range_now, dy / d * range_now end
      dx, dy = turn(dx, dy)
      -- every kind's icon about the same size, bigger near me and smaller far off (so the zoom changes it):
      -- 1.3x at my feet down to 0.7x at the range; on the edge (beyond the range) 0.6x
      local cell = max(1, px * (edge and 0.6 or (1.3 - 0.6 * min(1, d / range_now))))
      local half = 5.5 * cell
      local sx, sy = cx + dx * scale, cy + dy * scale
      local skip = false
      if edge then
        for i = 1, rim_n do
          local p = on_rim[i]
          if p[1] == k and (p[2] - sx) ^ 2 + (p[3] - sy) ^ 2 < (2.2 * half) ^ 2 then skip = true; break end
        end
        if not skip then
          rim_n = rim_n + 1
          local p = on_rim[rim_n]
          if p then p[1], p[2], p[3] = k, sx, sy else on_rim[rim_n] = { k, sx, sy } end
        end
      end
      if not skip then
        local pal = palette(k)
        -- layers: supplies at the bottom, then the loot, then the weapons on top (counts above all of them)
        local z = k.weapon and 925 or (k.supply and 910 or (k.structure and 915 or 920))
        local tint = pal.tint
        if sweep then
          local pulse = exp(-((sweep - atan2(dx, dy)) % (2 * pi)) / 0.5)
          if pulse > 0.08 and TEXTURES.glow then
            local g = half * 2.4
            chef.bitmap(TEXTURES.glow, sx - g, sy - g, 2 * g, 2 * g, chef.color(GLOW[1], GLOW[2], GLOW[3], floor(150 * pulse)), z - 1)
          end
          half = half * (1 + 0.12 * pulse)
          tint = chef.color(255, 255, 255, floor(255 * (0.72 + 0.28 * pulse)))
        end
        local tex, hw = k.texture, half
        if k.weapon then
          -- a weapon: its own silhouette, wide (as tall as a loot icon's middle, about 2.7 times as wide)
          tex = TEXTURES.weapons[s.wid] or TEXTURES.weapon_generic
          hw = half * 0.75 * WEAPON_ASPECT
          half = half * 0.75
        end
        if not (tex and chef.bitmap(tex, sx - hw, sy - half, 2 * hw, 2 * half, tint, z)) then
          half = 4.5 * cell; hw = half
          chef.rect(sx - half, sy - half, 9 * cell, 9 * cell, pal.back, z)
          chef.sprite(sx - half, sy - half, ICON[k.icon], cell, pal, z + 1)
        end
        if s.n > 1 and not edge then btext(sx + hw + px, sy - 3 * px / 2, tostring(s.n), small, pal.X, 930) end
      end
    end
  end
  -- the enemies and SEAF troopers, over the pickups, only inside the range (no edge markers for them): heavies as the
  -- skull, the rest as the dot (medium ones and troopers bigger), drawn after the dots so the skulls sit on top
  if #M.foes > 0 and (cfg.kinds.enemy or cfg.kinds.friend or cfg.kinds.squad) then
    local r2 = range_now * range_now
    for pass = 1, 2 do
      for _, h in ipairs(M.foes) do
        local fk = h.k
        if not h.gone and not h.dying and cfg.kinds[fk.id] and (h.tier == 3) == (pass == 2) then
          local pal = palette(fk)
          local dx, dy = h.x - cam.x, h.y - cam.y
          if dx * dx + dy * dy <= r2 then
            dx, dy = turn(dx, dy)
            local sx, sy = cx + dx * scale, cy + dy * scale
            local half = (h.tier == 3 and 5.5) or (h.tier == 2 and 2.6) or 1.8
            half = half * px
            -- the dot textures carry their color (the tint is white): red enemies, blue SEAF and civilians, green squad
            local tex = h.tier == 3 and fk.texture or fk.dot_tex
            if not (tex and chef.bitmap(tex, sx - half, sy - half, 2 * half, 2 * half, pal.tint, 926 + pass)) then
              if h.tier == 3 then
                chef.rect(sx - 4.5 * px, sy - 4.5 * px, 9 * px, 9 * px, pal.back, 927)
                chef.sprite(sx - 4.5 * px, sy - 4.5 * px, ICON[fk.icon], px, pal, 928)
              else
                chef.rect(sx - half, sy - half, 2 * half, 2 * half, pal.X, 926)
              end
            end
          end
        end
      end
    end
  end
  -- me, and which way I'm looking (always up with Rotate With View)
  local vx, vy = fx, fy
  if cfg.rotate then vx, vy = 0, 1 end
  local me, dark = chef.color(GREEN[1], GREEN[2], GREEN[3], 255), chef.color(12, 12, 14, 235)
  for i = 1, 5 do chef.rect(cx + vx * i * 2 * px - px, cy + vy * i * 2 * px - px, 2 * px, 2 * px, me, 941) end
  chef.rect(cx - 3 * px, cy - 3 * px, 6 * px, 6 * px, dark, 940)
  chef.rect(cx - 2 * px, cy - 2 * px, 4 * px, 4 * px, me, 941)
end

-- ------------------------------------------------------------------ the ledger
-- Left of the radar, its bottom level with the radar's. Each kind is a small tile, its icon over its count (a check
-- mark once it's cleared), with a thin line in its color along the top. Rows, top to bottom: the enemy structures,
-- then Super Credits, Medals and Requisition Slips, then the samples, then the supplies. A row shows the kinds the
-- mission has (seen at least once), right-aligned beside the radar; a cleared kind keeps its tile, dimmed, with a
-- gray line.
local LEDGER_ROWS = {
  { 'fabricator', 'bulkfab', 'ilship', 'bughole' },
  { 'credit', 'medal', 'requisition' },
  { 'common', 'rare', 'super' },
  { 'ammo', 'grenade', 'stim' },
}
local kind_by_id = {}
for _, k in ipairs(KINDS) do kind_by_id[k.id] = k end
-- the tile, in cells (one cell = px): width, height, the gap between tiles and between rows, the icon's size
local TILE_W, TILE_H, TILE_GAP, ROW_GAP, TILE_ICON = 15, 17, 1.5, 3, 8.5
-- the rows shown this frame, in tables kept from frame to frame (row_n[i]: how many kinds row i has now)
local rows, row_n = {}, {}
for i = 1, #LEDGER_ROWS do rows[i] = {} end
-- edge_x: the ledger's right edge, or its left edge with `left` (when the radar sits on the left of the screen)
local function draw_ledger(px, edge_x, bottom, left)
  local n = 0
  for _, ids in ipairs(LEDGER_ROWS) do
    local c = 0
    for _, id in ipairs(ids) do
      local k = kind_by_id[id]
      if k and cfg.kinds[id] and (seen_max[id] or 0) > 0 then
        if c == 0 then n = n + 1 end
        c = c + 1; rows[n][c] = k
      end
    end
    if c > 0 then row_n[n] = c end
  end
  if n == 0 then return end
  local tw_, th, tg, isz = TILE_W * px, TILE_H * px, TILE_GAP * px, TILE_ICON * px
  local y = bottom + n * (th + ROW_GAP * px) - ROW_GAP * px - th     -- the top row's bottom edge
  local fill, fill_done = chef.color(8, 12, 10, A(200)), chef.color(8, 12, 10, A(130))
  local gray, check, white, dim_icon = chef.color(90, 90, 90, A(230)), chef.color(140, 230, 140, 255),
    chef.color(245, 245, 245, 255), chef.color(255, 255, 255, 100)
  local ts = 0.56 * px                    -- the count's size (its capitals 3.9 cells tall)
  local cs = 6 * px                       -- the check mark
  local line = max(1, floor(px * 0.9 + 0.5))
  for r = 1, n do
    local ks, kn = rows[r], row_n[r]
    local x = floor((left and edge_x or edge_x - kn * tw_ - (kn - 1) * tg) + 0.5)
    for j = 1, kn do
      local k = ks[j]
      local left = max(0, (counts[k.id] or 0) - (gone_n[k.id] or 0))
      local done = left == 0
      local pal = palette(k)
      if cfg.opacity > 0 then
        if not (TEXTURES.tile and chef.bitmap(TEXTURES.tile, x, y, tw_, th, done and fill_done or fill, 900)) then
          chef.rect(x, y, tw_, th, done and fill_done or fill, 900)
        end
      end
      chef.rect(x + 1.2 * px, y + th - line, tw_ - 2.4 * px, line, done and gray or chef.color(k.rgb[1], k.rgb[2], k.rgb[3], A(230)), 902)
      local ix, iy = x + (tw_ - isz) / 2, y + th - 2.2 * px - isz
      if not (k.texture and chef.bitmap(k.texture, ix, iy, isz, isz, done and dim_icon or pal.tint, 910)) then
        chef.rect(ix, iy, isz, isz, pal.back, 909)
        chef.sprite(ix + (isz - 9 * px * 0.9) / 2, iy + (isz - 9 * px * 0.9) / 2, ICON[k.icon], px * 0.9, pal, 910)
      end
      if done then
        if not (TEXTURES.check and chef.bitmap(TEXTURES.check, x + (tw_ - cs) / 2, y + 1.2 * px, cs, cs, check, 920)) then
          chef.sprite(x + (tw_ - 9 * px * 0.6) / 2, y + 1.6 * px, CHECK, px * 0.6, { X = check }, 920)
        end
      else
        local num = tostring(left)
        btext(x + (tw_ - tw(num, ts)) / 2, y + 1.8 * px, num, ts, white, 920)
      end
      x = x + tw_ + tg
    end
    y = y - th - ROW_GAP * px
  end
end

-- ------------------------------------------------------------------ world markers
-- Each pile's icon over it in the world within cfg.markers meters, with how far it is and, for a pile, how many.
-- Placed through my view camera (the loader's world_to_screen). The Markers Key hides or shows them.
local function draw_markers(px, cam, w, h)
  if not (cfg.markers and markers_on and chef.world_to_screen) then return end
  local small = max(1, floor(px * 2 / 3))
  local my_z = cam.z - EYE
  local r2 = cfg.markers >= ENDLESS and math.huge or cfg.markers * cfg.markers
  for _, p in ipairs(pickups) do
    local dx, dy, dz = p.x - cam.x, p.y - cam.y, p.z - my_z
    local d2 = dx * dx + dy * dy + dz * dz
    if d2 <= r2 then
      local n = 0
      for _, u in ipairs(p.units) do if not gone[u] then n = n + 1 end end
      if n > 0 and cfg.kinds[p.kind.id] then
        local sx, sy = chef.world_to_screen(p.x, p.y, p.z + 0.8)
        if sx and sx > 0 and sx < w and sy > 0 and sy < h then
          local k = p.kind
          local pal = palette(k)
          local half = 4.1 * px                -- every kind the same size
          local tex, hw = k.texture, half
          if k.weapon then
            tex = TEXTURES.weapons[p.wid] or TEXTURES.weapon_generic
            half = 3.2 * px; hw = half * WEAPON_ASPECT
          end
          local zl = k.weapon and 882 or 880   -- a weapon's marker over the loot's
          if not (tex and chef.bitmap(tex, sx - hw, sy - half, 2 * hw, 2 * half, pal.tint, zl)) then
            chef.rect(sx - half, sy - half, 2 * half, 2 * half, pal.X, zl)
          end
          if n > 1 then btext(sx + hw + small, sy - 3 * small, tostring(n), small, pal.X, 885) end
          local t = dist_text(sqrt(d2))
          btext(sx - tw(t, small) / 2, sy - half - 8 * small, t, small, pal.X, 885)
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ every frame
-- The keys: hide, double-tap Tab, world markers.
local function read_keys()
  if any_key(cfg.hide) then hidden = not hidden; chef.log('radar %s (%s)', hidden and 'hidden' or 'shown', cfg.hide[1]) end
  -- tapping Tab twice quickly hides or shows the radar and the ledger, like the Hide Key (the two taps open and close
  -- the game's map, so it ends up closed); a third tap starts over
  if cfg.tab and chef.key_pressed('tab') then
    local t = chef.time()
    if tab_last and t - tab_last <= DOUBLE_TAP then
      tab_last, hidden = nil, not hidden
      chef.log('radar %s (Tab tapped twice)', hidden and 'hidden' or 'shown')
    else
      tab_last = t
    end
  end
  if cfg.markers and any_key(cfg.mark) then
    markers_on = not markers_on
    chef.log('world markers %s', markers_on and 'shown' or 'hidden')
  end
end

-- The drop: nothing is drawn while my camera falls fast and steadily (the Hellpod comes down at 200+ m/s for seconds,
-- a reinforcement too) and for a moment after it lands, and at a mission's start not until the first drop has landed
-- (or DROP_NONE s went by without one). A camera that jumps for a frame or two (aiming, a dive, a hit) isn't a drop:
-- the fall has to last DROP_FOR s, or the radar would blink out now and then.
local DROP_SPEED, DROP_FOR, DROP_AFTER, DROP_NONE = 40, 0.4, 2.5, 12
local drop = { mission = nil }
local function dropping(cam)
  local t = chef.time()
  if drop.mission ~= mission_id then
    drop = { mission = mission_id, start = t, z = cam.z, t = t, landed = false, fall_at = nil, since = nil }
    return true
  end
  local dt = t - drop.t
  if dt > 0 then
    local v = (drop.z - cam.z) / dt
    drop.z, drop.t = cam.z, t
    if v > DROP_SPEED then
      drop.since = drop.since or (t - dt)
      if t - drop.since >= DROP_FOR then
        drop.fall_at = t
      end
    else
      drop.since = nil
    end
  end
  if drop.fall_at then
    if t - drop.fall_at < DROP_AFTER then return true end
    if not drop.landed then drop.landed = true; chef.log('landed: the radar shows (%.1f s after the mission started)', t - drop.start) end
    return false
  end
  if drop.landed then return false end
  if t - drop.start >= DROP_NONE then drop.landed = true; chef.log('no drop seen in %d s: the radar shows', DROP_NONE); return false end
  return true
end

-- once a mission is over (back on the ship, or straight into the next): what its ledger ended on
function M.mission_over()
  if not M.live then return end
  M.live = false
  chef.log('mission over: %s | enemy death states learned so far: %d',
    (M.last_line or '') ~= '' and 'ledger ' .. M.last_line or 'no loot found', M.learned)
end
local hud_next = 0
local waiting_gen = nil
function M.update(dt)
  frame_no = frame_no + 1
  local here = chef.in_mission()
  if #active == 0 or not here then
    if not here then M.mission_over() end
    -- every kind unticked in the options menu, or no mission: the unit list rests
    if watch then watch.pause() end
    return
  end
  if chef.world_id() ~= mission_id then
    -- a new mission: nothing from the last one carries over
    M.mission_over()
    mission_id = chef.world_id()
    seen_max, counts, stacks, pickups, stack_of, gone, gone_n, listed_at = {}, {}, {}, {}, {}, {}, {}, {}
    struct_uk, dead.mission, dead.units = {}, mission_id, {}
    M.foes, M.foes_said, M.foe_dead, M.foe_i = {}, nil, {}, 0
    last_gen = watch and watch.generation or -1
    hud.no_id, hud.no_file, hud_next, M.last_line, M.weapons_said = nil, nil, 0, nil, nil
    if not M.keys_checked then M.keys_checked = true; check_keys() end
    local n = 0
    for _ in pairs(watch_kinds) do n = n + 1 end
    chef.log('new mission (world %d): watching %d unit kinds', mission_id, n)
  end
  M.live = true
  read_keys()
  -- nothing to draw: the unit list rests until something is shown again
  local markers_up = cfg.markers ~= nil and markers_on
  if hidden and not markers_up then
    if watch then watch.pause() end
    return
  end
  if not watch then watch = chef.watch(watch_kinds, 3)
  elseif not watch.active then
    -- back from a pause: the old piles may be out of date, so nothing is drawn until the fresh list is in
    watch.resume()
    waiting_gen = watch.generation
  end
  if not hidden then
    if any_key(cfg.zin) then zoom_step(-1) elseif any_key(cfg.zout) then zoom_step(1) end
  end
  if watch.generation ~= last_gen then
    last_gen = watch.generation
    rebuild(watch.items)
  end
  if waiting_gen then
    if watch.generation == waiting_gen then return end
    waiting_gen = nil
  end
  local cam = chef.camera()
  if not cam then return end
  check_alive(cam)
  if dropping(cam) then return end
  local w, h = chef.screen()
  local px = max(1, floor(h / 540 + 0.5))     -- 2 at 1080p, 3 at 1440p, 4 at 4K
  draw_markers(px, cam, w, h)
  if chef.time() >= hud_next then hud_next = chef.time() + HUD_EVERY; read_hud() end
  if hidden then return end
  local R = MY_RADIUS * h * cfg.scale
  local cx, cy, ledger_left = M.place(w, h, R)
  local ui = px * cfg.scale
  if M.logged ~= mission_id then
    M.logged = mission_id
    chef.log('screen %dx%d: radar at %d, %d (from the bottom left; position %s, moved %d, %d), radius %d, %s', w, h,
      floor(cx), floor(cy), tostring(cfg.pos), cfg.nudge_x, cfg.nudge_y, floor(R), cfg.rotate and 'turning with my view' or 'north up')
  end
  if cfg.radar then
    if cfg.kinds.enemy or cfg.kinds.friend or cfg.kinds.squad then foe_update(cam) end
    draw_radar(ui, cam, cx, cy, R)
    if zoom_note.text and chef.time() < zoom_note.until_t then
      btext(cx - tw(zoom_note.text, px) / 2, cy + R * 0.72, zoom_note.text, px, chef.color(255, 255, 255, 230), 945)
    end
  end
  if cfg.ledger then
    if ledger_left then draw_ledger(ui, cx + R + 6 * ui, cy - R, true) else draw_ledger(ui, cx - R - 6 * ui, cy - R) end
  end
end

function M.shutdown() end

return M
