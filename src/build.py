#!/usr/bin/env python3
"""Builds Treasure Radar for Arsenal (and the standalone Chef Loader).

  python3 build.py <out dir>              -> <out dir>/Treasure-Radar-<ver>.zip (the release)
  python3 build.py <out dir> --tester     -> Treasure-Radar-<ver>-Tester.zip (the release plus the HUD Calibration option)
  python3 build.py <out dir> --test N     -> Treasure-Radar-<ver>-Test-N.zip (a numbered test build, on the Tester's id)
  add --loader to also build Chef-Loader-<ver>.zip; --textures writes every texture as a PNG (for previews);
  --header-from <a working Lua patch> takes the patch header from a patch that works on the current game.

Treasure Radar is an Arsenal mod with Options. The core folder holds the game's `boot` script replaced by its own copy
of Chef Loader (loader.lua), the addon (treasure_radar.lua) and its textures; every option folder ships a small
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

LOADER_VERSION = '0.1.0'
TM_VERSION = '0.5.0'
LOADER_GUID = '2d6f0b8e-91c4-4a37-b5e2-7c0a94f13d58'
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
             'stim': (60, 140, 255)}
OPACITY = [100, 75, 50, 25, 0]
RANGES = [150, 75, 100, 200, 250, 300]          # meters from me to the radar's edge; the first is the default
MARKER_RANGES = [50, 25, 100]


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


def build_loader():
    d = os.path.join(OUT, 'loader')
    shutil.rmtree(d, ignore_errors=True)
    src = open(os.path.join(HERE, 'loader.lua'), 'rb').read()
    write_folder(d, [(h.resource_hash('boot'), h.lua_resource(src))])
    json.dump({'Version': 1, 'Guid': LOADER_GUID, 'Name': f'Chef Loader {LOADER_VERSION}', 'IconPath': 'thumbnail.png',
               'Description': ("Loads Chef's Lua mods on the current game build (Lua 5.1). Replaces the game's empty boot "
                               "script; finds mods/chef addons in your installed mods and runs them, each in its own space. "
                               "A mod that crashes the game is switched off on the next launch and named in chef_loader.log "
                               "(%LOCALAPPDATA%). Only one mod can replace boot: don't combine with others that do.")},
              open(os.path.join(d, 'manifest.json'), 'w'), indent=2)
    shutil.copy(os.path.join(HERE, 'artwork', 'thumbnail.png'), d)
    z = os.path.join(OUT, f'Chef-Loader-{LOADER_VERSION}.zip')
    zip_dir(d, z)
    return z


def builtin_loader():
    """Treasure Radar's own copy of the loader: runs only Treasure Radar, and logs to treasure_radar.log."""
    src = open(os.path.join(HERE, 'loader.lua'), encoding='utf-8').read()
    for key, line in (('LOADER', f"local LOADER = 'Treasure Radar {TM_VERSION}: Chef Loader'"), ('FILES', "local FILES = 'treasure_radar'"),
                      ('ALLOW', "local ALLOW = '^mods/chef/treasure_radar'")):
        src, n = re.subn(r'^local %s = .*--@@%s@@.*$' % (key, key), line + '  --@@%s@@' % key, src, flags=re.M)
        assert n == 1, key
    head = f"-- Treasure Radar {TM_VERSION}: its built-in loader (Chef Loader {LOADER_VERSION}), running only Treasure Radar\n"
    return (head + src).encode()


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

    def tex(key, img, lua_key=None):
        img = img.convert('RGBA')
        tid = h.resource_hash('mods/chef/treasure_radar/' + key)
        textures.append((tid, TEXTURE, icon_textures.texture_resource(img.width, img.height), img.tobytes(), b'', 64))
        lines.append("%s = '%016x'" % (lua_key or 'TEXTURES.' + key, tid))
    # the pickup icons (icons.py: the game's pickup icons redrawn), each in its kind's color with a dark outline
    for kid, rgb in TM_COLORS.items():
        tex('icon2_' + kid, icon_textures.icon_image(kid, rgb), 'TEXTURES.' + kid)
    # the sonar panel (with N E S W, and without them for Rotate With View), the ledger's pill (fill and outline), the
    # check mark, the blip glow and the sweep's frames
    tex('disc', rt.sonar_disc())
    tex('disc_plain', rt.sonar_disc(False))
    tex('pill_fill', rt.pill(False))
    tex('pill_ring', rt.pill(True))
    tex('check', rt.check())
    tex('glow', rt.glow())
    lines.append('TEXTURES.sweep = {}')
    for i in range(rt.SWEEP_FRAMES):
        tex('sweep_%d' % i, rt.sweep_frame(i), 'TEXTURES.sweep[%d]' % (i + 1))
    # the characters for numbers, at four sizes, each at its own width: GLYPHS[i] = { cap = px, ['0'] = { id, width / cap } }
    lines.append('GLYPH_PAD = %d' % rt.GLYPH_PAD)
    for gi, cap in enumerate(rt.GLYPH_SIZES):
        lines.append('GLYPHS[%d] = { cap = %d }' % (gi + 1, cap))
        for ch in rt.GLYPHS:
            img, ratio = rt.glyph(ch, cap)
            tid = h.resource_hash('mods/chef/treasure_radar/glyph%d_%d' % (cap, ord(ch)))
            textures.append((tid, TEXTURE, icon_textures.texture_resource(img.width, img.height), img.tobytes(), b'', 64))
            lines.append("GLYPHS[%d]['%s'] = { '%016x', %.4f }" % (gi + 1, ch, tid, ratio))
    if '--textures' in args:
        tdir = os.path.join(OUT, 'textures'); os.makedirs(tdir, exist_ok=True)
        for t in textures:
            hh, ww = struct.unpack('<2I', t[2][192:][12:20])
            Image.frombytes('RGBA', (ww, hh), t[3]).save(os.path.join(tdir, '%016x.png' % t[0]))
    assert addon.count('--@@ICON_TEXTURES@@') == 1
    addon = addon.replace('--@@ICON_TEXTURES@@', '\n'.join(lines)).encode()
    boot = builtin_loader()
    open(os.path.join(OUT, 'treasure_radar_boot.lua'), 'wb').write(boot)
    core = os.path.join(d, 'core'); os.makedirs(core, exist_ok=True)
    lua_entries = [(h.resource_hash('boot'), LUA, h.lua_resource(boot), b'', b'', 64),
                   (h.resource_hash('mods/chef/treasure_radar'), LUA, h.lua_resource(addon), b'', b'', 64)]
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
    calibrate = TESTER or TEST
    if calibrate:
        write_folder(os.path.join(d, 'calibrate'), [options_resource('calibrate', '{ calibrate = true }')])
    for m in MARKER_RANGES:
        write_folder(os.path.join(d, f'markers_{m}'), [options_resource(f'markers_{m}', '{ markers = %d }' % m)])
    for m in RANGES:
        write_folder(os.path.join(d, f'range_{m}'), [options_resource(f'range_{m}', '{ range = %d }' % m)])
    for pct in OPACITY:
        write_folder(os.path.join(d, f'opacity_{pct}'), [options_resource(f'opacity_{pct}', '{ opacity = %.2f }' % (pct / 100))])
    # a 256x256 picture for every option and sub-option (option_icons.py), in images/
    import option_icons
    idir = os.path.join(d, 'images'); os.makedirs(idir, exist_ok=True)
    for name, im in option_icons.all_images([f for f, _, _, _ in TM_KINDS]).items():
        if name == 'calibrate' and not calibrate:
            continue
        im.convert('RGB').save(os.path.join(idir, name + '.png'), optimize=True)

    def img(name): return f'images/{name}.png'
    options = [
        {'Name': 'Treasure Radar (core)', 'Description': "The round sonar radar, where the game's map opens (bottom right): the open map covers it. Keep this ticked. F7, or holding Tab, hides or shows the radar and the ledger; the numpad's + and - zoom it.",
         'Image': img('core'), 'Include': ['core']},
        {'Name': 'Loot Ledger', 'Description': "Left of the radar: a pill for each kind with how many are left in the mission; a cleared kind gets a check mark.", 'Image': img('ledger'), 'Include': ['ledger']},
        {'Name': 'Opacity', 'Description': "How solid the radar's panel and sweep and the ledger's pills are; the icons and counts stay solid (at 0% only they're left). Tick it and pick a level (100% without it).", 'Image': img('opacity'), 'Include': [],
         'SubOptions': [{'Name': f'{pct}%', 'Description': f"The radar's panel and sweep and the ledger's pills at {pct}%.", 'Image': img(f'opacity_{pct}'), 'Include': [f'opacity_{pct}']} for pct in OPACITY]},
        {'Name': 'Size', 'Description': 'How big the radar and the ledger are. Tick it and pick a size (Medium without it).', 'Image': img('size'), 'Include': [],
         'SubOptions': [{'Name': n, 'Description': dsc, 'Image': img(f'size_{k}'), 'Include': [f'size_{k}']} for k, n, dsc in
                        [('medium', 'Medium (default)', "The radar at 75% of the game's map circle."), ('small', 'Small', 'At 60%.'), ('large', 'Large', "At 100%: as big as the game's map circle.")]]},
        {'Name': 'Rotate With View', 'Description': 'The radar turns with you: the way you look is always up, and N, E, S and W move around the rim.',
         'Image': img('rotate'), 'Include': ['rotate']},
        {'Name': 'World Markers', 'Description': "Each pickup's icon floats over it in the world, with how far it is, within the range you pick. F8 hides or shows them.", 'Image': img('markers'), 'Include': [],
         'SubOptions': [{'Name': f'{m} m' + (' (default)' if m == 50 else ''), 'Description': f'Markers on pickups within {m} m.', 'Image': img(f'markers_{m}'), 'Include': [f'markers_{m}']} for m in MARKER_RANGES]},
        {'Name': 'Range', 'Description': "How far the radar reaches, from you to its edge. Tick it and pick a range (150 m without it). Loot farther out sits on the edge, pointing the way.", 'Image': img('range'), 'Include': [],
         'SubOptions': [{'Name': f'{m} m' + (' (default)' if m == 150 else ''), 'Description': f'The radar reaches {m} m.', 'Image': img(f'range_{m}'), 'Include': [f'range_{m}']} for m in RANGES]}]
    if calibrate:
        options.append({'Name': 'HUD Calibration (Tester)', 'Description': "Tester only: a magenta ring where Treasure Radar thinks the game's map rim is, with your HUD settings written above it, drawn over the open map. Screenshot it with the map open for each HUD setting.",
                        'Image': img('calibrate'), 'Include': ['calibrate']})
    for folder, name, desc, _ in TM_KINDS:
        options.append({'Name': name, 'Description': desc, 'Image': img(folder), 'Include': [folder]})
    name = f'Treasure Radar {TM_VERSION}' + (' Tester' if TESTER else (f' Test {TEST}' if TEST else ''))
    json.dump({'Version': 1, 'Guid': TM_TEST_GUID if (TESTER or TEST) else TM_GUID, 'Name': name, 'IconPath': 'thumbnail.png',
               'Description': ("A round sonar radar where the game's map opens (bottom right) with every sample, medal, Super Credit, Requisition Slip "
                               "and supply around you, using the game's pickup icons, plus a ledger of what's left and markers over the loot near you. "
                               "Has its own loader built in (it replaces the game's empty boot script; log: treasure_radar.log in %LOCALAPPDATA%), "
                               "so don't use it together with another mod that replaces boot."),
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
    built = [build_tm()]
    if '--loader' in args:
        built.append(build_loader())
    for z in built:
        print('built', z)
