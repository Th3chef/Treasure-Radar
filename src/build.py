#!/usr/bin/env python3
"""Builds Treasure Radar for Arsenal.

  python3 build.py <out dir>              -> <out dir>/Treasure-Radar-<ver>.zip (the release)
  python3 build.py <out dir> --tester     -> Treasure-Radar-<ver>-Tester.zip (the release on the Tester's id)
  python3 build.py <out dir> --test N     -> Treasure-Radar-<ver>-Test-N.zip (a numbered test build, on the Tester's id)
  --textures writes every texture as a PNG (for previews);
  --weapons-from <a release zip> takes the weapon silhouettes' textures from that release (the game's own marker icons
    aren't in the repository: without weapon_icons/ and without this, every weapon gets my generic shape);
  --header-from <a working Lua patch> takes the patch header from a patch that works on the current game.

Treasure Radar is a Chef Shared Loader addon packed as an Arsenal mod with Options. It needs Chef Shared Loader (1.0.0
or newer, its own mod; its source kit is the loader's only home) and carries no loader of its own.
The core folder holds the addon (treasure_radar.lua) and its textures, and every option folder ships a small
"-- HD2-Options: mods/chef/treasure_radar" resource the loader merges. The zip is the same byte for byte on every build.
Needs Python 3 and Pillow; the Poppins Bold font for the numbers (fonts/Poppins-Bold.ttf, SIL Open Font License).
"""
import json, os, re, sys, zipfile, shutil, struct
import hd2_patch as h
LUA, TEXTURE = 0xa14e8dfa2cd117e2, 0xcd4238c6a0c69e32

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
OUT = args[0]
TEST = int(args[args.index('--test') + 1]) if '--test' in args else None
TESTER = '--tester' in args
# the header of a Lua patch (engine metadata only); --header-from takes it from a patch that works on the current game
HEADER = bytes.fromhex('0000000000000000000000000000000000000000ea7b0000000000000000'
                       '000000000000000000000000000000000000000000000000000000000000')
if '--header-from' in args:
    HEADER = open(args[args.index('--header-from') + 1], 'rb').read()[12:72]
assert len(HEADER) == 60

TM_VERSION = '0.6.0'
NEEDS_LOADER = '1.0.0'                                     # the oldest Chef Shared Loader Treasure Radar runs on
TM_GUID = 'dde1d14f-762f-4abf-85ed-42846077674c'           # Treasure Radar
TM_TEST_GUID = '8e41c7a2-3f5d-4b90-a6e1-0d29b7f4c853'      # Treasure Radar Tester and test builds (installs beside it)
ZIP_DATE = (2026, 10, 21, 0, 0, 0)

TM_KINDS = [  # (option folder, Arsenal name, description, options table as Lua)
    ('credit', 'Super Credits', 'In Super Credit blue.', "{ kinds = { credit = true } }"),
    ('medal', 'Medals', 'In medal yellow.', "{ kinds = { medal = true } }"),
    ('common', 'Common Samples', 'In green.', "{ kinds = { common = true } }"),
    ('rare', 'Rare Samples', 'In orange.', "{ kinds = { rare = true } }"),
    ('super', 'Super Samples', 'In pink.', "{ kinds = { super = true } }"),
    ('requisition', 'Requisition Slips', 'In requisition yellow.', "{ kinds = { requisition = true } }"),
    ('ammo', 'Ammo Boxes', "In the game's ammo yellow.", "{ kinds = { ammo = true } }"),
    ('grenade', 'Grenade Packs', 'In olive green.', "{ kinds = { grenade = true } }"),
    ('stim', 'Stim Packs', 'In blue.', "{ kinds = { stim = true } }"),
]
TM_COLORS = {'credit': (115, 233, 242), 'super': (255, 114, 211), 'rare': (255, 151, 64), 'medal': (255, 221, 31),
             'common': (95, 220, 60), 'requisition': (244, 247, 56), 'ammo': (255, 234, 128), 'grenade': (135, 170, 45),
             'stim': (60, 140, 255), 'fabricator': (190, 20, 30), 'bulkfab': (190, 20, 30), 'ilship': (190, 20, 30), 'bughole': (190, 20, 30)}
