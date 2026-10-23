-- HD2-Addon: mods/chef/treasure_radar
-- Treasure Radar 0.6.0 (a Chef Shared Loader addon; the successor of Treasure Map 1.x)
-- What's still lying around in the mission: a round sonar radar beside where the game's map opens (bottom right), with an icon
-- for every pickup around me, a ledger of tiles counting what's left of each kind, and markers floating over the
-- pickups near me in the world. Weapons on the ground (optional) show with their own silhouettes, outside the ledger.
-- The settings are Arsenal options, and can be changed in game in the loader's options menu (F9).
-- How: the loader lists my pickup kinds' units every 3 s (spread over frames) and I draw everything with its screen
-- drawing. Nothing Lua can read says the map is open, so the radar sits just left of it, level with it, where the open
-- map never covers it and it never covers the map. Its spot follows the game's HUD Scale and HUD Edge Offset (read from the player's settings file).
-- Idle: nothing outside a mission; while the radar is hidden and the world markers are off, the unit list pauses too.

local chef = ...
-- my lines go to treasure_radar.log next to the loader's log (Chef Shared Loader 1.0.0 and newer); an older loader
-- keeps them in chef_loader.log
if type(chef.own_log) == 'function' then chef.own_log('treasure_radar') end
local M = { version = '0.6.0' }
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
}
local CHECK = { '........X', '.......XX', '......XX.', 'X....XX..', 'XX..XX...', '.XXXX....', '..XX.....', '.........', '.........' }

