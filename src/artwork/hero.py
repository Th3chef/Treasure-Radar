"""Treasure Radar release art: the hero scene (the sonar radar with its sweep, the pickups, enemy structures and
weapons lighting up, and the ledger's tiles, over a blurred shot of the game). hero(W, H, cx, cy, r) -> RGBA image; the
text is added by cards.py. The weapon silhouettes come from weapon_icons/ (the game's own marker icons, see
weapon_textures.py); a missing one falls back to my generic shape."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import icon_textures, radar_textures, weapon_textures

FONT = os.path.join(os.path.dirname(HERE), 'fonts', 'Poppins-Bold.ttf')   # SIL Open Font License
RGB = {'credit': (115, 233, 242), 'medal': (255, 221, 31), 'common': (95, 220, 60), 'rare': (255, 151, 64),
       'super': (255, 114, 211), 'requisition': (244, 247, 56), 'ammo': (255, 234, 128), 'grenade': (135, 170, 45),
       'stim': (60, 140, 255), 'fabricator': (190, 20, 30), 'bulkfab': (190, 20, 30), 'ilship': (190, 20, 30),
       'bughole': (190, 20, 30)}
SUPPLY = ('ammo', 'grenade', 'stim')
STRUCT = ('fabricator', 'bulkfab', 'ilship', 'bughole')
LIGHT = (150, 255, 180)
SWEEP_AT = 52                       # degrees clockwise from north where the sweep's line is in the pictures

# on the radar: (east, north) as a fraction of the radius, kind (or 'w:<weapon unit id>'), pile count
PICKUPS = [(0.30, 0.58, 'medal', 1), (0.62, 0.30, 'credit', 1), (-0.48, 0.40, 'common', 3), (0.18, -0.36, 'rare', 1),
           (-0.30, -0.52, 'super', 1), (-0.72, -0.12, 'requisition', 1), (0.48, -0.58, 'medal', 2), (-0.10, 0.22, 'ammo', 4),
           (0.40, 0.04, 'grenade', 2), (-0.34, 0.04, 'stim', 1), (0.10, 0.76, 'common', 1),
           (-0.58, 0.70, 'fabricator', 1), (0.82, -0.30, 'bughole', 2), (-0.80, -0.48, 'ilship', 1),
           (0.70, 0.62, 'w:2e9d0bdc48b09e60', 1), (-0.04, -0.66, 'w:a6a735accb4a327f', 1)]
# the ledger's tile rows, top to bottom (as in game): structures, then credits, medals and slips, samples, supplies
LEDGER_ROWS = [[('fabricator', 1), ('ilship', 1), ('bughole', 2)], [('credit', 1), ('medal', 4), ('requisition', 1)],
               [('common', 4), ('rare', 2), ('super', 0)], [('ammo', 5), ('grenade', 2), ('stim', 1)]]
WEAPON_ICONS = os.path.join(os.path.dirname(HERE), 'weapon_icons')


def background(W, H):
    """the game, blurred and darkened toward the edges, so the radar and the text stand out"""
    im = Image.open(os.path.join(HERE, 'scene.jpg')).convert('RGB')
    k = max(W / im.width, H / im.height)
    im = im.resize((math.ceil(im.width * k), math.ceil(im.height * k)), Image.LANCZOS)
    x0, y0 = (im.width - W) // 2, (im.height - H) // 2
    im = im.crop((x0, y0, x0 + W, y0 + H)).filter(ImageFilter.GaussianBlur(max(W, H) / 180))
    im = ImageEnhance.Brightness(im).enhance(0.62)
    im = ImageEnhance.Color(im).enhance(0.85).convert('RGBA')
    vig = Image.new('L', (W, H), 0)
    ImageDraw.Draw(vig).ellipse((-W * 0.25, -H * 0.3, W * 1.25, H * 1.3), fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(min(W, H) / 5))
    dark = Image.new('RGBA', (W, H), (0, 0, 0, 255)); dark.putalpha(vig.point(lambda p: int((255 - p) * 0.75)))
    im.alpha_composite(dark)
    return im


def icon(kid, size, alpha=1.0):
    ic = icon_textures.icon_master(kid, RGB[kid]).convert('RGBA').resize((size, size), Image.LANCZOS)
    if alpha < 1:
        ic.putalpha(ic.getchannel('A').point(lambda v: int(v * alpha)))
    return ic


_weapons = {}


def weapon(uid, h, alpha=1.0):
    """a weapon's silhouette, h px tall (its texture is 128 x 48, white with the dark outline)"""
    if uid not in _weapons:
        path = os.path.join(WEAPON_ICONS, uid + '.png')
        mask = weapon_textures.silhouette(path) if os.path.exists(path) else None
        _weapons[uid] = weapon_textures.texture(mask if mask is not None else weapon_textures.generic(), master=True)
    w = int(h * weapon_textures.W / weapon_textures.H)
    im = _weapons[uid].resize((w, h), Image.LANCZOS)
    if alpha < 1:
        im.putalpha(im.getchannel('A').point(lambda v: int(v * alpha)))
    return im