# 0.6.0: Weapons (a kind outside the ledger), Still Radar, and the keys. Key ids are the addon's KEYS names.
WEAPON_KIND = ('weapon', 'Weapons', "Support weapons and expendables lying on the ground (a fallen Helldiver's, one set down, an unused drop), each with its own silhouette, on the radar and as world markers. Not in the ledger; weapons someone is holding or carrying aren't shown.",
               "{ kinds = { weapon = true } }")
# 0.6.0: Enemy Structures (one option for both kinds), in Treasure Map 1.4.0's deep red
STRUCT_KIND = ('structures', 'Enemy Structures', "Bot fabricators, Bulk Fabricators, Illuminate warp ships and bug holes, in deep red, on the radar (farther ones on its edge), in the ledger and as world markers. Fabricators, Bulk Fabricators and warp ships drop off once destroyed, bug holes once closed.",
               "{ kinds = { fabricator = true, bulkfab = true, ilship = true, bughole = true } }")
KEY_LABELS = {'insert': 'Insert', 'home': 'Home', 'end': 'End', 'delete': 'Delete', 'pageup': 'Page Up', 'pagedown': 'Page Down',
              'pause': 'Pause', 'scrolllock': 'Scroll Lock', 'numpad0': 'Numpad 0', 'numpaddot': 'Numpad .', 'numpadmul': 'Numpad *',
              'numpaddiv': 'Numpad /', 'off': 'Off'}
KEY_CAPS = {'pageup': 'PgUp', 'pagedown': 'PgDn', 'scrolllock': 'ScrLk', 'numpad0': 'Num 0', 'numpaddot': 'Num .', 'numpadmul': 'Num *',
            'numpaddiv': 'Num /', 'insert': 'Ins', 'delete': 'Del', 'pause': 'Pause', 'home': 'Home', 'end': 'End', 'off': 'Off'}
def key_label(k): return KEY_LABELS.get(k, k.upper())
def key_cap(k): return KEY_CAPS.get(k, k.upper())
_KEY_TAIL = ['insert', 'home', 'end', 'delete', 'pageup', 'pagedown', 'pause', 'scrolllock', 'numpad0', 'numpaddot', 'numpadmul', 'numpaddiv', 'off']
# Arsenal ticks every option and picks the first sub-option by default, so each list starts with the default key.
HIDE_KEYS = ['f7'] + [f'f{i}' for i in range(1, 13) if i != 7] + _KEY_TAIL
MARKER_KEYS = ['f8'] + [f'f{i}' for i in range(1, 13) if i != 8] + _KEY_TAIL
ZOOM_KEYS = [('numpad', 'Numpad + / Numpad - (default)', '+', '-'), ('page', 'Page Up / Page Down', 'PgUp', 'PgDn'), ('homeend', 'Home / End', 'Home', 'End'), ('insdel', 'Insert / Delete', 'Ins', 'Del'),
             ('numpad82', 'Numpad 8 / Numpad 2', 'Num 8', 'Num 2'), ('brackets', '] / [', ']', '['), ('off', 'Off', 'Off', None)]
OPACITY = [100, 75, 50, 25, 0]
RANGES = [150, 75, 100, 200, 250, 300]          # meters from me to the radar's edge; the first is the default
MARKER_RANGES = [50, 25, 100, 200, 'endless']   # 'endless': no limit (the addon's ENDLESS)


def options_resource(folder, table):
    name = 'mods/chef/treasure_radar/options/' + folder
    src = ('-- HD2-Options: mods/chef/treasure_radar\n'
           f'-- Treasure Radar option "{folder}": merged into the addon\'s options by the loader.\n'
           f'return {table}\n').encode()
    return (h.resource_hash(name), h.lua_resource(src))


