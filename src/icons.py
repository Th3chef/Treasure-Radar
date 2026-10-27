"""Treasure Radar's icon shapes. The loot kinds use the game's own icons (pickup_icons/<kind>.png, taken from the
player's game with Filediver; they're game files, so they aren't in this repository). Without them, and for the enemy
structures (the game has no icon for each), I draw vector shapes: laid out on a 36-unit-high grid (y down) and
rendered at any height with 4x supersampling.
mask(kind, height) -> 'L' image that fits a height x height box: 255 = the icon's body, 0 = empty (cut-outs show the
map through)."""
import math
import os
from PIL import Image, ImageChops, ImageDraw, ImageFilter

# the game's icon for each loot kind (the texture each one is cut from, for re-exporting after a game update):
# Super Credits, medal, requisition slip and the samples are the game's reward icons, the supplies their pickups' own
# marker icons, and the stim pack the HUD's syringe
GAME_ICONS = {'credit': '9414ab4f02745820', 'medal': '980cf7bb9ce23913', 'requisition': '89d9a4e1eddb5c0a',
              'common': '5d9cd53cc1d3c44c', 'rare': '1ff270be2076cca6', 'super': '8d99a7a7ee0d21cc',
              'ammo': '7615d6a35c657087', 'grenade': '4c3bef8bc16021c9', 'stim': '93b43ada76587340',
              'enemy': '6a6598587d4bc8f5', 'enemydot': '932be8284447e469'}
# how a shape is read from its icon when it isn't simply the alpha (or the darkest channel of a white-on-black one):
# the skull has a dark rim baked into its alpha (only its light body is kept)
READ = {'enemy': 'light'}
PICKUP_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pickup_icons')
# kinds that share another's game icon in their own color: the SEAF troopers' blue dot is the enemy dot
SAME = {'frienddot': 'enemydot', 'squaddot': 'enemydot'}
# the reward icons for Super Credits and requisition slips have a bar under the square; I keep only the square
DROP_BAR = ('credit', 'requisition')
# the game's syringe lies flat and thin; tilted (needle up to the left) it fills the square like the other icons
TILT = {'stim': -45}

GRID = 36
WIDTH = {'fabricator': 36, 'bulkfab': 36, 'ilship': 36, 'bughole': 36, 'titanhole': 36, 'ammo': 36, 'grenade': 32, 'stim': 36, 'medal': 26, 'common': 36, 'rare': 36, 'super': 36, 'credit': 36, 'requisition': 36, 'enemy': 30, 'enemydot': 36, 'frienddot': 36, 'squaddot': 36}


def octagon(cx, cy, rx, ry):
    return [(cx + rx * math.sin(math.radians(45 * k)), cy - ry * math.cos(math.radians(45 * k))) for k in range(8)]


def ellipse(d, cx, cy, r, fill):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def draw_medal(d):
    # ribbons above and below: two triangles meeting in the middle
    for top in (True, False):
        def p(x, y): return (x, y if top else GRID - y)
        d.polygon([p(5, 0), p(8.6, 0), p(13, 1.6), p(17.4, 0), p(21, 0), p(21, 5), p(13, 1.9), p(5, 5)], fill=255)
    d.polygon(octagon(13, 17.8, 13, 12.9), fill=255)
    # the skull, cut out
    d.polygon([(9.5, 10.6), (16.5, 10.6), (19, 12.6), (19, 16.8), (20, 17.6), (20, 21.2), (18.6, 22.6), (16.4, 22.6),
               (16.4, 25.6), (9.6, 25.6), (9.6, 22.6), (7.4, 22.6), (6, 21.2), (6, 17.6), (7, 16.8), (7, 12.6)], fill=0)
    ellipse(d, 9.7, 19.2, 1.75, 255)
    ellipse(d, 16.3, 19.2, 1.75, 255)
    d.polygon([(12.2, 21.1), (13.8, 21.1), (13.8, 22.8), (12.2, 22.8)], fill=255)
    d.rectangle((11.7, 24.2, 12.3, 25.6), fill=255)
    d.rectangle((13.7, 24.2, 14.3, 25.6), fill=255)


