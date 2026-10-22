-- Chef Loader - the game's `boot` script, replaced
-- Loads my Lua addons on the Lua 5.1 game build (7.2.0 and later), where the older loaders and LuaJIT's ffi are gone.
-- What it's built on:
--   * the game runs `boot` at start-up and calls its init/update/render/shutdown; its own boot does nothing
--   * Lua can read the deployed patch files (io), so I find addons myself: Lua resources whose text starts with
--     "-- HD2-Addon: mods/chef/<name>", and option resources starting with "-- HD2-Options: mods/chef/<name>"
--   * loadstring runs them; every addon gets its own environment and a `chef` table of helpers
--   * some engine calls crash the whole game (a null read, not a Lua error) when given the wrong kind of unit or
--     a stale handle; a Lua pcall can't catch that. So every engine call the helpers make is guarded: the first
--     time a call is made I write a breadcrumb, and if the game dies the next launch reads it, skips that call and
--     turns off the addon that made it, saying so in the log and on screen.
--   * engine handles (units, GUIs, cameras) belong to one world: when the world changes I drop them all, and nothing
--     made in one world is used in the next.
--   * on a menu quit the game calls shutdown() and then often crashes by itself (a known game bug), so a run that
--     reached shutdown() is never blamed.
-- Idle: nothing runs outside what an addon asked for. The unit scan only runs while an addon watches unit kinds, in a
-- settled world, spread over frames (1,500 units a frame). Drawing objects are made only when something draws.
-- Files (in %LOCALAPPDATA%), named after FILES below (chef_loader for Chef Loader): .log (what happened),
-- _state.txt (calls that crashed the game, addons turned off), _trace.txt (this launch's breadcrumbs).

function init() end
function shutdown() end
function update(dt) end
function render() end

local loader_ok, loader_err = pcall(function()

-- A mod can carry this loader built in: its build swaps these three lines, so the name, the files and the addons it
-- runs are that mod's own.
local LOADER = 'Chef Loader'             --@@LOADER@@
local FILES = 'chef_loader'              --@@FILES@@
local ALLOW = '^mods/chef/'              --@@ALLOW@@ my own mods first; other authors later
local VERSION = '0.1.0'
local STABLE_FOR = 3                     -- seconds a main world must last before addons may draw in it
local MISSION_UNITS = 5000               -- a main world bigger than this is a mission (ship ~3,800, missions 7,900-16,000)
local SCAN_PER_FRAME = 1500
local RECENT = 60                        -- a per-frame job is only blamed for a crash within this many seconds of starting
local MAX_ERRORS = 20                    -- Lua errors before an addon is switched off for the session
local STATUS_EVERY = 60
local LOG_CAP = 4 * 1024 * 1024         -- bytes one launch may write to the log (a runaway addon can't fill the disk)
local CAMERA_RETRY = 1                   -- seconds between searches for the camera when it can't be found

local G = _G
local S = rawget(G, 'stingray') or {}
local io_, os_ = rawget(G, 'io'), rawget(G, 'os')
local pairs, ipairs, pcall, type, tostring, tonumber, select = pairs, ipairs, pcall, type, tostring, tonumber, select
local fmt, concat, sort, sqrt, min, max, floor, atan2 = string.format, table.concat, table.sort, math.sqrt, math.min, math.max, math.floor, math.atan2
local byte, sub = string.byte, string.sub
local clock = type(os_) == 'table' and os_.clock or function() return 0 end

local elapsed = 0
local frame_no = 0

-- ------------------------------------------------------------------ files
-- At the root of %LOCALAPPDATA%: Lua can't make a folder here, and the root is always there.
local DIR = ''
if type(os_) == 'table' and type(os_.getenv) == 'function' then
  local ok, dir = pcall(os_.getenv, 'LOCALAPPDATA')
  if ok and type(dir) == 'string' and dir ~= '' then DIR = dir .. '\\' end
end
local LOG_FILE, STATE_FILE, TRACE_FILE = DIR .. FILES .. '.log', DIR .. FILES .. '_state.txt', DIR .. FILES .. '_trace.txt'

local function now()
  if type(os_) == 'table' then local ok, d = pcall(os_.date, '%H:%M:%S'); if ok then return d end end
  return '?'
end

local function open(path, mode)
  if type(io_) ~= 'table' then return nil end
  local ok, f = pcall(io_.open, path, mode)
  if ok then return f end
end

local log_file, log_written = nil, 0
local function log(text)
  if log_written > LOG_CAP then return end
  if not log_file then
    -- a fresh log each launch once it passes 1 MB
    local f = open(LOG_FILE, 'r')
    local big = false
    if f then local size = f:seek('end'); big = size and size > 1024 * 1024; f:close() end
    log_file = open(LOG_FILE, big and 'w' or 'a')
  end
  local line = fmt('%s %6.1f s | %s', now(), elapsed, text)
  log_written = log_written + #line + 1
  if log_written > LOG_CAP then line = line .. '\n(the log is full for this launch)' end
  if log_file then pcall(log_file.write, log_file, line .. '\n'); pcall(log_file.flush, log_file)
  elseif type(print) == 'function' then pcall(print, '[' .. LOADER .. '] ' .. line) end
end

-- ------------------------------------------------------------------ crash learning
-- State kept between launches: "skip: <key>" (a call that crashed the game) and "off: <addon> <fingerprint>
-- <reason>" (an addon I turned off; it comes back on its own when its file changes, i.e. an update).
-- "rule: 3": a first call that never returned is skipped at once (that one is certain). A per-frame job (drawing, a
-- scan) running when the game died is only suspected the first time ("suspect: <key>") and skipped if the next launch
-- dies in it again: a game that ends for its own reasons mid-frame mustn't switch a feature off for good. Skips from
-- the older rules are dropped once (except rule 2's certain ones).
local RULE = '3'
local skip, off, dropped, suspect = {}, {}, {}, {}
do
  local f = open(STATE_FILE, 'r')
  if f then
    local rule, old = nil, {}
    for line in f:lines() do
      rule = line:match('^rule: (%S+)$') or rule
      local k = line:match('^skip: (.+)$')
      if k then old[#old + 1] = k end
      local sp = line:match('^suspect: (.+)$')
      if sp then suspect[sp] = true end
      local name, fp, why = line:match('^off: (%S+) (%S+) (.*)$')
      if name then off[name] = { fp = fp, why = why } end
    end
    f:close()
    for _, k in ipairs(old) do
      -- rule 2's skips stay, except a job's (loader|draw:...): those were blamed on one exit, which rule 3 doesn't do
      if rule == RULE or (rule == '2' and not k:match('|draw:')) then skip[k] = true else dropped[#dropped + 1] = k end
    end
  end
end
local function save_state()
  local f = open(STATE_FILE, 'w')
  if not f then return end
  f:write('rule: ', RULE, '\n')
  for k in pairs(suspect) do f:write('suspect: ', k, '\n') end
  local keys = {}
  for k in pairs(skip) do keys[#keys + 1] = k end
  sort(keys)
  for _, k in ipairs(keys) do f:write('skip: ', k, '\n') end
  local names = {}
  for n in pairs(off) do names[#names + 1] = n end
  sort(names)
  for _, n in ipairs(names) do f:write('off: ', n, ' ', off[n].fp, ' ', off[n].why, '\n') end
  f:close()
end

-- What killed the last launch, read from its trace before I start a new one.
-- "> owner|call" / "< owner|call" = making that call for the first time / it returned (blamed if it never returned);
-- ">> owner|job @<s>" / "<< owner|job" = a per-frame job (blamed if still open and started within RECENT s);
-- "#### clean shutdown" = the game called shutdown(): nothing to blame.
local blamed, blamed_job = nil, false
do
  local f = open(TRACE_FILE, 'r')
  if f then
    local firsts, opened, order, last_t, clean = {}, {}, {}, 0, false
    for line in f:lines() do
      if line:match('^#### clean shutdown') then clean = true end
      local t = line:match('^t (%d+)$')
      if t then last_t = tonumber(t) end
      local o, at = line:match('^>> (.-) @(%d+)$')
      if o then opened[o] = tonumber(at); order[#order + 1] = o; last_t = max(last_t, tonumber(at)) end
      local c = line:match('^<< (.+)$')
      if c then opened[c] = nil end
      -- first calls can nest (an addon's first update makes first calls of its own), so they're a stack
      local b = line:match('^> (.+)$')
      if b then firsts[#firsts + 1] = b end
      local r = line:match('^< (.+)$')
      if r then for i = #firsts, 1, -1 do if firsts[i] == r then table.remove(firsts, i); break end end end
    end
    f:close()
    if not clean then
      blamed = firsts[#firsts]
      if not blamed then
        for i = #order, 1, -1 do
          local k = order[i]
          if opened[k] and last_t - opened[k] <= RECENT then blamed, blamed_job = k, true; break end
        end
      end
    end
  end
end

local trace = open(TRACE_FILE, 'w')
local function crumb(line)
  if trace then pcall(trace.write, trace, line .. '\n'); pcall(trace.flush, trace) end
end
local last_tick = -1
local function tick()   -- a time stamp in the trace every 10 s, so "started within RECENT s" can be judged
  local t = floor(elapsed)
  if t >= last_tick + 10 then last_tick = t; crumb('t ' .. t) end
end

-- ------------------------------------------------------------------ guarded engine calls
-- "Table.function" split once per name (the engine's tables are looked up each time, so a replaced one is seen)
local split = {}
local function fn_of(name)
  local sp = split[name]
  if sp == nil then
    local t, f = name:match('^([%w_]+)%.([%w_]+)$')
    sp = t and { t, f } or false
    split[name] = sp
  end
  if sp then local t = S[sp[1]]; return type(t) == 'table' and t[sp[2]] or nil end
  return S[name]
end
local proven = {}
-- The keys "owner|call" built once each and kept, so the hot paths (thousands of calls a frame) build no strings.
local keycache = {}
local function key_of(owner, key)
  local t = keycache[owner]
  if not t then t = {}; keycache[owner] = t end
  local k = t[key]
  if not k then k = owner .. '|' .. key; t[key] = k end
  return k
end
-- No table per call: the drawing makes thousands of these a frame while a panel is up.
local function pass(ok, a, b, c, d)
  if not ok then return nil, tostring(a) end
  return a, b, c, d
end
-- call(owner, key, fn, ...): skipped if `owner|key` crashed a launch; breadcrumbed the first time it runs.
local function guarded(owner, key, fn, ...)
  local k = key_of(owner, key)
  if skip[k] then return nil, 'skipped' end
  if type(fn) == 'table' then
    local mt = getmetatable(fn)
    if not (type(mt) == 'table' and mt.__call) then return nil, 'not callable' end
  elseif type(fn) ~= 'function' then
    return nil, 'missing'
  end
  if not proven[k] then
    proven[k] = true; crumb('> ' .. k)
    local a, b, c, d = pass(pcall(fn, ...))
    crumb('< ' .. k)
    return a, b, c, d
  end
  return pass(pcall(fn, ...))
end
local function api(name, ...) return guarded('loader', name, fn_of(name), ...) end
local held = {}
local function hold(key, on)
  if on and not held[key] then held[key] = true; crumb(fmt('>> %s @%d', key, elapsed))
  elseif not on and held[key] then held[key] = nil; crumb('<< ' .. key) end
end

-- ------------------------------------------------------------------ discovery
-- Patch archive layout (as my build tools write it and Arsenal deploys it): 72-byte header (0xF0000011, type
-- count, entry count, ...), 32-byte type rows, 80-byte entries (id, type, offset, stream offset, gpu offset,
-- 2 unused: u64; then size: u32 ...). A Lua resource: u32 length, u32 flag (2 = source text), then the text.
local LUA_TYPE = { 0xe2, 0x17, 0xd1, 0x2c, 0xfa, 0x8d, 0x4e, 0xa1 }
local function u32(s, i) local a, b, c, d = byte(s, i, i + 3); return a + b * 256 + c * 65536 + d * 16777216 end
local function u64(s, i) return u32(s, i) + u32(s, i + 4) * 4294967296 end
local function is_lua(s, i) for k = 1, 8 do if byte(s, i + k - 1) ~= LUA_TYPE[k] then return false end end return true end

local found_addons, found_options, scan = {}, {}, { files = 0, ms = 0, bad = 0 }
local MAX_ENTRIES, MAX_LUA = 200000, 4 * 1024 * 1024    -- sanity limits: a patch file claiming more is skipped
-- One patch file: its table of contents, then the first bytes of each Lua resource. Anything that doesn't add up (a
-- different format, a cut-off file) makes me skip that file, never read past it.
local function read_patch(f, name)
  local head = f:read(72) or ''
  if #head ~= 72 or u32(head, 1) ~= 0xF0000011 then return end
  local nt, ne = u32(head, 5), u32(head, 9)
  if nt > 4096 or ne > MAX_ENTRIES then scan.bad = scan.bad + 1; return end
  local toc = f:read(nt * 32 + ne * 80) or ''
  if #toc < nt * 32 + ne * 80 then scan.bad = scan.bad + 1; return end
  for e = 0, ne - 1 do
    local at = nt * 32 + e * 80 + 1
    if is_lua(toc, at + 8) then
      local off, size = u64(toc, at + 16), u32(toc, at + 56)
      if size >= 8 and size <= MAX_LUA and f:seek('set', off) then
        local first = f:read(min(size, 120)) or ''
        if #first >= 8 and u32(first, 5) == 2 then
          local kind, mod = first:sub(9):match('^%-%- HD2%-(%a+): ([%w_/%.%-]+)')
          if mod and mod:match(ALLOW) and (kind == 'Addon' or kind == 'Options') and f:seek('set', off + 8) then
            local src = f:read(size - 8) or ''
            if #src == size - 8 then
              local list = kind == 'Addon' and found_addons or found_options
              list[#list + 1] = { name = mod, file = name:match('[^/]+$'), src = src }
            end
          end
        end
      end
    end
  end
end
local function discover()
  local t0 = clock()
  local misses = 0
  for n = 0, 512 do
    local name = 'data/9ba626afa44a3aa3.patch_' .. n
    local f = open(name, 'rb')
    if not f then
      misses = misses + 1
      if misses > 40 then break end
    else
      misses = 0
      scan.files = scan.files + 1
      local ok, err = pcall(read_patch, f, name)
      if not ok then scan.bad = scan.bad + 1; log('skipped ' .. name .. ': ' .. tostring(err)) end
      pcall(f.close, f)
    end
  end
  scan.ms = (clock() - t0) * 1000
  sort(found_addons, function(a, b) return a.name < b.name end)
end

local function fingerprint(src)
  local h = #src
  for i = 1, #src, 7 do h = (h * 31 + byte(src, i)) % 2147483647 end
  return fmt('%x', h)
end

-- ------------------------------------------------------------------ world, camera, input
-- world.id: a new one for every settled world, and when the same world's contents turn into another (the game loads
-- the ship into the world the mission ran in). world.instance: a new one only for a new engine world; handles made in
-- one instance (GUIs) can be kept across an id change, never across an instance change.
local world = { main = nil, since = 0, time = -1, id = 0, instance = 0, stable = false, mission = false, units = 0 }
local new_world_hooks = {}
local function world_changed()
  for _, fn in ipairs(new_world_hooks) do fn() end
end
local function update_world()
  local main = api('Application.main_world')
  if not main then
    if world.main ~= nil then world.main, world.stable, world.mission = nil, false, false; world.instance = world.instance + 1; world_changed() end
    return
  end
  local t = api('World.time', main)
  if type(t) ~= 'number' and not world.no_time then world.no_time = true; log('World.time is not available: only a new main world counts as a world change') end
  if main ~= world.main or (type(t) == 'number' and t < world.time) then
    -- a different world (or the same one restarted): everything from the last one is dropped right now, before it can
    -- be used again, and nothing new is made until it has settled
    local was_stable = world.stable or world.main ~= nil
    world.main, world.since, world.stable = main, elapsed, false
    world.instance = world.instance + 1
    if was_stable then world_changed() end
  end
  world.time = type(t) == 'number' and t or -1
  if not world.stable and elapsed - world.since >= STABLE_FOR then
    world.stable = true
    world.id = world.id + 1
    world_changed()
    local n = api('World.num_units', main)
    world.units = type(n) == 'number' and n or 0
    world.mission = world.units > MISSION_UNITS
    world.recheck, world.flip = elapsed + 2, 0
    log(fmt('world %d: %s (%d units)', world.id, world.mission and 'mission' or 'not a mission', world.units))
  elseif world.stable and elapsed >= (world.recheck or 0) then
    -- The game keeps the same main world after a mission (the ship is loaded into it), so I look at its size every
    -- 2 s: on the other side of MISSION_UNITS it's a new world as far as addons are concerned (new id, mission or not;
    -- the same instance). Leaving a mission counts at the first look (the mission's units are going away); a world
    -- that turns into a mission needs two looks in a row.
    world.recheck = elapsed + 2
    local n = api('World.num_units', main)
    if type(n) == 'number' then
      if (n > MISSION_UNITS) ~= world.mission then
        world.flip = (world.flip or 0) + 1
        if world.flip >= 2 or world.mission then
          world.flip, world.id, world.units, world.mission = 0, world.id + 1, n, n > MISSION_UNITS
          log(fmt('world %d: %s (%d units; the same world, its contents changed)', world.id,
            world.mission and 'mission' or 'not a mission', n))
          world_changed()
        end
      else
        world.flip = 0
      end
    end
  end
end

-- The camera: I remember the camera unit and only look for it again when it's gone (at most once every CAMERA_RETRY
-- seconds). A new world forgets it.
local cam = { unit = nil, c = nil, frame = -1, data = nil, retry = 0 }
new_world_hooks[#new_world_hooks + 1] = function() cam.unit, cam.c, cam.data, cam.frame, cam.retry = nil, nil, nil, -1, 0 end
local function xyz(v)
  if v == nil then return nil end
  local x, y, z = api('Vector3.to_elements', v)
  if type(x) == 'number' then return x, y, z end
end
local function cam_from(u)
  local c = api('Unit.camera', u, 1)
  if not c then return nil end
  local x, y, z = xyz((api('Camera.world_position', c)))
  if not x then return nil end
  local d = { x = x, y = y, z = z, fx = 0, fy = 1, fz = 0, yaw = 0 }
  cam.c = c
  local fov = api('Camera.vertical_fov', c)
  if type(fov) == 'number' then d.fov = fov end
  local rot = api('Camera.world_rotation', c)
  local fx, fy, fz = xyz(rot and api('Quaternion.forward', rot))
  if fx then d.fx, d.fy, d.fz, d.yaw = fx, fy, fz, atan2(fx, fy) end
  return d
end
local function camera()
  if cam.frame == frame_no then return cam.data end
  cam.frame, cam.data = frame_no, nil
  if not world.stable then return nil end
  local from = cam_from
  if cam.unit and api('Unit.alive', cam.unit) == true then cam.data = from(cam.unit) end
  if not cam.data and elapsed >= cam.retry then
    cam.unit, cam.c = nil, nil
    cam.retry = elapsed + CAMERA_RETRY
    local units = api('World.units', world.main)
    if type(units) == 'table' then
      for _, u in pairs(units) do
        local nc = api('Unit.num_cameras', u)
        if type(nc) == 'number' and nc > 0 then cam.unit = u; cam.data = from(u); break end
      end
    end
  end
  return cam.data
end

local keys = {}
local function key_index(name)
  local k = keys[name]
  if k == nil then k = api('Keyboard.button_index', name) or false; keys[name] = k end
  return k
end

-- ------------------------------------------------------------------ unit watching (spread over frames)
-- Addons say which unit kinds they want (resource id -> anything) and how often; one shared scan serves them
-- all, and it only runs while somebody is watching, in a stable world.
local watchers = {}
local job = nil
local scan_off_noted = false
local function scan_start()
  if skip['loader|scan'] then
    if not scan_off_noted then scan_off_noted = true; log('the unit scan is off: the game ended twice while it ran (delete the state file to try again)') end
    return
  end
  local due = {}
  for _, w in ipairs(watchers) do
    if w.active and w.owner_on() and (w.want_now or elapsed >= w.next) then due[#due + 1] = w end
  end
  if #due == 0 then return end
  local units = api('World.units', world.main)
  if type(units) ~= 'table' then return end
  for _, w in ipairs(due) do w.want_now, w.next, w.building = false, elapsed + w.every, {} end
  job = { units = units, i = 0, due = due, world = world.id, instance = world.instance, t0 = clock(), cost = 0 }
  hold('loader|scan', true)   -- a game that dies mid-scan twice in a row stops the scan (my crash rule for jobs)
end
local pos_keys = {}               -- kind -> "Unit.world_position:<kind>", built once
-- A new world: the scan under way stops (its units belong to the old one), and every watcher's list empties at once,
-- with a new generation, so no addon keeps using units from the world that's gone.
new_world_hooks[#new_world_hooks + 1] = function()
  if job then job = nil; hold('loader|scan', false) end
  for _, w in ipairs(watchers) do
    w.items, w.building, w.generation, w.want_now = {}, nil, w.generation + 1, true
  end
end
local function scan_step()
  if not world.stable or job.world ~= world.id or job.instance ~= world.instance then job = nil; hold('loader|scan', false); return end
  local t0 = clock()
  local units = job.units
  local last = min(#units, job.i + SCAN_PER_FRAME)
  for i = job.i + 1, last do
    local u = units[i]
    local n = api('Unit.debug_name', u)
    local k = type(n) == 'string' and n:match('#ID%[(%x+)%]')
    if k then
      for _, w in ipairs(job.due) do
        -- the list was taken a few frames ago: a unit picked up since is checked before I ask where it is
        if w.kinds[k] and api('Unit.alive', u) == true then
          local pk = pos_keys[k]
          if not pk then pk = 'Unit.world_position:' .. k; pos_keys[k] = pk end
          local x, y, z = xyz((guarded(w.owner, pk, fn_of('Unit.world_position'), u, 1)))
          if x then w.building[#w.building + 1] = { unit = u, kind = k, x = x, y = y, z = z } end
        end
      end
    end
  end
  job.i = last
  job.cost = job.cost + (clock() - t0) * 1000
  if last >= #units then
    for _, w in ipairs(job.due) do
      w.items, w.building, w.generation = w.building, nil, w.generation + 1
      w.scan_ms = job.cost
    end
    job = nil
    hold('loader|scan', false)
  end
end

-- ------------------------------------------------------------------ drawing
-- Screen: one immediate GUI per stable world, with the performance-HUD font and GUI materials (rects
-- draw; text glyphs come out as solid blocks, so text is my own pixel font made of rects). Origin bottom-left.
-- World: one line object per stable world, reset every frame something draws, dispatched after the addons ran.
local draw = { world = 0, instance = -1, gui = nil, lines = nil, lines_used = false, colors = {}, w = 1920, h = 1080, icons = {}, icon_ok = nil }
local GUI_FONT, GUI_MAT = 'core/performance_hud/debug', 'core/performance_hud/gui'

-- The engine's Color (like Vector3) is a temporary that only lives for the frame it was made in (kept longer, every
-- rect comes out white), so the cache starts empty every frame.
local color_frame = -1
local function color(r, g, b, a)
  if color_frame ~= frame_no then color_frame = frame_no; draw.colors = {} end
  local key = r * 16777216 + g * 65536 + b * 256 + (a or 255)
  local c = draw.colors[key]
  if c == nil then c = api('Color', a or 255, r, g, b) or false; draw.colors[key] = c end
  return c or nil
end

-- My GUIs live in the world they were made in: within the same instance they're kept (the ship loaded into the
-- mission's world is the same engine world), in a new one they're dropped without being touched (a GUI used after its
-- world went away crashes the game, and so may destroying it).
local function draw_world_reset()
  if draw.world ~= world.id then
    if draw.instance ~= world.instance then
      hold('loader|draw:gui', false); hold('loader|draw:lines', false)
      hold('loader|draw:bitmaps', false)
      draw.gui, draw.lines, draw.icons, draw.icon_ok = nil, nil, {}, nil
      draw.instance = world.instance
    end
    draw.world, draw.lines_used = world.id, false
    draw.size_at = -1
  end
  -- the screen size, again every 2 s (the resolution can change mid-mission)
  if elapsed >= (draw.size_at or -1) + 2 then
    draw.size_at = elapsed
    local w, h = api('Application.back_buffer_size')
    if type(w) == 'number' and type(h) == 'number' and w > 0 and h > 0 then draw.w, draw.h = w, h end
  end
end

local function gui()
  if not world.stable then return nil end
  draw_world_reset()
  if skip['loader|draw:gui'] then return nil end
  if draw.gui == nil then
    draw.gui = api('World.create_screen_gui', world.main, 'immediate', 'material', GUI_FONT, 'material', GUI_MAT) or false
    if draw.gui then hold('loader|draw:gui', true) end
  end
  return draw.gui or nil
end

-- The top: the first world that isn't the main one. Treasure Map 1.x drew its map markers there, on top
-- of the game's map. Anything drawn at layer 2000 or up goes there (at its layer - 1000). I check every frame that
-- something is drawn there that it's still the same world (and the world count hasn't changed); if not, I drop my
-- GUIs without touching them, because a GUI used after its world went away crashes the game.
local TOP_FROM = 2000
local top = { world = nil, n = 0, wid = -1, gui = nil, icons = {}, frame = -1 }
local function top_drop()
  hold('loader|draw:top', false)
  top.world, top.gui, top.icons = nil, nil, {}
end
local function top_world()
  if skip['loader|draw:top'] or not world.stable then return nil end
  if top.frame == frame_no then return top.world end
  top.frame = frame_no
  local ws = api('Application.worlds')
  local found, n = nil, 0
  if type(ws) == 'table' then
    n = #ws
    for i = 1, n do if ws[i] ~= world.main then found = ws[i]; break end end
  end
  if top.world ~= nil and (found == nil or n ~= top.n or top.wid ~= world.id or not (found == top.world)) then top_drop() end
  if top.world == nil and found ~= nil then top.world, top.n, top.wid = found, n, world.id end
  return top.world
end
local function top_gui()
  local w = top_world()
  if not w then return nil end
  if top.gui == nil then
    top.gui = api('World.create_screen_gui', w, 'immediate', 'material', GUI_FONT, 'material', GUI_MAT) or false
    if top.gui then hold('loader|draw:top', true) end
  end
  return top.gui or nil
end

-- The hot path of every panel: a few thousand of these a frame. After the first (breadcrumbed) calls proved
-- Vector3, Vector2 and Gui.rect, I call them straight through one pcall, with no key strings built per call.
local fast_rect = nil
local function rect_fast(g, x, y, w, h, c, layer)
  local V3, V2, R = S.Vector3, S.Vector2, S.Gui.rect
  return R(g, V3(x, y, layer), V2(w, h), c)
end
local function rect(x, y, w, h, c, layer)
  layer = layer or 900
  local g
  if layer >= TOP_FROM then g = top_gui(); layer = layer - 1000 else g = gui() end
  if not g or not c then return end
  if fast_rect then
    if not pcall(rect_fast, g, x, y, w, h, c, layer) then fast_rect = false end
    return
  end
  local p, s = api('Vector3', x, y, layer), api('Vector2', w, h)
  if p and s then
    local _, err = api('Gui.rect', g, p, s, c)
    if fast_rect == nil and not err and proven['loader|Gui.rect'] then fast_rect = true end
  end
end

-- 5x7 pixel font. Each glyph: 7 rows of 5 bits, top row first.
local GLYPHS = {
  ['A'] = '01110100011000111111100011000110001', ['B'] = '11110100011000111110100011000111110',
  ['C'] = '01110100011000010000100001000101110', ['D'] = '11100100101000110001100011001011100',
  ['E'] = '11111100001000011110100001000011111', ['F'] = '11111100001000011110100001000010000',
  ['G'] = '01110100011000010111100011000101111', ['H'] = '10001100011000111111100011000110001',
  ['I'] = '01110001000010000100001000010001110', ['J'] = '00111000100001000010000101001001100',
  ['K'] = '10001100101010011000101001001010001', ['L'] = '10000100001000010000100001000011111',
  ['M'] = '10001110111010110101100011000110001', ['N'] = '10001100011100110101100111000110001',
  ['O'] = '01110100011000110001100011000101110', ['P'] = '11110100011000111110100001000010000',
  ['Q'] = '01110100011000110001101011001001101', ['R'] = '11110100011000111110101001001010001',
  ['S'] = '01111100001000001110000010000111110', ['T'] = '11111001000010000100001000010000100',
  ['U'] = '10001100011000110001100011000101110', ['V'] = '10001100011000110001100010101000100',
  ['W'] = '10001100011000110101101011010101010', ['X'] = '10001100010101000100010101000110001',
  ['Y'] = '10001100010101000100001000010000100', ['Z'] = '11111000010001000100010001000011111',
  ['0'] = '01110100011001110101110011000101110', ['1'] = '00100011000010000100001000010001110',
  ['2'] = '01110100010000100010001000100011111', ['3'] = '11111000100010000010000011000101110',
  ['4'] = '00010001100101010010111110001000010', ['5'] = '11111100001111000001000011000101110',
  ['6'] = '00110010001000011110100011000101110', ['7'] = '11111000010001000100010000100001000',
  ['8'] = '01110100011000101110100011000101110', ['9'] = '01110100011000101111000010001001100',
  [' '] = '00000000000000000000000000000000000', ['.'] = '00000000000000000000000000110001100',
  [':'] = '00000011000110000000011000110000000', ['-'] = '00000000000000011111000000000000000',
  ['/'] = '00001000010001000100010001000010000', ['%'] = '11001110010001000100010001001110011',
  ['+'] = '00000001000010011111001000010000000', ['('] = '00010001000100001000010000010000010',
  [')'] = '01000001000001000010000100010001000', ["'"] = '00100001000100000000000000000000000',
  ['!'] = '00100001000010000100001000000000100', ['?'] = '01110100010000100010001000000000100',
  [','] = '00000000000000000000001100010001000', ['x'] = '00000000001000101010001000101010001',
}
-- Each glyph as a few rects: runs along a row, merged down over identical rows (about 6-12 rects a letter).
local glyph_rects = {}
local function rects_of(ch)
  local r = glyph_rects[ch]
  if r then return r end
  local bits = GLYPHS[ch] or GLYPHS[ch:upper()] or GLYPHS['?']
  local runs = {}
  for row = 0, 6 do
    local col = 0
    while col < 5 do
      if sub(bits, row * 5 + col + 1, row * 5 + col + 1) == '1' then
        local start = col
        while col < 5 and sub(bits, row * 5 + col + 1, row * 5 + col + 1) == '1' do col = col + 1 end
        runs[#runs + 1] = { x = start, w = col - start, row = row }
      else
        col = col + 1
      end
    end
  end
  r = {}
  local used = {}
  for i, a in ipairs(runs) do
    if not used[i] then
      local h = 1
      for j = i + 1, #runs do
        local b = runs[j]
        if not used[j] and b.x == a.x and b.w == a.w and b.row == a.row + h then used[j] = true; h = h + 1 end
      end
      r[#r + 1] = { x = a.x, y = 7 - a.row - h, w = a.w, h = h }   -- y measured up from the glyph's bottom
    end
  end
  glyph_rects[ch] = r
  return r
end

-- Sprites: small pictures given as rows of characters (top row first); each character maps to a color, '.' is
-- empty. Drawn as rects, runs along a row merged down over identical rows, cached per sprite.
local sprite_rects = setmetatable({}, { __mode = 'k' })
local function sprite_runs(rows)
  local r = sprite_rects[rows]
  if r then return r end
  local h = #rows
  local runs = {}
  for row = 1, h do
    local line, col = rows[row], 1
    while col <= #line do
      local ch = sub(line, col, col)
      if ch ~= '.' then
        local start = col
        while col <= #line and sub(line, col, col) == ch do col = col + 1 end
        runs[#runs + 1] = { x = start - 1, w = col - start, row = row - 1, ch = ch }
      else
        col = col + 1
      end
    end
  end
  r = {}
  local used = {}
  for i, a in ipairs(runs) do
    if not used[i] then
      local n = 1
      for j = i + 1, #runs do
        local b = runs[j]
        if not used[j] and b.x == a.x and b.w == a.w and b.ch == a.ch and b.row == a.row + n then used[j] = true; n = n + 1 end
      end
      r[#r + 1] = { x = a.x, y = h - a.row - n, w = a.w, h = n, ch = a.ch }
    end
  end
  sprite_rects[rows] = r
  return r
end
-- x, y = bottom-left corner; cell = size of one sprite pixel; colors = { [char] = color }
local function sprite(x, y, rows, cell, colors, layer)
  for _, r in ipairs(sprite_runs(rows)) do
    local c = colors[r.ch]
    if c then rect(x + r.x * cell, y + r.y * cell, r.w * cell, r.h * cell, c, (layer or 900) + (r.ch == 'o' and 0 or 1)) end
  end
end

local function text_width(text, px) return #text * 6 * px - px end
local function text(x, y, str, px, c, layer)
  if not c then return 0 end
  local g = gui()
  if not g then return 0 end
  local cx = x
  for i = 1, #str do
    local ch = sub(str, i, i)
    if ch ~= ' ' then
      for _, r in ipairs(rects_of(ch)) do rect(cx + r.x * px, y + r.y * px, r.w * px, r.h * px, c, layer) end
    end
    cx = cx + 6 * px
  end
  return cx - x - px
end

local function line(x1, y1, z1, x2, y2, z2, c)
  if not world.stable or not c then return end
  draw_world_reset()
  if skip['loader|draw:lines'] then return end
  if draw.lines == nil then
    draw.lines = api('World.create_line_object', world.main) or false
    if draw.lines then hold('loader|draw:lines', true) end
  end
  if not draw.lines then return end
  if not draw.lines_used then api('LineObject.reset', draw.lines); draw.lines_used = true end
  local a, b = api('Vector3', x1, y1, z1), api('Vector3', x2, y2, z2)
  if a and b then api('LineObject.add_line', draw.lines, c, a, b) end
end

-- Bitmaps (icons): Treasure Map 1.x's recipe, all engine functions. The game's UI material
-- content/ui/shared/misc/yellow_logo (still in 7.2.0) has one texture slot; every texture gets its own screen GUI whose
-- copy of that material has the texture bound (Gui.material + Material.set_texture), and Gui.bitmap draws it.
-- Textures shipped in a mod's patch are loaded with the game's boot archive (1.x's icons were). If the material or a
-- texture isn't loaded, or a call is refused, bitmap() returns false and the caller draws something else.
local UI_MATERIAL, UI_SLOT = 'e2d6ed90906c1e8b', '3aa8b87e00000000'
local function id64(hex) return api('IdString64.from_hex', hex) end
local icon_notes = {}
local fast_bitmap, ui_mat_id, ui_mat_frame = nil, nil, -1
local function bitmap_fast(g, mat, x, y, w, h, c, layer)
  local V3, V2 = S.Vector3, S.Vector2
  return S.Gui.bitmap(g, mat, V3(x, y, layer), V2(w, h), c)
end
local function bitmap(tex, x, y, w, h, c, layer)
  if not world.stable or not c or skip['loader|draw:bitmaps'] then return false end
  draw_world_reset()
  layer = layer or 900
  local icons, target = draw.icons, world.main
  if layer >= TOP_FROM then
    target = top_world()
    if not target then return false end
    icons, layer = top.icons, layer - 1000
  end
  local e = icons[tex]
  if e == nil then
    e = false
    if draw.icon_ok == nil then draw.icon_ok = api('Application.can_get', 'material', id64(UI_MATERIAL)) == true end
    local why = nil
    if not draw.icon_ok then why = 'the UI material is not loaded'
    elseif api('Application.can_get', 'texture', id64(tex)) ~= true then why = 'texture ' .. tex .. ' is not loaded'
    else
      local g = api('World.create_screen_gui', target, 'immediate')
      if g then e = { gui = g, frame = -1 } else why = 'no screen GUI' end
    end
    icons[tex] = e
    if e then hold(icons == top.icons and 'loader|draw:top' or 'loader|draw:bitmaps', true)
    elseif not icon_notes[why] then icon_notes[why] = true; log('icons: ' .. why .. '; the addon draws its own fallback') end
  end
  if not e then return false end
  if e.frame ~= frame_no then
    -- the texture is bound once a frame, like 1.x did before every redraw
    e.frame = frame_no
    local mh = api('Gui.material', e.gui, id64(UI_MATERIAL))
    local _, err = nil, 'no material'
    if mh then _, err = api('Material.set_texture', mh, id64(UI_SLOT), id64(tex)) end
    if err then
      icons[tex] = false
      if not icon_notes[err] then icon_notes[err] = true; log('icons: texture ' .. tex .. ' refused (' .. tostring(err) .. ')') end
      return false
    end
  end
  -- like rects: once the breadcrumbed calls proved Vector3, Vector2 and Gui.bitmap, one pcall straight through (an
  -- addon's numbers can be a few hundred bitmaps a frame)
  if fast_bitmap then
    -- the material id made fresh once a frame (the engine's value types can be one-frame temporaries, like Color)
    if ui_mat_frame ~= frame_no then
      ui_mat_frame = frame_no
      local ok, v = pcall(S.IdString64.from_hex, UI_MATERIAL)
      ui_mat_id = ok and v or nil
    end
    if ui_mat_id and pcall(bitmap_fast, e.gui, ui_mat_id, x, y, w, h, c, layer) then return true end
    fast_bitmap = false
    return false
  end
  local p, sz = api('Vector3', x, y, layer), api('Vector2', w, h)
  if not (p and sz) then return false end
  local _, err = api('Gui.bitmap', e.gui, id64(UI_MATERIAL), p, sz, c)
  if not err and fast_bitmap == nil and proven['loader|Gui.bitmap'] then
    fast_bitmap = true
  end
  return not err
end

local function draw_flush()
  -- nothing drawn on top for half a second (the map closed): I give the top world's GUIs back, so they don't pile up
  -- over a session and a crash long after isn't put on them
  if top.world and frame_no - top.frame > 30 then
    local ws, alive = api('Application.worlds'), false
    if type(ws) == 'table' and #ws == top.n and top.wid == world.id then
      for i = 1, #ws do if ws[i] == top.world then alive = true; break end end
    end
    if alive then
      if top.gui then api('World.destroy_gui', top.world, top.gui) end
      for _, e in pairs(top.icons) do if e then api('World.destroy_gui', top.world, e.gui) end end
    end
    top_drop(); top.frame = -1
  end
  if draw.lines and draw.lines_used and world.stable and draw.world == world.id then
    api('LineObject.dispatch', world.main, draw.lines)
  end
  draw.lines_used = false
end

-- ------------------------------------------------------------------ addons
local addons, notices = {}, {}
local function options_for(name)
  local o = {}
  for _, r in ipairs(found_options) do
    if r.name == name then
      local chunk = loadstring(r.src, '@' .. r.name .. ' (options in ' .. r.file .. ')')
      local ok, t = false, nil
      -- an options file is just a table: it runs with nothing to reach
      if chunk then setfenv(chunk, {}); ok, t = pcall(chunk) end
      if ok and type(t) == 'table' then
        for k, v in pairs(t) do
          if type(v) == 'table' and type(o[k]) == 'table' then for k2, v2 in pairs(v) do o[k][k2] = v2 end
          else o[k] = v end
        end
      else
        log('options for ' .. name .. ' in ' .. r.file .. ' could not be read')
      end
    end
  end
  return o
end

local function make_api(a)
  local owner = a.name                   -- crash keys carry the full addon name, e.g. mods/chef/treasure_radar|Unit.alive
  local chef = { loader = LOADER, loader_version = VERSION, name = a.name }
  chef.options = a.options
  function chef.log(...) local ok, s = pcall(fmt, ...); log('[' .. owner .. '] ' .. (ok and s or tostring((...)))) end
  function chef.call(name, ...) return guarded(owner, name, fn_of(name), ...) end
  local kind_keys = {}                   -- name -> kind -> "name:kind", built once
  function chef.call_kind(name, kind, ...)
    local t = kind_keys[name]
    if not t then t = {}; kind_keys[name] = t end
    local key = t[kind]
    if not key then key = name .. ':' .. kind; t[kind] = key end
    return guarded(owner, key, fn_of(name), ...)
  end
  function chef.time() return elapsed end
  function chef.world() if world.stable then return world.main end end
  function chef.world_id() return world.stable and world.id or 0 end
  function chef.in_mission() return world.stable and world.mission end
  chef.camera = camera
  -- a world point on screen through my view camera: x, y in screen pixels (bottom-left origin, like the
  -- GUIs), or nil when it's behind me or there's no camera. The engine's answer is 2D, so "behind" is my own check.
  function chef.world_to_screen(x, y, z)
    local d = camera()
    if not d or not cam.c then return nil end
    local ax, ay, az = x - d.x, y - d.y, z - d.z
    if ax * d.fx + ay * d.fy + az * d.fz <= 0.5 then return nil end
    local v = api('Vector3', x, y, z)
    if not v then return nil end
    local r = guarded(owner, 'Camera.world_to_screen', fn_of('Camera.world_to_screen'), cam.c, v)
    if r == nil then return nil end
    local sx, sy = xyz(r)
    return sx, sy
  end
  function chef.watch(kinds, every)
    local w = { owner = owner, kinds = kinds, every = every or 5, next = 0, items = {}, generation = 0,
                active = true, want_now = true, owner_on = function() return a.on end, scan_ms = 0 }
    watchers[#watchers + 1] = w
    function w.pause() w.active = false end
    function w.resume() if not w.active then w.active, w.want_now = true, true end end
    function w.refresh() w.want_now = true end
    return w
  end
  function chef.key_down(name)
    local k = key_index(name)
    if not k then return false end
    local v = guarded(owner, 'Keyboard.button', fn_of('Keyboard.button'), k)
    return type(v) == 'number' and v > 0.5
  end
  function chef.key_pressed(name)
    local k = key_index(name)
    return k and guarded(owner, 'Keyboard.pressed', fn_of('Keyboard.pressed'), k) == true or false
  end
  function chef.screen() draw_world_reset(); return draw.w, draw.h end
  -- the mouse wheel this frame (0 when it didn't move); the game's map zooms with it
  local wheel_ix = nil
  function chef.wheel()
    if wheel_ix == nil then wheel_ix = guarded(owner, 'Mouse.axis_index', fn_of('Mouse.axis_index'), 'wheel') or false end
    if not wheel_ix then return 0 end
    local v = guarded(owner, 'Mouse.axis', fn_of('Mouse.axis'), wheel_ix)
    if v == nil then return 0 end
    local _, y = guarded(owner, 'Vector3.to_elements', fn_of('Vector3.to_elements'), v)
    return type(y) == 'number' and y or 0
  end
  -- the mouse cursor (window pixels, as the engine gives them) and a mouse button held ('left', 'right', ...)
  local cursor_ix, mouse_ix = nil, {}
  function chef.cursor()
    if cursor_ix == nil then cursor_ix = guarded(owner, 'Mouse.axis_index', fn_of('Mouse.axis_index'), 'cursor') or false end
    if not cursor_ix then return nil end
    local v = guarded(owner, 'Mouse.axis', fn_of('Mouse.axis'), cursor_ix)
    if v == nil then return nil end
    local x, y = guarded(owner, 'Vector3.to_elements', fn_of('Vector3.to_elements'), v)
    if type(x) == 'number' and type(y) == 'number' then return x, y end
  end
  function chef.mouse_down(name)
    local k = mouse_ix[name]
    if k == nil then k = guarded(owner, 'Mouse.button_index', fn_of('Mouse.button_index'), name) or false; mouse_ix[name] = k end
    if not k then return false end
    local v = guarded(owner, 'Mouse.button', fn_of('Mouse.button'), k)
    return type(v) == 'number' and v > 0.5
  end
  chef.TOP = TOP_FROM
  chef.color, chef.text_width = color, text_width
  function chef.rect(x, y, w, h, c, layer) rect(x, y, w, h, c, layer) end
  function chef.text(x, y, s, px, c, layer) return text(x, y, s, px, c, layer) end
  function chef.sprite(x, y, rows, cell, colors, layer) sprite(x, y, rows, cell, colors, layer) end
  function chef.bitmap(tex, x, y, w, h, c, layer) return bitmap(tex, x, y, w, h, c, layer) end
  function chef.line(x1, y1, z1, x2, y2, z2, c) line(x1, y1, z1, x2, y2, z2, c) end
  return chef
end

local function run_hook(a, hook, ...)
  local fn = a.module and a.module[hook]
  if not a.on or type(fn) ~= 'function' then return end
  local t0 = clock()
  local ok, err = pcall(fn, ...)
  local ms = (clock() - t0) * 1000
  a.ms, a.frames = a.ms + ms, a.frames + 1
  if ms > a.max_ms then a.max_ms = ms end
  if not ok then
    a.errors = a.errors + 1
    if a.errors <= 3 then log('[' .. a.short .. '] ' .. hook .. ' error: ' .. tostring(err)) end
    if a.errors >= MAX_ERRORS then
      a.on = false
      log('switched off ' .. a.name .. ' for this session after ' .. a.errors .. ' errors')
      notices[#notices + 1] = { text = a.short:upper():gsub('_', ' ') .. ' STOPPED AFTER ERRORS', dur = 20 }
    end
  end
end

local function start_addons()
  local seen = {}
  for _, r in ipairs(found_addons) do
    if seen[r.name] then
      log('skipped a second copy of ' .. r.name .. ' (' .. r.file .. ')')
    else
      seen[r.name] = true
      local a = { name = r.name, short = r.name:match('([^/]+)$'), file = r.file, fp = fingerprint(r.src),
                  on = true, errors = 0, ms = 0, frames = 0, max_ms = 0 }
      addons[#addons + 1] = a
      local was = off[a.name]
      -- A Tester probe can ask to stay on after a crash ("-- HD2-Keep-On-Crash: yes" in its first lines): then only
      -- the call that crashed is skipped.
      local keep = r.src:sub(1, 400):match('\n%-%- HD2%-Keep%-On%-Crash: yes') ~= nil
      if was and keep then
        off[a.name] = nil
        save_state()
        log('kept on after a crash (it asked to): ' .. a.name .. '; the call that crashed stays skipped')
        was = nil
      end
      if was and was.fp == a.fp then
        a.on = false
        log('kept off: ' .. a.name .. ' (' .. was.why .. '); an update of the mod turns it back on')
        notices[#notices + 1] = { text = a.short:upper():gsub('_', ' ') .. ' IS OFF AFTER A CRASH (SEE ' .. FILES:upper() .. '.LOG)', dur = 25 }
      elseif was then
        off[a.name] = nil
        save_state()
        log('turned back on: ' .. a.name .. ' (the mod changed since it was turned off)')
      end
      if a.on then
        a.options = options_for(a.name)
        local chunk, cerr = loadstring(r.src, '@' .. r.name)
        if not chunk then
          a.on = false
          log('could not compile ' .. a.name .. ': ' .. tostring(cerr))
        else
          local env = setmetatable({}, { __index = G })
          setfenv(chunk, env)
          crumb('> ' .. a.name .. '|start')
          local ok, m = pcall(chunk, make_api(a))
          crumb('< ' .. a.name .. '|start')
          if ok and type(m) == 'table' then
            a.module = m
            log(fmt('started %s %s (%s)', a.name, tostring(m.version or ''), a.file))
          else
            a.on = false
            log('could not start ' .. a.name .. ': ' .. tostring(m))
          end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ frame
local next_status = STATUS_EVERY
local loader_ms, loader_frames, loader_max = 0, 0, 0

local function draw_notices()
  if #notices == 0 or not world.stable then return end
  local keep = {}
  local w, h = draw.w, draw.h
  local px = max(2, floor(h / 540 + 0.5))
  local y = h - 60 * px / 2
  local red, dark = color(255, 90, 70, 255), color(10, 10, 10, 180)
  for _, n in ipairs(notices) do
    n.until_t = n.until_t or (elapsed + n.dur)     -- the clock starts when the notice can first be seen
    if elapsed < n.until_t then
      keep[#keep + 1] = n
      local tw = text_width(n.text, px)
      local x = floor((w - tw) / 2)
      rect(x - 3 * px, y - 2 * px, tw + 6 * px, 11 * px, dark, 950)
      text(x, y, n.text, px, red, 960)
      y = y - 14 * px
    end
  end
  notices = keep
end

local function frame(dt)
  frame_no = frame_no + 1
  tick()
  update_world()
  if job then scan_step() elseif world.stable and #watchers > 0 then scan_start() end
  for _, a in ipairs(addons) do run_hook(a, 'update', dt) end
  draw_notices()
  draw_flush()
  if elapsed >= next_status then
    next_status = elapsed + STATUS_EVERY
    local parts = {}
    for _, a in ipairs(addons) do
      parts[#parts + 1] = fmt('%s %s avg %.3f ms max %.2f ms%s', a.short, a.on and 'on' or 'off',
        a.frames > 0 and a.ms / a.frames or 0, a.max_ms, a.errors > 0 and (' errors ' .. a.errors) or '')
      a.ms, a.frames, a.max_ms = 0, 0, 0
    end
    log(fmt('status: loader avg %.3f ms max %.2f ms | %s', loader_frames > 0 and loader_ms / loader_frames or 0, loader_max,
      #parts > 0 and concat(parts, ' | ') or 'no addons'))
    loader_ms, loader_frames, loader_max = 0, 0, 0
  end
end

local frame_errors, frame_errors_at = 0, 0
function update(dt)
  if type(dt) == 'number' and dt > 0 and dt < 10 then elapsed = elapsed + dt end
  local t0 = clock()
  local ok, err = pcall(frame, dt)
  local ms = (clock() - t0) * 1000
  loader_ms, loader_frames = loader_ms + ms, loader_frames + 1
  if ms > loader_max then loader_max = ms end
  if not ok then
    -- a loader error every frame mustn't flood the log: the first few, then a count once a minute
    frame_errors = frame_errors + 1
    if frame_errors <= 5 then log('frame error: ' .. tostring(err))
    elseif elapsed >= frame_errors_at then frame_errors_at = elapsed + 60; log(fmt('frame errors so far: %d (last: %s)', frame_errors, tostring(err))) end
  end
end

function shutdown()
  pcall(function()
    for _, a in ipairs(addons) do run_hook(a, 'shutdown') end
    crumb('#### clean shutdown')
    log('shutdown (clean)')
    if trace then trace:close(); trace = nil end
    if log_file then log_file:close(); log_file = nil end
  end)
end

-- ------------------------------------------------------------------ start-up
log(fmt('==== %s %s starting', LOADER, VERSION))
if #dropped > 0 then
  log('dropped ' .. #dropped .. ' skip(s) recorded by the old crash rule: ' .. concat(dropped, ', '))
  save_state()
end
if blamed and blamed_job and not suspect[blamed] then
  log('the last launch ended while ' .. blamed .. ' was running; if the next one ends the same way, I skip it')
  suspect = { [blamed] = true }
  blamed = nil
  save_state()
elseif not blamed and next(suspect) then
  suspect = {}
  save_state()
end
if blamed then
  suspect = {}
  skip[blamed] = true
  local owner = blamed:match('^([^|]+)|')
  log('the last launch crashed in: ' .. blamed .. ' (that call is skipped from now on)')
  if owner and owner ~= 'loader' then
    off[owner] = { fp = 'pending', why = 'crashed the game in ' .. blamed:gsub('^[^|]+|', '') }
  end
  save_state()
end
local dok, derr = pcall(discover)
if not dok then log('addon search failed: ' .. tostring(derr)) end
log(fmt('found %d addon(s) and %d option file(s) in %d patch files (%.1f ms)', #found_addons, #found_options, scan.files, scan.ms))
-- an addon blamed for the last crash is turned off now that I know its fingerprint
for _, r in ipairs(found_addons) do
  local o = off[r.name]
  if o and o.fp == 'pending' then o.fp = fingerprint(r.src); save_state() end
end
start_addons()

end)
if not loader_ok and type(print) == 'function' then pcall(print, '[Chef Loader] failed to start: ' .. tostring(loader_err)) end