def write_folder(path, entries):
    os.makedirs(path, exist_ok=True)
    h.write_lua_archive(os.path.join(path, '9ba626afa44a3aa3.patch_0'), entries, HEADER)


def zip_dir(src, dest):
    """the same zip on every build: sorted paths, fixed dates and attributes"""
    paths = []
    for root, dirs, files in os.walk(src):
        dirs.sort()
        for f in sorted(files):
            paths.append(os.path.join(root, f))
    paths.sort(key=lambda p: os.path.relpath(p, src).replace(os.sep, '/'))
    with zipfile.ZipFile(dest, 'w', zipfile.ZIP_DEFLATED) as z:
        for full in paths:
            info = zipfile.ZipInfo(os.path.relpath(full, src).replace(os.sep, '/'), ZIP_DATE)
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, open(full, 'rb').read(), compresslevel=9)


def build_tm():
    import icon_textures, radar_textures as rt, patch_writer
    from PIL import Image
    d = os.path.join(OUT, 'treasure_radar')
    shutil.rmtree(d, ignore_errors=True)
    addon = open(os.path.join(HERE, 'treasure_radar.lua'), encoding='utf-8').read()
    assert addon.startswith('-- HD2-Addon: mods/chef/treasure_radar\n')
    tag = TM_VERSION + (' (tester)' if TESTER else (f' (test {TEST})' if TEST else ''))
    addon, n = re.subn(r"^local M = \{ version = '[^']*' \}$", "local M = { version = '%s' }" % tag, addon, flags=re.M)
    assert n == 1
    textures, lines = [], []
    # --weapons-from: the release's own weapon textures, by resource id (its core patch's .gpu_resources hold the pixels)
    from_release = {}
    from_release_zip = args[args.index('--weapons-from') + 1] if '--weapons-from' in args else None
    if from_release_zip:
        with zipfile.ZipFile(args[args.index('--weapons-from') + 1]) as z:
            tmp = os.path.join(OUT, '_weapons_from'); os.makedirs(tmp, exist_ok=True)
            for ext in ('', '.gpu_resources', '.stream'):
                open(os.path.join(tmp, 'p' + ext), 'wb').write(z.read('core/9ba626afa44a3aa3.patch_0' + ext))
        for e in h.read_archive(os.path.join(tmp, 'p')):
            if e['tid'] == TEXTURE: from_release[e['fid']] = e['gpu']
        shutil.rmtree(tmp, ignore_errors=True)

    def tex(key, img, lua_key=None):
        img = img.convert('RGBA')
        tid = h.resource_hash('mods/chef/treasure_radar/' + key)
        pixels = img.tobytes()
        if key.startswith('weapon_') and tid in from_release:
            assert len(from_release[tid]) == len(pixels), key
            pixels = from_release[tid]
        textures.append((tid, TEXTURE, icon_textures.texture_resource(img.width, img.height), pixels, b'', 64))
        if lua_key is not False:
            lines.append("%s = '%016x'" % (lua_key or 'TEXTURES.' + key, tid))
        return tid

    def sized(key, master, w, ht, lua_key=None, ui=True, steps=rt.LADDER):
        """a texture shipped at each size of its ladder (radar_textures.ladder), each shrunk straight from the 4x master:
        the biggest under the texture's own id (and lua_key), the rest as key_w<width>; with ui, each one's UI-world copy"""
        lua_key = lua_key or 'TEXTURES.' + key
        ladder = []
        for i, size in enumerate(rt.ladder(w, ht, steps)):
            im = master.resize(size, Image.LANCZOS)
            k2 = key if i == 0 else '%s_w%d' % (key, size[0])
            tid = tex(k2, im, lua_key if i == 0 else False)
            if ui:
                uid = tex(k2 + '_ui', rt.ui_copy(im), False)
                lines.append("TEXTURES_UI['%016x'] = '%016x'" % (tid, uid))
            ladder.append((size[0], tid))
        ladder.reverse()
        lines.append('TEXTURE_SIZES[%s] = { %s }' % (lua_key, ', '.join("%d, '%016x'" % e for e in ladder)))
    # the pickup icons (icons.py: the game's pickup icons redrawn), each in its kind's color with a dark outline
    S = icon_textures.SIZE
    for kid, rgb in TM_COLORS.items():
        sized('icon2_' + kid, icon_textures.icon_master(kid, rgb), S, S, 'TEXTURES.' + kid)
    # the sonar panel (with N E S W, and without them for Rotate With View), the ledger's tile, the
    # check mark, the blip glow and the sweep's frames; the UI world's copies (radar_textures.ui_copy) are used below
    # native Render Scale
    T = rt.DISC_TOP
    sized('disc', rt.sonar_disc(True, master=True), T, T, steps=rt.LADDER[:5])
    sized('disc_plain', rt.sonar_disc(False, master=True), T, T, steps=rt.LADDER[:5])
    # the ledger's tile (0.6.0 Test 23: the ledger is a grid of tiles), a rounded square at each size
    sized('tile', rt.tile(master=True), 120, 136, ui=False)
    sized('check', rt.check(master=True), 64, 64, ui=False)
    tex('glow', rt.glow())
    lines.append('TEXTURES.sweep = {}')
    for i in range(rt.SWEEP_FRAMES):
        fr = rt.sweep_frame(i)
        tex('sweep_%d' % i, fr, 'TEXTURES.sweep[%d]' % (i + 1))
        tex('sweep_%d_ui' % i, rt.ui_copy(fr), 'TEXTURES_UI[TEXTURES.sweep[%d]]' % (i + 1))
    # the characters for numbers, at six sizes, each at its own width: GLYPHS[i] = { cap = px, ['0'] = { id, width / cap } }
    lines.append('GLYPH_PAD = %d' % rt.GLYPH_PAD)
    for gi, cap in enumerate(rt.GLYPH_SIZES):
        lines.append('GLYPHS[%d] = { cap = %d }' % (gi + 1, cap))
        for ch in rt.GLYPHS:
            img, ratio = rt.glyph(ch, cap)
            tid = h.resource_hash('mods/chef/treasure_radar/glyph%d_%d' % (cap, ord(ch)))
            textures.append((tid, TEXTURE, icon_textures.texture_resource(img.width, img.height), img.tobytes(), b'', 64))
            lines.append("GLYPHS[%d]['%s'] = { '%016x', %.4f }" % (gi + 1, ch, tid, ratio))
    # the weapons' silhouettes (weapon_textures.py; the game's marker icons from weapon_icons/, else a generic shape)
    import weapon_textures as wt
    wdir = os.path.join(HERE, 'weapon_icons')
    wtex = wt.all_textures(wdir if os.path.isdir(wdir) else None, master=True)
    if from_release:
        # every weapon the release has a silhouette for (its pixels replace these placeholders in tex())
        for uid in wt.WEAPONS:
            if uid not in wtex and h.resource_hash('mods/chef/treasure_radar/weapon_' + uid) in from_release:
                wtex[uid] = wtex['generic']
    for key, im in sorted(wtex.items()):
        if key == 'generic':
            sized('weapon_generic', im, wt.W, wt.H, 'TEXTURES.weapon_generic')
        else:
            sized('weapon_' + key, im, wt.W, wt.H, "TEXTURES.weapons['%s']" % key)
    if '--textures' in args:
        tdir = os.path.join(OUT, 'textures'); os.makedirs(tdir, exist_ok=True)
        for t in textures:
            hh, ww = struct.unpack('<2I', t[2][192:][12:20])
            Image.frombytes('RGBA', (ww, hh), t[3]).save(os.path.join(tdir, '%016x.png' % t[0]))
    assert addon.count('--@@ICON_TEXTURES@@') == 1
    addon = addon.replace('--@@ICON_TEXTURES@@', '\n'.join(lines)).encode()
    # no loader here: Chef Shared Loader is its own mod and runs the addon
    core = os.path.join(d, 'core'); os.makedirs(core, exist_ok=True)
    lua_entries = [(h.resource_hash('mods/chef/treasure_radar'), LUA, h.lua_resource(addon), b'', b'', 64)]
    rid, data = options_resource('core', '{ radar = true }')
    lua_entries.append((rid, LUA, data, b'', b'', 64))
    toc, gpu, stream = patch_writer.write(lua_entries + textures, [(LUA, 64), (TEXTURE, 64)], header=HEADER, pad_toc=True)
    patch_writer.check(toc, gpu, stream)
    base = os.path.join(core, '9ba626afa44a3aa3.patch_0')
    open(base, 'wb').write(toc); open(base + '.gpu_resources', 'wb').write(gpu); open(base + '.stream', 'wb').write(stream)
    # the option folders
    write_folder(os.path.join(d, 'ledger'), [options_resource('ledger', '{ ledger = true }')])
    for folder, _, _, table in TM_KINDS:
        write_folder(os.path.join(d, folder), [options_resource(folder, table)])
    for key in ('medium', 'small', 'large'):
        write_folder(os.path.join(d, f'size_{key}'), [options_resource(f'size_{key}', "{ size = '%s' }" % key)])
    write_folder(os.path.join(d, 'rotate'), [options_resource('rotate', '{ rotate = true }')])
    for m in MARKER_RANGES:
        write_folder(os.path.join(d, f'markers_{m}'), [options_resource(f'markers_{m}', '{ markers = %d }' % (100000 if m == 'endless' else m))])
    for m in RANGES:
        write_folder(os.path.join(d, f'range_{m}'), [options_resource(f'range_{m}', '{ range = %d }' % m)])
    for pct in OPACITY:
        write_folder(os.path.join(d, f'opacity_{pct}'), [options_resource(f'opacity_{pct}', '{ opacity = %.2f }' % (pct / 100))])
    write_folder(os.path.join(d, WEAPON_KIND[0]), [options_resource(WEAPON_KIND[0], WEAPON_KIND[3])])
    write_folder(os.path.join(d, STRUCT_KIND[0]), [options_resource(STRUCT_KIND[0], STRUCT_KIND[3])])
    write_folder(os.path.join(d, 'animation'), [options_resource('animation', '{ animation = true }')])
    write_folder(os.path.join(d, 'tabhold'), [options_resource('tabhold', '{ tab_hold = true }')])
    for k in HIDE_KEYS:
        write_folder(os.path.join(d, f'hidekey_{k}'), [options_resource(f'hidekey_{k}', "{ hide_key = '%s' }" % k)])
    for k in MARKER_KEYS:
        write_folder(os.path.join(d, f'markerkey_{k}'), [options_resource(f'markerkey_{k}', "{ marker_key = '%s' }" % k)])
    for k, _, _, _ in ZOOM_KEYS:
        write_folder(os.path.join(d, f'zoom_{k}'), [options_resource(f'zoom_{k}', "{ zoom_keys = '%s' }" % k)])
    # a 256x256 picture for every option and sub-option (option_icons.py), in images/
    import option_icons
    idir = os.path.join(d, 'images'); os.makedirs(idir, exist_ok=True)
    images = option_icons.all_images([f for f, _, _, _ in TM_KINDS] + [WEAPON_KIND[0], STRUCT_KIND[0]])
    images['animation'], images['tabhold'] = option_icons.make_animation(), option_icons.make_tabhold()
    images['hidekey'] = option_icons.make_key('F7', 'HIDE')
    images['markerkey'] = option_icons.make_key('F8', 'MARKERS')
    images['zoomkeys'] = option_icons.make_keypair('+', '-')
    for k in HIDE_KEYS: images[f'hidekey_{k}'] = option_icons.make_key(key_cap(k), 'HIDE')
    for k in MARKER_KEYS: images[f'markerkey_{k}'] = option_icons.make_key(key_cap(k), 'MARKERS')
    for k, _, a, b in ZOOM_KEYS: images[f'zoom_{k}'] = option_icons.make_keypair(a, b) if b else option_icons.make_key('Off', 'ZOOM')
    for name, im in images.items():
        if name == 'weapon' and from_release_zip:
            # the Weapons option's picture shows game icons: from the release, like the silhouettes
            with zipfile.ZipFile(from_release_zip) as z: open(os.path.join(idir, name + '.png'), 'wb').write(z.read('images/weapon.png'))
            continue
        im.convert('RGB').save(os.path.join(idir, name + '.png'), optimize=True)

    def img(name): return f'images/{name}.png'
    options = [
        {'Name': 'Treasure Radar (core)', 'Description': "The round sonar radar, just left of where the game's map opens (bottom right) and level with it, so it never covers the map. Keep this ticked. F7, or tapping Tab twice quickly, hides or shows the radar and the ledger; the numpad's + and - zoom it (each can be changed below). Every setting can also be changed in game in Chef Shared Loader's options menu (F9).",
         'Image': img('core'), 'Include': ['core']},
        {'Name': 'Loot Ledger', 'Description': "Left of the radar: a tile for each kind with how many are left in the mission (structures, then credits, medals and slips, then samples, then supplies); a cleared kind gets a check mark.", 'Image': img('ledger'), 'Include': ['ledger']},
        {'Name': 'Opacity', 'Description': "How solid the radar's panel and sweep and the ledger's tiles are; the icons and counts stay solid (at 0% only they're left). Tick it and pick a level (100% without it).", 'Image': img('opacity'), 'Include': [],
         'SubOptions': [{'Name': f'{pct}%', 'Description': f"The radar's panel and sweep and the ledger's tiles at {pct}%.", 'Image': img(f'opacity_{pct}'), 'Include': [f'opacity_{pct}']} for pct in OPACITY]},
        {'Name': 'Size', 'Description': 'How big the radar and the ledger are. Tick it and pick a size (Medium without it).', 'Image': img('size'), 'Include': [],
         'SubOptions': [{'Name': n, 'Description': dsc, 'Image': img(f'size_{k}'), 'Include': [f'size_{k}']} for k, n, dsc in
                        [('medium', 'Medium (default)', "The radar at 75% of the game's map circle."), ('small', 'Small', 'At 60%.'), ('large', 'Large', "At 100%: as big as the game's map circle.")]]},
        {'Name': 'Rotate With View', 'Description': 'The radar turns with you: the way you look is always up, and N, E, S and W move around the rim.',
         'Image': img('rotate'), 'Include': ['rotate']},
        {'Name': 'World Markers', 'Description': "Each pickup's icon floats over it in the world, with how far it is, within the range you pick. F8 hides or shows them.", 'Image': img('markers'), 'Include': [],
         'SubOptions': [{'Name': ('Endless' if m == 'endless' else f'{m} m' + (' (default)' if m == 50 else '')),
                         'Description': ('Markers on every pickup, however far.' if m == 'endless' else f'Markers on pickups within {m} m.'),
                         'Image': img(f'markers_{m}' if m != 'endless' else 'markers'), 'Include': [f'markers_{m}']} for m in MARKER_RANGES]},
        {'Name': 'Range', 'Description': "How far the radar reaches, from you to its edge. Tick it and pick a range (150 m without it). Loot farther out sits on the edge, pointing the way.", 'Image': img('range'), 'Include': [],
         'SubOptions': [{'Name': f'{m} m' + (' (default)' if m == 150 else ''), 'Description': f'The radar reaches {m} m.', 'Image': img(f'range_{m}'), 'Include': [f'range_{m}']} for m in RANGES]},
        {'Name': 'Radar Animation', 'Description': "The sweep that turns every 3 seconds and lights each pickup up as it passes. Untick it for a still radar with every pickup at full strength.", 'Image': img('animation'), 'Include': ['animation']},
        {'Name': 'Hide Key', 'Description': "The key that hides or shows the radar and the ledger (F7 by default). Off: no key (a quick double tap of Tab still works with Double-Tap Tab To Hide).", 'Image': img('hidekey'), 'Include': [],
         'SubOptions': [{'Name': key_label(k) + (' (default)' if k == 'f7' else ''), 'Description': ('No key; a quick double tap of Tab still hides or shows the radar if Double-Tap Tab To Hide is ticked.' if k == 'off' else f'{key_label(k)} hides or shows the radar and the ledger.'),
                         'Image': img(f'hidekey_{k}'), 'Include': [f'hidekey_{k}']} for k in HIDE_KEYS]},
        {'Name': 'Double-Tap Tab To Hide', 'Description': "Tapping Tab twice quickly (within half a second) hides or shows the radar and the ledger; the map opens and closes again, so it ends up closed. A single tap still just opens the map.", 'Image': img('tabhold'), 'Include': ['tabhold']},
        {'Name': 'Zoom Keys', 'Description': "The keys that zoom the radar in and out (the numpad's + and - by default).", 'Image': img('zoomkeys'), 'Include': [],
         'SubOptions': [{'Name': n, 'Description': ('No zoom keys: the radar keeps its Range.' if k == 'off' else f'{a} zooms in, {b} zooms out.'),
                         'Image': img(f'zoom_{k}'), 'Include': [f'zoom_{k}']} for k, n, a, b in ZOOM_KEYS]},
        {'Name': 'Markers Key', 'Description': "The key that hides or shows the world markers (F8 by default).", 'Image': img('markerkey'), 'Include': [],
         'SubOptions': [{'Name': key_label(k) + (' (default)' if k == 'f8' else ''), 'Description': ('No key: the world markers always show.' if k == 'off' else f'{key_label(k)} hides or shows the world markers.'),
                         'Image': img(f'markerkey_{k}'), 'Include': [f'markerkey_{k}']} for k in MARKER_KEYS]}]
    for folder, name, desc, _ in TM_KINDS + [WEAPON_KIND, STRUCT_KIND]:
        options.append({'Name': name, 'Description': desc, 'Image': img(folder), 'Include': [folder]})
    name = f'Treasure Radar {TM_VERSION}' + (' Tester' if TESTER else (f' Test {TEST}' if TEST else ''))
    json.dump({'Version': 1, 'Guid': TM_TEST_GUID if (TESTER or TEST) else TM_GUID, 'Name': name, 'IconPath': 'thumbnail.png',
               'Description': ("A round sonar radar beside where the game's map opens (bottom right) with every sample, medal, Super Credit, Requisition Slip "
                               "and supply around you, using the game's pickup icons, plus a ledger of what's left, markers over the loot near you and, if you like, the weapons on the ground. "
                               f"Needs Chef Shared Loader {NEEDS_LOADER} or newer, installed as its own mod: without it Treasure Radar does nothing. "
                               "Its log is treasure_radar.log in %APPDATA%\\Arrowhead\\Helldivers2."),
               'Options': options}, open(os.path.join(d, 'manifest.json'), 'w'), indent=2)
    thumb = Image.open(os.path.join(HERE, 'artwork', 'thumbnail.png')).convert('RGB')
    if TESTER or TEST:
        from PIL import ImageDraw
        dr = ImageDraw.Draw(thumb)
        dr.rectangle((0, 462, 512, 512), fill=(255, 231, 16))
        try:
            from PIL import ImageFont
            f = ImageFont.truetype(os.path.join(HERE, 'fonts', 'Poppins-Bold.ttf'), 30)
            dr.text((256, 487), 'TESTER', font=f, fill=(17, 17, 17), anchor='mm')
        except OSError:
            pass
    thumb.save(os.path.join(d, 'thumbnail.png'), optimize=True)
    suffix = '-Tester' if TESTER else (f'-Test-{TEST}' if TEST else '')
    z = os.path.join(OUT, f'Treasure-Radar-{TM_VERSION}{suffix}.zip')
    zip_dir(d, z)
    return z


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    print('built', build_tm())