def draw_common(d):
    ellipse(d, 18, 18, 18, 255)
    d.rectangle((15.2, 0, 20.4, 36), fill=0)


def draw_rare(d):
    d.rectangle((0, 0, 36, 36), fill=255)
    d.rectangle((0, 15, 21, 21), fill=0)
    d.rectangle((15, 21, 21, 36), fill=0)


def draw_super(d):
    d.rectangle((0, 0, 36, 36), fill=255)
    d.rectangle((15, 0, 21, 36), fill=0)
    d.rectangle((0, 15, 36, 21), fill=0)


def draw_credit(d):
    d.rectangle((0, 0, 36, 36), fill=255)
    d.polygon([(15, 4.2), (22.8, 4.2), (22.8, 13), (15.9, 13), (15.9, 19.5), (8, 19.5), (8, 11.2)], fill=0)
    d.polygon([(21, 16.3), (28.8, 16.3), (28.8, 25.2), (21.9, 32), (14, 32), (14, 23), (21, 23)], fill=0)


def draw_requisition(d):
    d.rectangle((0, 0, 36, 36), fill=255)
    d.rectangle((9, 4, 13, 33), fill=0)                                                   # stem
    d.rectangle((9, 4, 20, 20), fill=0)                                                   # bowl
    d.ellipse((12, 4, 28.2, 20), fill=0)
    d.rectangle((13, 8, 20, 16.2), fill=255)                                              # its hole
    d.ellipse((15.8, 8, 24.2, 16.2), fill=255)
    d.rectangle((13, 8, 15.8, 16.2), fill=255)
    d.polygon([(19.6, 19), (24.6, 19), (28.6, 33), (23.6, 33)], fill=0)                  # leg


def draw_ammo(d):
    # an ammo box, as the game's pickup icon: three solid cartridges, the middle one raised
    for x, top in ((1, 6), (13.5, 0), (26, 6)):
        w = 9
        d.polygon([(x, top + 10), (x + 0.6, top + 5.5), (x + w / 2, top), (x + w - 0.6, top + 5.5), (x + w, top + 10)], fill=255)
        d.rectangle((x, top + 9.5, x + w, top + 30), fill=255)


def draw_grenade(d):
    # a frag grenade, drawn to read as one at a glance: a segmented ("pineapple") body, the fuse head on top,
    # the spoon lever down the right side and the pin's ring at the top left
    d.ellipse((1.5, 11, 26.5, 36), fill=255)
    for box in ((1, 19.6, 27, 22.1), (1, 27, 27, 29.5), (12.8, 11, 15.2, 36)):
        d.rectangle(box, fill=0)
    d.rectangle((8, 5.5, 21, 13), fill=255)
    d.polygon([(18, 4.5), (23.5, 4.5), (31.5, 14), (31.5, 29), (28.6, 29), (28.6, 15.2), (21.5, 8.6)], fill=255)
    d.rectangle((6, 4.5, 10, 7.5), fill=255)
    d.ellipse((0, 0, 9.5, 9.5), fill=255)
    d.ellipse((2.6, 2.6, 6.9, 6.9), fill=0)


def _rot(pts, ang, cx, cy):
    c, s = math.cos(ang), math.sin(ang)
    return [(cx + u * c - v * s, cy + u * s + v * c) for u, v in pts]


def draw_stim(d):
    # a stim pack, as the game's pickup icon: a syringe lying at a slant, needle up left, plunger down right
    # (laid out along its own axis, then turned and centered in the 36-unit square)
    parts = [
        [(0, -0.9), (9, -0.9), (9, 0.9), (0, 0.9)],                              # needle
        [(8, -1.4), (14, -6.4), (14, 6.4), (8, 1.4)],                             # tip
        [(13.5, -6.6), (32.5, -6.6), (32.5, 6.6), (13.5, 6.6)],                   # barrel
        [(32, -10), (35, -10), (35, 10), (32, 10)],                               # finger flange
        [(34.5, -2.4), (40.5, -2.4), (40.5, 2.4), (34.5, 2.4)],                   # rod
        [(40, -6.5), (43.5, -6.5), (43.5, 6.5), (40, 6.5)],                       # thumb rest
    ]
    ang, k = math.radians(22), 0.8
    pts = [_rot([(u * k, v * k) for u, v in poly], ang, 0, 0) for poly in parts]
    xs = [x for poly in pts for x, _ in poly]; ys = [y for poly in pts for _, y in poly]
    ox, oy = 18 - (min(xs) + max(xs)) / 2, 18 - (min(ys) + max(ys)) / 2
    for poly in pts: d.polygon([(x + ox, y + oy) for x, y in poly], fill=255)



