-- HD2-Addon: mods/chef/treasure_radar
-- Treasure Radar 0.5.1 (a Chef Loader addon; the successor of Treasure Map 1.x)
-- What's still lying around in the mission: a round sonar radar where the game's map opens (bottom right) with an icon
-- for every pickup around me, a ledger of pills counting what's left of each kind, and markers floating over the
-- pickups near me in the world.
-- How: the loader lists my pickup kinds' units every 3 s (spread over frames) and I draw everything with its screen
-- drawing. The game's map can't be read from Lua, so the radar sits exactly where the map opens: the open map covers it.
-- Its spot follows the game's HUD Scale and HUD Edge Offset (read from the player's settings file).
-- Idle: nothing outside a mission; while the radar is hidden and the world markers are off, the unit list pauses too.

local chef = ...
local M = { version = '0.5.1' }
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
}
local CHECK = { '........X', '.......XX', '......XX.', 'X....XX..', 'XX..XX...', '.XXXX....', '..XX.....', '.........', '.........' }

-- The kinds, in ledger order (the most valuable first, supplies last), with their units' resource ids. Pickups of a
-- kind within `stack` meters of each other share one icon on the radar, with a count.
-- Enemy structures and side objectives aren't here on purpose: nothing Lua can read changes when one is destroyed or
-- done, so they would stay on the radar for the whole mission.
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
}
-- My textures (resource ids, filled in by the build): the icons, the radar panel, the sweep's frames, the ledger's pill,
-- the check mark, the blip glow, and the characters for numbers at four sizes.
local TEXTURES = {}
local GLYPHS, GLYPH_PAD = {}, 2
--@@ICON_TEXTURES@@
for i, k in ipairs(KINDS) do k.texture = TEXTURES[k.id]; k.rank = i end

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
local CALIBRATE = opt.calibrate == true                          -- HUD Calibration (Tester builds only)
local function A(a) return floor(a * OPACITY + 0.5) end

local TOGGLE_KEY, MARKER_KEY = 'f7', 'f8'
local HOLD_HIDE = 0.6                   -- seconds of holding Tab that hide or show the radar (a tap opens the map)
local SWEEP_T = 3                       -- seconds for one turn of the sweep
local ALIVE_EVERY = 0.1                 -- how often I check that the pickups near me are still there
local HUD_EVERY = 10                    -- how often I read the HUD settings again in a mission
local MARK_STACK = 2                    -- meters: pickups of a kind this close share one world marker
local EYE = 1.6                         -- my camera sits about this high above my feet
local RIM_LETTERS = { { 'N', 0, 1 }, { 'E', 1, 0 }, { 'S', 0, -1 }, { 'W', -1, 0 } }
local GREEN, GLOW = { 150, 255, 180 }, { 150, 255, 180 }