-- The kinds, in ledger order (the most valuable first, supplies last), with their units' resource ids. Pickups of a
-- kind within `stack` meters of each other share one icon on the radar, with a count.
-- Enemy structures are here only when I know how a destroyed one looks (it drops off then). Side objectives and Bile
-- Titan holes aren't: nothing I've seen change on them yet, so they would stay on the radar for the whole mission.
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
  -- (0.6.0) Enemy Structures, in Treasure Map 1.4.0's deep red. A destroyed fabricator stays in the world: its animation
  -- state goes to 3 (`dead_state`; the same reading Objective Tracker uses for bot outposts). A destroyed warp ship
  -- stays in the world too: its meshes swap (`dead_mesh`, below).
  { id = 'fabricator', say = 'fabricator', icon = 'fab', rgb = { 190, 20, 30 }, stack = 5, structure = true, dead_state = 3, units = { 'a57ae2a703c02899' } },
  -- (Test 20) The Bulk Fabricator (colony_cyborg_spawner; its entity is named "Bulk Fabricator" in the game's data). Its
  -- state stays 0 when it's destroyed (Test 20 log), but its meshes swap: whole, meshes 1-3 and 17-20 show; destroyed,
  -- 1-3 hide and the rubble (4-16) shows. So it's destroyed once its first mesh hides (`dead_mesh`).
  { id = 'bulkfab', say = 'Bulk Fabricator', icon = 'bfab', rgb = { 190, 20, 30 }, stack = 8, structure = true, dead_mesh = 1, units = { 'a2a86454f67fbc47' } },
  -- (Test 29) A destroyed warp ship stays in the world too (my Test 28): it has no state machine, but its 16 meshes swap
  -- like the Bulk Fabricator's. Whole, meshes 4-6 and 12-16 show (0001110000011111); destroyed, 1-3 and 7-11 show and
  -- 4-6 hide (1110001111100000). So it's destroyed once mesh 4 hides.
  { id = 'ilship', say = 'warp ship', icon = 'ship', rgb = { 190, 20, 30 }, stack = 5, structure = true, dead_mesh = 4, units = { 'f5f3207ca1b3a5d6' } },
  -- (Test 30) Bug holes (small, medium, large and ceiling; the HD2 Codex's unit ids), the tunnel icon I picked for
  -- Treasure Map 1.4.0. (Test 31) A closed hole swaps its meshes exactly like a destroyed warp ship (my Test 30 log:
  -- no state machine, 16 meshes, open 0001110000011111, closed 1110001111100000), so it's closed once mesh 4 hides.
  { id = 'bughole', say = 'bug hole', icon = 'hole', rgb = { 190, 20, 30 }, stack = 5, structure = true, dead_mesh = 4,
    units = { '2e454bd4d24eb04a', 'a83587cbff25c79e', 'd6a27adb179ad4ff', '3b3327050e8c2c23' } },
  -- support weapons and expendables lying on the ground (a fallen Helldiver's, one set down, an unused drop), each
  -- drawn with its own silhouette (the game's marker icon); never in the ledger. Same weapons within `stack` share an icon.
  { id = 'weapon', icon = 'gun', rgb = { 235, 235, 235 }, stack = 1, weapon = true,
    units = { '6cfcc7f8801a0266', 'a8cffb316f0b5c5f', '89c5493e08ca4207', '96de9cd50f7306e6', '78a8185f63a70795',
              '80932fa0ed6901d3', '7617642765ac38c7', 'b2b5e0d185605f9e', '25aa2fd4643cf4ee', '39ab99895147a3bf',
              '02eecd0b1fa49630', '88c2d09ad85a7c9f', 'fe3b29b2cfa63f9b', '9f80d67a12a7e40f', 'd54b9505c0f72873',
              '35a61296619cc47e', '43a58cb89cfa197c', 'a6a735accb4a327f', '2152d5147b0ac418', '11c27d3babb38956',
              'b16c9d490aa59b77', '5990123d142b16cb', 'e8d5f49ad7780e54', '26e40437ea275296', '2e9d0bdc48b09e60',
              '3828e2051aa9e897', 'cc786f6491fe7e65', '43b2d7766120203b', '52071f49263415e4' } },
}
-- A Helldiver (any player): a weapon held or on someone's back sits up at their hands or back, a dropped one on the
-- ground (also next to a body), so weapons near a Helldiver and CARRY_UP above their feet are carried, not shown.
local DIVER = '4d1c334d294dfa97'
-- Everyone who can carry a support weapon: Helldivers (avatar_helldiver; fp_cha_avatar, the first-person one) and SEAF
-- troopers (cha_seaf, cha_battlefront_seaf: their specialists carry EATs and machine guns). (Test 10: weapons on
-- SEAF troopers' backs showed on the radar.)
local CARRIERS = { [DIVER] = true, ['d0cf4d493ca08bed'] = true, ['7a3637cd33a54e4c'] = true, ['75f7e96af7dcd303'] = true }
local CARRY_NEAR, CARRY_UP_MIN, CARRY_UP_MAX = 1.2, 0.5, 2.3
-- (Test 11: SEAF weapons still showed, logged 0.4-1.9 m from a trooper and -0.7 to 0.4 m up from his position, and
-- moving between lists) Near a carrier in this wider reach, a weapon only counts as lying on the ground once it has
-- stayed put from one list to the next: a trooper's weapon moves with him, one dropped by a body doesn't.
local NEAR_REACH, NEAR_DOWN, NEAR_UP, STILL_M = 2.5, -1.5, 2.5, 0.3
-- My textures (resource ids, filled in by the build): the icons, the radar panel, the sweep's frames, the ledger's tile,
-- the check mark, the blip glow, and the characters for numbers at six sizes.
local TEXTURES = { weapons = {} }       -- weapons: unit id -> its silhouette (128 x 48); weapon_generic for the rest
local GLYPHS, GLYPH_PAD = {}, 2
local TEXTURES_UI = {}                  -- texture -> its copy for the UI world (below native Render Scale)
-- texture -> its ladder of pre-shrunk sizes (the UI material has no mipmaps, so a texture shrunk by half or more draws
-- with stair-step edges): the loader draws the one nearest the size I ask for
local TEXTURE_SIZES = {}
--@@ICON_TEXTURES@@
if chef.ui_textures then chef.ui_textures(TEXTURES_UI) end
if chef.texture_sizes then chef.texture_sizes(TEXTURE_SIZES) end
for i, k in ipairs(KINDS) do k.texture = TEXTURES[k.id]; k.rank = i end
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
-- (Test 30) The settings as they are now: the Arsenal options above to start with, then whatever the player changes in
-- the loader's options menu (F9, when the loader has one; saved between launches). Everything below reads cfg, so a
-- change shows at once. One table rather than a local each also keeps the drawing functions under Lua 5.1's 60 upvalues.
local cfg = { radar = SHOW_RADAR, ledger = SHOW_LEDGER, scale = MAP_SCALE, rotate = ROTATE, markers = MARKERS,
              opacity = OPACITY, still = STILL, kinds = {} }
for _, k in ipairs(KINDS) do cfg.kinds[k.id] = kind_on(k.id) end
local ENDLESS = 10000                   -- World Markers at this range or more: no limit (Test 30: "endless draw distance")
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
-- Double-Tap Tab To Hide (ticked by default). Until Test 21 it was Hold Tab To Hide: the option keeps its old folder
-- (tabhold) and key (tab_hold), so a player's tick carries over.
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

-- ------------------------------------------------------------------ zoom (the Zoom Keys; the numpad's + and - by default)
-- The range steps through ZOOMS; the Arsenal range is where it starts, and the last zoom is remembered between
-- launches: by the options menu's Range row, or (an older loader without the menu) next to my log ("<range> <the
-- Arsenal range it was zoomed from>": a new Arsenal pick starts over).
local ZOOMS = { 50, 75, 100, 150, 200, 250, 300, 400, 500 }
local ZOOM_FILE = nil
-- the loader's options menu (Chef Shared Loader 1.0.0 and newer) saves the range itself; the zoom file is only for an
-- older loader without one
local HAS_MENU = type(chef.has) == 'function' and chef.has('menu') and type(chef.option) == 'function'
if not HAS_MENU then
  -- the loader's folder (chef.log_directory), else %LOCALAPPDATA% (where loaders without the options menu kept it)
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
-- of the screen (1) and the screen's own edge (0). The map is a circle with a 296 px radius to its rim (0.2056 heights),
-- the same at any HUD Scale; its center sits MAP_DX left of and MAP_DY above the corner at HUD Scale 0.85, and moves a
-- little with HUD Scale (measured at 0.75, 0.85 and 1.25).
local CORNER_RIGHT, CORNER_BOTTOM, BASE_SCALE = 70 / 1440, 44 / 1440, 0.85
local MAP_DX, MAP_DY = 254.4 / 1440, 301.3 / 1440
local DX_PER_SCALE, DY_PER_SCALE = 34 / 1440, 63 / 1440
local MAP_RIM, MY_RADIUS = 0.2056, 0.19
-- (Test 20) Nothing tells me the map is open (Tests 6-18: I could see a stratagem code and chat in my Helldiver's pose,
-- never the map), and following Tab is messy, so the radar no longer sits where the map opens: it sits just left of the
-- map's rim, its center level with the map's, and follows the HUD settings the same way. MAP_GAP: the space between
-- the two rims, in screen heights.
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

-- the map's center on screen (pixels, bottom-left origin)
local function layout(w, h)
  local area = min(w, h * 16 / 9)
  local off = hud.offset
  if type(off) ~= 'number' or off < 0 or off > 1 then off = 1 end
  local ds = hud_scale() - BASE_SCALE
  local right = w - off * (w - area) / 2 - CORNER_RIGHT * h
  return right - (MAP_DX + ds * DX_PER_SCALE) * h, CORNER_BOTTOM * h + (MAP_DY + ds * DY_PER_SCALE) * h
end

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
      active[#active + 1] = k
      for _, u in ipairs(k.units) do kind_of_unit[u] = k; watch_kinds[u] = true end
      if k.weapon then WEAPONS_ON = true end
    end
  end
  -- with Weapons on, the Helldivers are listed too (only to tell a carried weapon from a dropped one)
  if WEAPONS_ON then for id in pairs(CARRIERS) do watch_kinds[id] = true end end
end
apply_kinds()
-- Every loot kind, ticked or not, is how the loader tells a small mission from the ship (it never has any). Supplies
-- weapons and structures aren't: I don't know that the ship has none.
if chef.mission_kinds then
  local loot = {}
  for _, k in ipairs(KINDS) do
    if not k.supply and not k.weapon and not k.structure then for _, u in ipairs(k.units) do loot[u] = true end end
  end
  chef.mission_kinds(loot)
end

local watch = nil
local mission_id = 0

-- ------------------------------------------------------------------ the loader's options menu (F9)
-- Every setting again in the menu (with a loader that has one: Chef Shared Loader 1.0.0 and newer). Each row
-- starts at the Arsenal pick; a change applies at once and is saved by the loader. The keys are key rows the player
-- binds by pressing a key; their defaults are the Arsenal keys.
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
    choice('markers', 'World markers', { 'Off', '25 M', '50 M', '100 M', '200 M', 'Endless' },
      { false, 25, 50, 100, 200, ENDLESS * 10 }, cfg.markers or false, function(v) cfg.markers = v or nil end)
    toggle('tab', 'Double-tap Tab to hide', cfg.tab, function(v) cfg.tab = v end)
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
    -- the kinds
    local NAMES = { credit = 'Super Credits', medal = 'Medals', common = 'Common Samples', rare = 'Rare Samples',
      super = 'Super Samples', requisition = 'Requisition Slips', ammo = 'Ammo Boxes', grenade = 'Grenade Packs',
      stim = 'Stim Packs', fabricator = 'Fabricators', bulkfab = 'Bulk Fabricators', ilship = 'Warp Ships',
      bughole = 'Bug Holes', weapon = 'Weapons' }
    for _, k in ipairs(KINDS) do
      toggle('kind_' .. k.id, 'Show ' .. (NAMES[k.id] or k.id), cfg.kinds[k.id], function(v)
        if cfg.kinds[k.id] ~= v then
          cfg.kinds[k.id] = v
          apply_kinds()
          if watch then watch.refresh() end
        end
      end)
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

-- Has this structure been destroyed? A fabricator's animation state reaches its kind's dead_state. Every unit is asked
-- whether it has a state machine before its state is read (one without crashes the game when asked; Objective Tracker
-- found a colony fabricator like that), each call under its own unit kind's crash key (one bug hole type that
-- misbehaves can't silence the other three).
local function is_destroyed(u, k, uk)
  if dead.mission ~= chef.world_id() then dead.mission, dead.units = chef.world_id(), {} end
  if dead.units[u] then return true end
  local key = 's' .. (uk or k.id)
  if k.dead_mesh then
    local m = chef.call_kind('Unit.mesh', key, u, k.dead_mesh)
    if m ~= nil and chef.call_kind('Mesh.visibility', key, m) == false then
      dead.units[u] = true
      chef.log('a %s was destroyed (mesh %d hidden)', k.say, k.dead_mesh)
      return true
    end
    return false
  end
  if not k.dead_state then return false end
  if chef.call_kind('Unit.has_animation_state_machine', key, u) ~= true then return false end
  local st = chef.call_kind('Unit.animation_get_state', key, u)
  if type(st) ~= 'number' then return false end
  if st >= k.dead_state then
    dead.units[u] = true
    chef.log('a %s was destroyed (state %d)', k.say, st)
    return true
  end
  return false
end

-- a weapon up at a Helldiver's hands or back (near them, CARRY_UP above their feet) is carried
-- Expendables (EAT-17, EAT-700, EAT-411, MGX-42, MLS-4X) are thrown down once spent and keep their unit (Test 11).
local EXPENDABLE = { ['80932fa0ed6901d3'] = 'EAT-17', ['b2b5e0d185605f9e'] = 'EAT-700', ['7617642765ac38c7'] = 'EAT-411',
  ['b16c9d490aa59b77'] = 'MGX-42', ['5990123d142b16cb'] = 'MLS-4X' }
-- (Test 13, my EAT test) A loaded EAT-17 on the ground is in animation state 2; once fired and thrown down it's in
-- state 0, every mesh still showing. So an expendable on the ground in state 0 is a spent tube and isn't shown. (The
-- others are taken to work the same way until seen otherwise.)
local function spent(it)
  if not EXPENDABLE[it.kind] then return false end
  local key = 'x' .. it.kind
  if chef.call_kind('Unit.has_animation_state_machine', key, it.unit) ~= true then return false end
  return chef.call_kind('Unit.animation_get_state', key, it.unit) == 0
end
local last_at = {}            -- a weapon unit -> where the previous list had it (to tell a still one from a carried one)
local function carried(it, divers)
  local z = it.z or 0
  local near = false
  for i = 1, #divers do
    local d = divers[i]
    local up = z - (d.z or 0)
    local h2 = (d.x - it.x) ^ 2 + (d.y - it.y) ^ 2
    if up >= CARRY_UP_MIN and up <= CARRY_UP_MAX and h2 <= CARRY_NEAR * CARRY_NEAR then return true end
    if up >= NEAR_DOWN and up <= NEAR_UP and h2 <= NEAR_REACH * NEAR_REACH then near = true end
  end
  if not near then return false end
  -- near someone: carried unless it lay in the same spot at the last list too
  local was = last_at[it.unit]
  return not (was and (was.x - it.x) ^ 2 + (was.y - it.y) ^ 2 + ((was.z or 0) - z) ^ 2 <= STILL_M * STILL_M)
end
local weapons_said = nil

local function rebuild(items)
  counts, stacks, gone, gone_n, pickups, stack_of, listed_at, struct_uk = {}, {}, {}, {}, {}, {}, {}, {}
  local divers, n_carried, n_spent = {}, 0, 0
  if WEAPONS_ON then
    for _, it in ipairs(items) do if CARRIERS[it.kind] then divers[#divers + 1] = it end end
  end
  local spots = {}
  for _, it in ipairs(items) do
    local k = kind_of_unit[it.kind]
    if k and k.weapon then spots[it.unit] = it end
    if k and k.weapon and spent(it) then
      n_spent = n_spent + 1
      k = nil
    elseif k and k.weapon and carried(it, divers) then
      n_carried = n_carried + 1
      k = nil
    end
    if k and k.structure then struct_uk[it.unit] = it.kind end
    if k and k.structure and is_destroyed(it.unit, k, it.kind) then k = nil end
    if k then
      counts[k.id] = (counts[k.id] or 0) + 1
      -- weapons pile up only with the same weapon (each has its own silhouette)
      local wid = k.weapon and it.kind or nil
      if wid then listed_at[it.unit] = it end
      local joined = false
      for _, s in ipairs(stacks) do
        if s.kind == k and s.wid == wid and (s.x - it.x) ^ 2 + (s.y - it.y) ^ 2 <= k.stack * k.stack then
          s.n = s.n + 1; stack_of[it.unit] = s; joined = true; break
        end
      end
      if not joined then
        stacks[#stacks + 1] = { kind = k, wid = wid, x = it.x, y = it.y, z = it.z or 0, n = 1 }
        stack_of[it.unit] = stacks[#stacks]
      end
      local z, near = it.z or 0, nil
      for _, p in ipairs(pickups) do
        if p.kind == k and p.wid == wid and (p.x - it.x) ^ 2 + (p.y - it.y) ^ 2 + (p.z - z) ^ 2 <= MARK_STACK * MARK_STACK then near = p; break end
      end
      if near then near.units[#near.units + 1] = it.unit
      else pickups[#pickups + 1] = { kind = k, wid = wid, units = { it.unit }, x = it.x, y = it.y, z = z } end
    end
  end
  for _, k in ipairs(active) do
    local c = counts[k.id] or 0
    if c > (seen_max[k.id] or 0) then seen_max[k.id] = c end
  end
  -- drawn from the least important up, so where icons overlap the more important one is on top
  table.sort(stacks, function(a, b) return a.kind.rank > b.kind.rank end)
  local parts = {}
  for _, k in ipairs(active) do
    if not k.weapon and (seen_max[k.id] or 0) > 0 then parts[#parts + 1] = k.id .. ' ' .. (counts[k.id] or 0) .. '/' .. seen_max[k.id] end
  end
  local line = table.concat(parts, ', ')
  if line ~= M.last_line then M.last_line = line; chef.log('ledger: %s', line ~= '' and line or 'nothing found yet') end
  if WEAPONS_ON then
    local w = string.format('%d on the ground, %d carried, %d spent, %d Helldivers and SEAF', counts.weapon or 0, n_carried, n_spent, #divers)
    if w ~= weapons_said then weapons_said = w; chef.log('weapons: %s', w) end
    last_at = spots
  end
end

-- has this weapon left the spot it was listed at (more than half a meter)? Its own spot: two of a weapon lying
-- together (an EAT drop) share one marker but not one spot. Asked with the scan's own call and key.
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
          if p.kind.weapon then last_at[u] = nil end
          local s = stack_of[u]
          if s then s.n = s.n - 1 end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ drawing helpers
-- Colors only live for one frame in the engine, so each frame gets its own palettes (one per kind, made on first use).
-- Each kind keeps one palette table; its colors are made again on its first use in a frame.
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
      -- (Test 30: every icon about the same size, bigger near me and smaller far off, and the zoom changes it)
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
  -- me, and which way I'm looking (always up with Rotate With View)
  local vx, vy = fx, fy
  if cfg.rotate then vx, vy = 0, 1 end
  local me, dark = chef.color(GREEN[1], GREEN[2], GREEN[3], 255), chef.color(12, 12, 14, 235)
  for i = 1, 5 do chef.rect(cx + vx * i * 2 * px - px, cy + vy * i * 2 * px - px, 2 * px, 2 * px, me, 941) end
  chef.rect(cx - 3 * px, cy - 3 * px, 6 * px, 6 * px, dark, 940)
  chef.rect(cx - 2 * px, cy - 2 * px, 4 * px, 4 * px, me, 941)
end

-- ------------------------------------------------------------------ the ledger
-- Left of the radar, its bottom level with the radar's. (0.6.0 Test 23) The ledger as tiles: each kind a small square, its icon over its count (a check mark once it's
-- cleared), with a thin line in its color along the top. Rows, top to bottom: the enemy structures, then Super Credits,
-- Medals and Requisition Slips, then the samples, then the supplies. A row shows the kinds the mission has (seen at
-- least once), right-aligned beside the radar; a cleared kind keeps its tile, dimmed, with a gray line.
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
local function draw_ledger(px, right_x, bottom)
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
    local x = floor(right_x - kn * tw_ - (kn - 1) * tg + 0.5)
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
-- Each pile's icon over it in the world within cfg.markers meters, with how far it is and, for a pile, how many; supplies
-- smaller. Through my view camera (the loader's world_to_screen). F8 hides or shows them.
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
          local half = 4.1 * px                -- (Test 30) every kind the same size
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
  -- the game's map again, so it ends up closed); a third tap starts over. Unticking Double-Tap Tab To Hide turns this off.
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
-- the fall has to last DROP_FOR s. (Test 10 hid on any one fast frame, and the radar blinked out now and then.)
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
        if not drop.fall_at or t - drop.fall_at > DROP_AFTER then chef.log('drop: falling (%.0f m/s)', v) end
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

local hud_next = 0
local waiting_gen = nil
function M.update(dt)
  frame_no = frame_no + 1
  if #active == 0 or not chef.in_mission() then
    -- every kind unticked in the options menu, or no mission: the unit list rests
    if watch then watch.pause() end
    return
  end
  if chef.world_id() ~= mission_id then
    -- a new mission: nothing from the last one carries over
    mission_id = chef.world_id()
    seen_max, counts, stacks, pickups, stack_of, gone, gone_n, listed_at = {}, {}, {}, {}, {}, {}, {}, {}
    last_at, struct_uk, dead.mission, dead.units = {}, {}, mission_id, {}
    last_gen = watch and watch.generation or -1
    hud.no_id, hud.no_file, hud_next, M.last_line, weapons_said = nil, nil, 0, nil, nil
    if not M.keys_checked then M.keys_checked = true; check_keys() end
    local n = 0
    for _ in pairs(watch_kinds) do n = n + 1 end
    chef.log('new mission (world %d): watching %d unit kinds', mission_id, n)
  end
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
  local cx, cy = layout(w, h)
  local R = MY_RADIUS * h * cfg.scale
  -- (Test 20) beside the map, not under it: left of the map's rim by MAP_GAP, its center level with the map's
  cx = cx - MAP_RIM * h - MAP_GAP * h - R
  local ui = px * cfg.scale
  if M.logged ~= mission_id then
    M.logged = mission_id
    chef.log('screen %dx%d: radar at %d, %d (from the bottom left), radius %d, %s', w, h, floor(cx), floor(cy),
      floor(R), cfg.rotate and 'turning with my view' or 'north up')
  end
  if cfg.radar then
    draw_radar(ui, cam, cx, cy, R)
    if zoom_note.text and chef.time() < zoom_note.until_t then
      btext(cx - tw(zoom_note.text, px) / 2, cy + R * 0.72, zoom_note.text, px, chef.color(255, 255, 255, 230), 945)
    end
  end
  if cfg.ledger then draw_ledger(ui, cx - R - 6 * ui, cy - R) end
end

function M.shutdown() end

return M