def draw_fabricator(d):
    # a bot fabricator: a factory with a sawtooth roof, a smokestack and a dark door
    d.rectangle((0, 17, 36, 35), fill=255)
    for x in (0, 9, 18):
        d.polygon([(x, 17.5), (x + 9, 8), (x + 9, 17.5)], fill=255)
    d.rectangle((28, 1, 34, 18), fill=255)
    d.rectangle((13, 24, 23, 35), fill=0)


def draw_bulkfab(d):
    # a Bulk Fabricator, the fabricator's big brother: a wider hall with four roof teeth, two smokestacks and a
    # wide dark bay door, so it reads apart from a fabricator at a glance
    d.rectangle((0, 17, 36, 35), fill=255)
    for x in (0, 5.5, 11, 16.5):
        d.polygon([(x, 17.5), (x + 5.5, 9), (x + 5.5, 17.5)], fill=255)
    d.rectangle((23, 3, 27.5, 18), fill=255)
    d.rectangle((30.5, 0, 35, 18), fill=255)
    d.rectangle((5, 24, 31, 35), fill=0)


def draw_ilship(d):
    # an Illuminate warp ship: a flat saucer with a dome and a dark band of lights
    d.ellipse((0, 15, 36, 29), fill=255)
    d.ellipse((9, 5, 27, 23), fill=255)
    d.rectangle((4, 21, 32, 22.5), fill=0)
    for x in (8, 17, 26):
        d.rectangle((x, 26, x + 2.5, 33), fill=255)


def draw_bughole(d):
    # a bug hole: a low rounded mound with a dark arched mouth
    d.ellipse((0, 8, 36, 52), fill=255)
    d.ellipse((11, 15, 25, 33), fill=0)
    d.rectangle((11, 24, 25, 36), fill=0)


def draw_titanhole(d):
    # a Bile Titan hole (not drawn on the radar yet): the bug hole's tunnel, wider and lower, three spikes on its back
    d.ellipse((0, 12, 36, 52), fill=255)
    for pts in ([(4, 18), (6, 4), (11, 15)], [(15, 13), (18, 1), (21, 13)], [(25, 15), (30, 4), (32, 18)]):
        d.polygon(pts, fill=255)
    d.ellipse((8, 19, 28, 35), fill=0)
    d.rectangle((8, 27, 28, 36), fill=0)


def draw_enemydot(d):
    ellipse(d, 18, 18, 18, 255)


def draw_heavy(d):
    # a plain skull (only without the game's icons)
    d.polygon([(4, 2), (26, 2), (30, 8), (30, 22), (24, 26), (24, 34), (6, 34), (6, 26), (0, 22), (0, 8)], fill=255)
    ellipse(d, 9, 15, 4, 0)
    ellipse(d, 21, 15, 4, 0)
    d.polygon([(15, 20), (18, 25), (12, 25)], fill=0)


DRAW = {'enemy': draw_heavy, 'enemydot': draw_enemydot, 'frienddot': draw_enemydot, 'squaddot': draw_enemydot, 'titanhole': draw_titanhole, 'bughole': draw_bughole, 'fabricator': draw_fabricator, 'bulkfab': draw_bulkfab, 'ilship': draw_ilship, 'ammo': draw_ammo, 'grenade': draw_grenade, 'stim': draw_stim, 'medal': draw_medal, 'common': draw_common, 'rare': draw_rare, 'super': draw_super, 'credit': draw_credit, 'requisition': draw_requisition}