-- ------------------------------------------------------------------ zoom (the numpad's + and -)
-- The range steps through ZOOMS; the Arsenal range is where it starts, and the last zoom is remembered between
-- launches next to my log ("<range> <the Arsenal range it was zoomed from>": a new Arsenal pick starts over).
local ZOOMS = { 50, 75, 100, 150, 200, 250, 300, 400, 500 }
local ZOOM_IN_KEYS = { 'numpad +', 'num +', 'numpad plus' }      -- the numpad's (the main row's keys don't register)
local ZOOM_OUT_KEYS = { 'numpad -', 'num -', 'numpad minus' }
local ZOOM_FILE = nil
do
  local ok, dir = pcall(os.getenv, 'LOCALAPPDATA')
  if ok and type(dir) == 'string' and dir ~= '' then ZOOM_FILE = dir .. '\\treasure_radar_zoom.txt' end
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
  for _, k in ipairs(list) do if chef.key_pressed(k) then return true end end
  return false
end

-- ------------------------------------------------------------------ where the game's map opens
-- The game anchors its HUD's bottom-right corner 70 px from the right and 44 px from the bottom (at 1440 px; 0.0486
-- and 0.0306 screen heights). HUD Edge Offset slides that corner between the right edge of the 16:9 area in the middle
-- of the screen (1) and the screen's own edge (0). The map is a circle 296 px across its rim (0.2056 heights), the
-- same at any HUD Scale; its center sits MAP_DX left of and MAP_DY above the corner at HUD Scale 0.85, and moves a
-- little with HUD Scale (measured at 0.75, 0.85 and 1.25). My radar is a little smaller, so the open map covers it.
local CORNER_RIGHT, CORNER_BOTTOM, BASE_SCALE = 70 / 1440, 44 / 1440, 0.85
local MAP_DX, MAP_DY = 254.4 / 1440, 301.3 / 1440
local DX_PER_SCALE, DY_PER_SCALE = 34 / 1440, 63 / 1440
local MAP_RIM, MY_RADIUS = 0.2056, 0.19

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
for _, k in ipairs(KINDS) do
  if kind_on(k.id) then
    active[#active + 1] = k
    for _, u in ipairs(k.units) do kind_of_unit[u] = k; watch_kinds[u] = true end
  end
end
-- Every loot kind, ticked or not, is how the loader tells a small mission from the ship (it never has any). Supplies
-- aren't: I don't know that the ship has none.
if chef.mission_kinds then
  local loot = {}
  for _, k in ipairs(KINDS) do
    if not k.supply then for _, u in ipairs(k.units) do loot[u] = true end end
  end
  chef.mission_kinds(loot)
end
chef.log('kinds on: %d of %d | radar %s (%s%s) | ledger %s | range %d m | opacity %d%% | world markers %s', #active, #KINDS,
  tostring(SHOW_RADAR), opt.size or 'medium', ROTATE and ', turning with my view' or '', tostring(SHOW_LEDGER), range_now,
  floor(OPACITY * 100 + 0.5), MARKERS and (MARKERS .. ' m') or 'off')

local watch = nil
local mission_id = 0
local last_gen = -1
local hidden, markers_on = false, true
local tab_held, tab_toggled = nil, false
local seen_max, counts = {}, {}         -- per kind: the most seen at once this mission, how many in the last list
local stacks = {}                       -- the radar's piles: { kind, x, y, z, n }
local pickups = {}                      -- the world markers' piles (within MARK_STACK): { kind, units, x, y, z }
local stack_of = {}                     -- unit -> its radar pile
local gone, gone_n = {}, {}             -- picked up since the last list: unit -> true, kind id -> how many
local next_alive = 0

local function rebuild(items)
  counts, stacks, gone, gone_n, pickups, stack_of = {}, {}, {}, {}, {}, {}
  for _, it in ipairs(items) do
    local k = kind_of_unit[it.kind]
    if k then
      counts[k.id] = (counts[k.id] or 0) + 1
      local joined = false
      for _, s in ipairs(stacks) do
        if s.kind == k and (s.x - it.x) ^ 2 + (s.y - it.y) ^ 2 <= k.stack * k.stack then
          s.n = s.n + 1; stack_of[it.unit] = s; joined = true; break
        end
      end
      if not joined then
        stacks[#stacks + 1] = { kind = k, x = it.x, y = it.y, z = it.z or 0, n = 1 }
        stack_of[it.unit] = stacks[#stacks]
      end
      local z, near = it.z or 0, nil
      for _, p in ipairs(pickups) do
        if p.kind == k and (p.x - it.x) ^ 2 + (p.y - it.y) ^ 2 + (p.z - z) ^ 2 <= MARK_STACK * MARK_STACK then near = p; break end
      end
      if near then near.units[#near.units + 1] = it.unit
      else pickups[#pickups + 1] = { kind = k, units = { it.unit }, x = it.x, y = it.y, z = z } end
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
    if (seen_max[k.id] or 0) > 0 then parts[#parts + 1] = k.id .. ' ' .. (counts[k.id] or 0) .. '/' .. seen_max[k.id] end
  end
  local line = table.concat(parts, ', ')
  if line ~= M.last_line then M.last_line = line; chef.log('ledger: %s', line ~= '' and line or 'nothing found yet') end
end

-- A picked-up pickup drops out at once (from its marker, its radar pile and the ledger), without waiting for the next
-- list. Only the ones near me are checked, ALIVE_EVERY seconds apart.
local function check_alive(cam)
  if chef.time() < next_alive then return end
  next_alive = chef.time() + ALIVE_EVERY
  local reach = (MARKERS or 0) + 5
  local r2 = reach * reach
  for _, p in ipairs(pickups) do
    if (p.x - cam.x) ^ 2 + (p.y - cam.y) ^ 2 <= r2 then
      for _, u in ipairs(p.units) do
        if not gone[u] and chef.call_kind('Unit.alive', p.kind.id, u) ~= true then
          gone[u] = true
          gone_n[p.kind.id] = (gone_n[p.kind.id] or 0) + 1
          local s = stack_of[u]
          if s then s.n = s.n - 1 end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ drawing helpers
-- Colors only live for one frame in the engine, so each frame gets its own palettes (one per kind, made on first use).
local pals, pals_frame = {}, -1
local frame_no = 0
local function palette(k)
  if pals_frame ~= frame_no then pals, pals_frame = {}, frame_no end
  local p = pals[k]
  if not p then
    local r, g, b = k.rgb[1], k.rgb[2], k.rgb[3]
    p = { X = chef.color(r, g, b, 255), back = chef.color(10, 10, 12, 200), tint = chef.color(255, 255, 255, 255) }
    pals[k] = p
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
  if not ROTATE then return dx, dy end
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
  local disc = ROTATE and TEXTURES.disc_plain or TEXTURES.disc
  if OPACITY > 0 and not (disc and chef.bitmap(disc, cx - R, cy - R, 2 * R, 2 * R, chef.color(255, 255, 255, A(255)), 900)) then
    local back, step = chef.color(8, 10, 12, A(150)), 4 * px
    for y = -R, R - step, step do
      local m = y + step / 2
      local half = sqrt(max(0, R * R - m * m))
      chef.rect(cx - half, cy + y, 2 * half, step, back, 900)
    end
    if not ROTATE then btext(cx - tw('N', px) / 2, cy + R - 12 * px, 'N', px, chef.color(255, 255, 255, A(160)), 945) end
  end
  if ROTATE then
    local lc = chef.color(GREEN[1], GREEN[2], GREEN[3], 235)
    for _, l in ipairs(RIM_LETTERS) do
      local nx, ny = turn(l[2], l[3])
      btext(cx + nx * R * 0.9 - tw(l[1], px) / 2, cy + ny * R * 0.9 - 3.5 * px, l[1], px, lc, 945)
    end
  end
  -- the sweep: one of its frames, a turn every SWEEP_T s, under the pickups. sweep = how far round it is, clockwise
  -- from the top, as drawn; each pickup lights up just after it passes.
  local sweep = nil
  local frames = TEXTURES.sweep
  if OPACITY > 0 and frames and frames[1] then
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
    if s.n > 0 and not (edge and k.supply) then
      if edge then dx, dy = dx / d * range_now, dy / d * range_now end
      dx, dy = turn(dx, dy)
      local cell = (edge or k.supply) and max(1, px * 0.7) or px
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
        local z = k.supply and 910 or 920
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
        if not (k.texture and chef.bitmap(k.texture, sx - half, sy - half, 2 * half, 2 * half, tint, z)) then
          half = 4.5 * cell
          chef.rect(sx - half, sy - half, 9 * cell, 9 * cell, pal.back, z)
          chef.sprite(sx - half, sy - half, ICON[k.icon], cell, pal, z + 1)
        end
        if s.n > 1 and not edge then btext(sx + half + px, sy - 3 * px / 2, tostring(s.n), small, pal.X, 930) end
      end
    end
  end
  -- me, and which way I'm looking (always up with Rotate With View)
  local vx, vy = fx, fy
  if ROTATE then vx, vy = 0, 1 end
  local me, dark = chef.color(GREEN[1], GREEN[2], GREEN[3], 255), chef.color(12, 12, 14, 235)
  for i = 1, 5 do chef.rect(cx + vx * i * 2 * px - px, cy + vy * i * 2 * px - px, 2 * px, 2 * px, me, 941) end
  chef.rect(cx - 3 * px, cy - 3 * px, 6 * px, 6 * px, dark, 940)
  chef.rect(cx - 2 * px, cy - 2 * px, 4 * px, 4 * px, me, 941)
end

-- ------------------------------------------------------------------ the ledger
-- Left of the radar, its bottom level with the radar's: one pill per kind, outlined in the kind's color, its icon and
-- how many are left; a cleared kind's pill goes gray with a green check. A pill is two bitmaps (its dark fill, faded by
-- Opacity, and its outline).
local function draw_ledger(px, right_x, bottom)
  local n = 0
  for _, k in ipairs(active) do if (seen_max[k.id] or 0) > 0 then n = n + 1 end end
  if n == 0 then return end
  local lh, gap, lw = 12 * px, 2 * px, 32 * px
  local x0 = right_x - lw
  local y = bottom + n * (lh + gap) - gap - lh          -- the top pill's bottom edge
  local fill, fill_done, gray = chef.color(8, 10, 12, A(195)), chef.color(8, 10, 12, A(120)), chef.color(80, 80, 80, A(160))
  local check, white, dim_icon = chef.color(140, 230, 140, 255), chef.color(245, 245, 245, 255), chef.color(255, 255, 255, 100)
  local pills = TEXTURES.pill_fill and TEXTURES.pill_ring
  local isz, cs = 9.5 * px, 7.5 * px
  for _, k in ipairs(active) do
    if (seen_max[k.id] or 0) > 0 then
      local left = max(0, (counts[k.id] or 0) - (gone_n[k.id] or 0))
      local done = left == 0
      local pal = palette(k)
      if OPACITY > 0 then
        if not (pills and chef.bitmap(TEXTURES.pill_fill, x0, y, lw, lh, done and fill_done or fill, 900)) then
          chef.rect(x0, y, lw, lh, done and fill_done or fill, 900)
        end
        if pills then chef.bitmap(TEXTURES.pill_ring, x0, y, lw, lh, done and gray or chef.color(k.rgb[1], k.rgb[2], k.rgb[3], A(230)), 901) end
      end
      if not (k.texture and chef.bitmap(k.texture, x0 + 2.5 * px, y + (lh - isz) / 2, isz, isz, done and dim_icon or pal.tint, 910)) then
        chef.rect(x0 + 3 * px, y + 1.5 * px, 9 * px, 9 * px, pal.back, 909)
        chef.sprite(x0 + 3 * px, y + 1.5 * px, ICON[k.icon], px, pal, 910)
      end
      if done then
        if not (TEXTURES.check and chef.bitmap(TEXTURES.check, x0 + lw - 4.5 * px - cs, y + (lh - cs) / 2, cs, cs, check, 920)) then
          chef.sprite(x0 + lw - 12 * px, y + 1.5 * px, CHECK, px, { X = check }, 920)
        end
      else
        local num = tostring(left)
        btext(x0 + lw - 5 * px - tw(num, px), y + 2.5 * px, num, px, white, 920)
      end
      y = y - lh - gap
    end
  end
end

-- ------------------------------------------------------------------ world markers
-- Each pile's icon over it in the world within MARKERS meters, with how far it is and, for a pile, how many; supplies
-- smaller. Through my view camera (the loader's world_to_screen). F8 hides or shows them.
local function draw_markers(px, cam, w, h)
  if not (MARKERS and markers_on and chef.world_to_screen) then return end
  local small = max(1, floor(px * 2 / 3))
  local my_z = cam.z - EYE
  local r2 = MARKERS * MARKERS
  for _, p in ipairs(pickups) do
    local dx, dy, dz = p.x - cam.x, p.y - cam.y, p.z - my_z
    local d2 = dx * dx + dy * dy + dz * dz
    if d2 <= r2 then
      local n = 0
      for _, u in ipairs(p.units) do if not gone[u] then n = n + 1 end end
      if n > 0 then
        local sx, sy = chef.world_to_screen(p.x, p.y, p.z + 0.8)
        if sx and sx > 0 and sx < w and sy > 0 and sy < h then
          local k = p.kind
          local pal = palette(k)
          local half = (k.supply and 3 or 4.1) * px
          if not (k.texture and chef.bitmap(k.texture, sx - half, sy - half, 2 * half, 2 * half, pal.tint, 880)) then
            chef.rect(sx - half, sy - half, 2 * half, 2 * half, pal.X, 880)
          end
          if n > 1 then btext(sx + half + small, sy - 3 * small, tostring(n), small, pal.X, 885) end
          local t = dist_text(sqrt(d2))
          btext(sx - tw(t, small) / 2, sy - half - 8 * small, t, small, pal.X, 885)
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ HUD Calibration (Tester builds)
-- A thin magenta ring where I think the game's map rim is, a cross on its center, and the HUD settings written above
-- it, drawn over everything (the open map too). One screenshot with the map open per HUD setting shows how far off it
-- is. The settings are read every 2 s, so they can be changed mid-mission.
local cal_next = 0
local function draw_calibration(w, h, px)
  if chef.time() >= cal_next then cal_next = chef.time() + 2; read_hud() end
  local top = chef.TOP or 0
  local cx, cy = layout(w, h)
  local R = MAP_RIM * h
  local dot = max(2, floor(px * 2 / 3))
  local magenta = chef.color(255, 0, 255, 255)
  local n = 144
  for i = 0, n - 1 do
    local a = i / n * 2 * pi
    chef.rect(cx + math.cos(a) * R - dot / 2, cy + math.sin(a) * R - dot / 2, dot, dot, magenta, top + 960)
  end
  chef.rect(cx - 8 * px, cy - dot / 2, 16 * px, dot, magenta, top + 960)
  chef.rect(cx - dot / 2, cy - 8 * px, dot, 16 * px, magenta, top + 960)
  local label = string.format('SCALE %s OFFSET %s POS %s CURVE %s  %dx%d', hud.scale and string.format('%.2f', hud.scale) or '?',
    tostring(hud.offset or '?'), tostring(hud.map_position or '?'), tostring(hud.curve or '?'), w, h)
  chef.text(cx - chef.text_width(label, px) / 2, cy + R + 4 * px, label, px, magenta, top + 960)
end

-- ------------------------------------------------------------------ every frame
local hud_next = 0
local waiting_gen = nil
function M.update(dt)
  frame_no = frame_no + 1
  if #active == 0 then return end
  if not chef.in_mission() then
    if watch then watch.pause() end
    return
  end
  if chef.world_id() ~= mission_id then
    -- a new mission: nothing from the last one carries over
    mission_id = chef.world_id()
    seen_max, counts, stacks, pickups, stack_of, gone, gone_n = {}, {}, {}, {}, {}, {}, {}
    last_gen = watch and watch.generation or -1
    hud.no_id, hud.no_file, hud_next, M.last_line = nil, nil, 0, nil
    local n = 0
    for _ in pairs(watch_kinds) do n = n + 1 end
    chef.log('new mission (world %d): watching %d unit kinds', mission_id, n)
  end
  if chef.key_pressed(TOGGLE_KEY) then hidden = not hidden; chef.log('radar %s (F7)', hidden and 'hidden' or 'shown') end
  -- holding Tab hides or shows the radar and the ledger, like F7 (a tap still just opens the game's map)
  if chef.key_down('tab') then
    tab_held = tab_held or chef.time()
    if not tab_toggled and chef.time() - tab_held >= HOLD_HIDE then
      tab_toggled, hidden = true, not hidden
      chef.log('radar %s (Tab held)', hidden and 'hidden' or 'shown')
    end
  else
    tab_held, tab_toggled = nil, false
  end
  if MARKERS and chef.key_pressed(MARKER_KEY) then
    markers_on = not markers_on
    chef.log('world markers %s', markers_on and 'shown' or 'hidden')
  end
  -- nothing to draw: the unit list rests until something is shown again
  local markers_up = MARKERS ~= nil and markers_on
  if hidden and not markers_up and not CALIBRATE then
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
    if any_key(ZOOM_IN_KEYS) then zoom_step(-1) elseif any_key(ZOOM_OUT_KEYS) then zoom_step(1) end
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
  local w, h = chef.screen()
  local px = max(1, floor(h / 540 + 0.5))     -- 2 at 1080p, 3 at 1440p, 4 at 4K
  draw_markers(px, cam, w, h)
  if CALIBRATE then draw_calibration(w, h, px)
  elseif chef.time() >= hud_next then hud_next = chef.time() + HUD_EVERY; read_hud() end
  if hidden then return end
  local cx, cy = layout(w, h)
  local R = MY_RADIUS * h * MAP_SCALE
  local ui = px * MAP_SCALE
  if M.logged ~= mission_id then
    M.logged = mission_id
    chef.log('screen %dx%d: radar at %d, %d (from the bottom left), radius %d, %s', w, h, floor(cx), floor(cy),
      floor(R), ROTATE and 'turning with my view' or 'north up')
  end
  if SHOW_RADAR then
    draw_radar(ui, cam, cx, cy, R)
    if zoom_note.text and chef.time() < zoom_note.until_t then
      btext(cx - tw(zoom_note.text, px) / 2, cy + R * 0.72, zoom_note.text, px, chef.color(255, 255, 255, 230), 945)
    end
  end
  if SHOW_LEDGER then draw_ledger(ui, cx - R - 6 * ui, cy - R) end
end

function M.shutdown() end

return M