def text(img, xy, s, size, rgb, anchor='lm'):
    f = ImageFont.truetype(FONT, int(size))
    m = Image.new('L', img.size, 0)
    ImageDraw.Draw(m).text(xy, s, font=f, fill=255, anchor=anchor)
    edge = m.filter(ImageFilter.MaxFilter(2 * max(1, int(size) // 9) + 1)).filter(ImageFilter.GaussianBlur(size / 40))
    dark = Image.new('RGBA', img.size, (8, 8, 8, 255)); dark.putalpha(edge.point(lambda p: int(p * 0.85)))
    img.alpha_composite(dark)
    col = Image.new('RGBA', img.size, rgb + (255,)); col.putalpha(m)
    img.alpha_composite(col)


def radar(r):
    """the radar as drawn in game: the sonar panel, the sweep, the pickups (brighter just behind the sweep) and me"""
    pad = r // 8
    S = 2 * (r + pad)
    out = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sh = Image.new('L', (S, S), 0)
    ImageDraw.Draw(sh).ellipse((pad, pad + r * 0.04, pad + 2 * r, pad + 2 * r + r * 0.04), fill=210)
    shadow = Image.new('RGBA', (S, S), (0, 0, 0, 255)); shadow.putalpha(sh.filter(ImageFilter.GaussianBlur(r / 18)))
    out.alpha_composite(shadow)
    disc = radar_textures.sonar_disc().convert('RGBA')
    # the panel a bit more solid than in game, so it reads at thumbnail size
    disc.putalpha(disc.getchannel('A').point(lambda v: min(255, int(v * 1.25))))
    out.alpha_composite(disc.resize((2 * r, 2 * r), Image.LANCZOS), (pad, pad))
    n = radar_textures.SWEEP_FRAMES
    sw = radar_textures.sweep_frame(round(SWEEP_AT / 360 * n) % n).resize((2 * r, 2 * r), Image.LANCZOS)
    out.alpha_composite(sw, (pad, pad))
    c = pad + r
    inner = r * 0.92
    h = max(14, int(r * 0.15))
    sweep = math.radians(SWEEP_AT)
    # drawn as in game: supplies at the bottom, then structures, the loot, and the weapons on top
    order = lambda p: 0 if p[2] in SUPPLY else (1 if p[2] in STRUCT else (3 if p[2][:2] == 'w:' else 2))
    for x, y, kid, cnt in sorted(PICKUPS, key=order):
        px, py = c + x * inner, c - y * inner
        since = (sweep - math.atan2(x, y)) % (2 * math.pi)
        pulse = math.exp(-since / 0.5)
        d0 = math.hypot(x, y)
        # every kind about the same size: bigger near me, smaller toward the edge (1.3x down to 0.7x in game)
        sz = int(h * (1.18 - 0.36 * d0) * (1 + 0.12 * pulse))
        if pulse > 0.08:
            g = int(sz * 1.2)
            halo = Image.new('RGBA', (4 * g, 4 * g), (0, 0, 0, 0))
            ImageDraw.Draw(halo).ellipse((g, g, 3 * g, 3 * g), fill=LIGHT + (int(140 * pulse),))
            out.alpha_composite(halo.filter(ImageFilter.GaussianBlur(g / 2.2)), (int(px - 2 * g), int(py - 2 * g)))
        if kid[:2] == 'w:':
            wim = weapon(kid[2:], int(sz * 0.75), 0.75 + 0.25 * pulse)
            out.alpha_composite(wim, (int(px - wim.width / 2), int(py - wim.height / 2)))
            continue
        out.alpha_composite(icon(kid, sz, 0.75 + 0.25 * pulse), (int(px - sz / 2), int(py - sz / 2)))
        if cnt > 1:
            text(out, (px + sz * 0.62, py + sz * 0.05), str(cnt), sz * 0.58, RGB[kid])
    # me: the dotted heading line and the square, sonar green
    d = ImageDraw.Draw(out)
    s = max(2, r / 120)
    d.rectangle((c - 4 * s, c - 4 * s, c + 4 * s, c + 4 * s), fill=(12, 12, 14, 255))
    d.rectangle((c - 3 * s, c - 3 * s, c + 3 * s, c + 3 * s), fill=LIGHT + (255,))
    for i in range(1, 6):
        d.rectangle((c - s, c - 2 * i * s - 4 * s, c + s, c - 2 * i * s - 2 * s), fill=LIGHT + (255,))
    return out, pad


def ledger(scale):
    """the ledger's tiles as drawn in game, `scale` px per game cell: each kind a small square with a line in its color
    along the top, its icon and how many are left; a cleared kind dims, with a gray line and a check mark"""
    TW, TH, GAP, ROW, ISZ = 15 * scale, 17 * scale, 1.5 * scale, 3 * scale, 8.5 * scale
    n = max(len(r) for r in LEDGER_ROWS)
    W = int(n * TW + (n - 1) * GAP + 4)
    H = int(len(LEDGER_ROWS) * TH + (len(LEDGER_ROWS) - 1) * ROW + 4)
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT, int(5.6 * scale))
    line = max(2, int(scale * 0.9 + 0.5))
    for ri, row in enumerate(LEDGER_ROWS):
        y0 = 2 + ri * (TH + ROW)
        x0 = W - 2 - len(row) * TW - (len(row) - 1) * GAP          # right-aligned beside the radar
        for kid, left in row:
            done = left == 0
            d.rounded_rectangle((x0, y0, x0 + TW, y0 + TH), radius=2.2 * scale, fill=(8, 12, 10, 130 if done else 205))
            d.rectangle((x0 + 1.2 * scale, y0, x0 + TW - 1.2 * scale, y0 + line - 1),
                        fill=(90, 90, 90, 230) if done else RGB[kid] + (230,))
            ic = icon(kid, int(ISZ), 0.4 if done else 1)
            img.alpha_composite(ic, (int(x0 + (TW - ISZ) / 2), int(y0 + 1.9 * scale)))
            cy = y0 + TH - 3.5 * scale
            if done:
                cs = 6 * scale
                x1, y1 = x0 + (TW - cs) / 2, cy - cs * 0.5
                d.line((x1, y1 + cs * 0.55, x1 + cs * 0.38, y1 + cs * 0.9, x1 + cs, y1 + cs * 0.15), fill=(140, 230, 140, 255),
                       width=max(2, int(scale * 1.1)), joint='curve')
            else:
                d.text((x0 + TW / 2, cy), str(left), font=f, fill=(245, 245, 245, 255), anchor='mm')
            x0 += TW + GAP
    return img


def hero(W, H, cx, cy, r, show_ledger=True):
    img = background(W, H)
    rad, pad = radar(r)
    img.alpha_composite(rad, (int(cx - r - pad), int(cy - r - pad)))
    if show_ledger:
        s = r / 205 * 2.25 * 1.15        # as in game: 2.25 px a cell at radius 205 (a touch bigger here)
        L = ledger(s)
        lx, ly = int(cx - r - 6 * s - L.width), int(cy + r - L.height)
        sh = Image.new('RGBA', L.size, (0, 0, 0, 0)); sh.putalpha(L.getchannel('A').point(lambda v: v // 2))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(4)), (lx + 3, ly + 4))
        img.alpha_composite(L, (lx, ly))
    return img


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'hero_test.png')
    hero(1600, 1000, 1000, 500, 380).save(out)
    print(out)