def has_game_icons():
    return all(os.path.exists(os.path.join(PICKUP_DIR, k + '.png')) for k in GAME_ICONS)


_shapes = {}


def game_shape(kind):
    """the game's icon for a loot kind as an 'L' mask cropped to the shape, or None when pickup_icons/ doesn't have it"""
    kind = SAME.get(kind, kind)
    if kind in _shapes:
        return _shapes[kind]
    p = os.path.join(PICKUP_DIR, kind + '.png')
    if kind not in GAME_ICONS or not os.path.exists(p):
        _shapes[kind] = None
        return None
    im = Image.open(p).convert('RGBA')
    r, g, b, a = im.split()
    if READ.get(kind) == 'max':
        m = ImageChops.lighter(ImageChops.lighter(r, g), b)
    elif READ.get(kind) == 'light':
        m = ImageChops.multiply(a, ImageChops.darker(ImageChops.darker(r, g), b).point(lambda v: 0 if v < 120 else 255))
    elif a.getextrema()[0] < 250:
        m = a                                        # a shape on a transparent background
    else:
        # white on black with a blue glow: the darkest channel keeps the white body and drops the glow
        m = ImageChops.darker(ImageChops.darker(r, g), b).point(lambda v: 0 if v < 48 else min(255, round((v - 48) * 255 / 160)))
    if kind in DROP_BAR:
        # rows from the bottom up: the bar, then an empty gap, then the square; I cut at the gap
        w, h = m.size
        px = m.load()
        filled = [any(px[x, y] > 128 for x in range(w)) for y in range(h)]
        y = h - 1
        while y > 0 and not filled[y]: y -= 1
        while y > 0 and filled[y]: y -= 1
        if y > h // 2:
            m = m.crop((0, 0, w, y))
    box = m.point(lambda v: 255 if v > 24 else 0).getbbox()
    m = m.crop(box) if box else m
    if kind in TILT:
        m = m.resize((m.width * 4, m.height * 4), Image.BICUBIC).rotate(TILT[kind], Image.BICUBIC, expand=True)
        m = m.crop(m.point(lambda v: 255 if v > 24 else 0).getbbox())
    _shapes[kind] = m
    return m


def _fit(shape, height):
    """the shape scaled to fit a height x height box; when it grows, its edges are sharpened back afterwards"""
    w, h = shape.size
    k = height / max(w, h)
    size = (max(1, round(w * k)), max(1, round(h * k)))
    out = shape.resize(size, Image.BICUBIC if k > 1 else Image.LANCZOS)
    if k > 1.5:
        # a small source's pixel steps show when it grows a lot: I soften them first, then sharpen the edge
        out = out.filter(ImageFilter.GaussianBlur(k * 0.35)) if k > 3 else out
        out = out.point(lambda v: 0 if v < 64 else (255 if v > 191 else round((v - 64) * 255 / 127)))
    return out


def mask(kind, height):
    shape = game_shape(kind)
    if shape is not None:
        return _fit(shape, height)
    ss = 4
    scale = height * ss / GRID
    w = WIDTH[kind]
    img = Image.new('L', (max(1, round(w * scale)), round(GRID * scale)), 0)
    d = ImageDraw.Draw(img)

    class Scaled:
        def polygon(self, pts, fill): d.polygon([(x * scale, y * scale) for x, y in pts], fill=fill)
        def rectangle(self, box, fill):
            x0, y0, x1, y1 = box
            d.rectangle((x0 * scale, y0 * scale, x1 * scale - 1, y1 * scale - 1), fill=fill)
        def ellipse(self, box, fill):
            x0, y0, x1, y1 = box
            d.ellipse((x0 * scale, y0 * scale, x1 * scale, y1 * scale), fill=fill)
    DRAW[kind](Scaled())
    return img.resize((max(1, round(w * height / GRID)), height), Image.LANCZOS)


def aspect(kind):
    shape = game_shape(kind)
    if shape is not None:
        return shape.width / shape.height
    return WIDTH[kind] / GRID
