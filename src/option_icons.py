"""Treasure Radar's Arsenal option images (256x256 PNGs, Arsenal shows one next to each option and sub-option).
  option_icons.py <out dir> [kind ids...]   writes <out dir>/<name>.png and prints the names
Same look as the thumbnail: the radar disc, the pickup icons, yellow for words."""
import sys, os, math, ast, re
from PIL import Image, ImageDraw, ImageFont
import icon_textures

HERE = os.path.dirname(os.path.abspath(__file__))
TM_COLORS = ast.literal_eval(re.search(r'^TM_COLORS = (\{.*?\})$', open(os.path.join(HERE, 'build.py')).read(), re.S | re.M).group(1))
S = 256
BG, YEL, MAG = (14, 16, 18, 255), (255, 221, 31, 255), (255, 0, 255, 255)
import os as _os
FONT = _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), 'fonts', 'Poppins-Bold.ttf')   # SIL Open Font License
import radar_textures   # the sonar panel, as in the game
_disc, _plain = radar_textures.sonar_disc().convert('RGBA'), radar_textures.sonar_disc(False).convert('RGBA')


def font(n): return ImageFont.truetype(FONT, n)


def canvas():
    img = Image.new('RGBA', (S, S), BG)
    ImageDraw.Draw(img).rectangle((3, 3, S - 4, S - 4), outline=(60, 62, 64, 255), width=3)
    return img


def disc(img, cx, cy, r, alpha=1.0, plain=False):
    d = (_plain if plain else _disc).resize((2 * r, 2 * r), Image.LANCZOS)
    if alpha < 1:
        a = d.getchannel('A').point(lambda v: round(v * alpha)); d.putalpha(a)
    img.alpha_composite(d, (cx - r, cy - r))


def icon(img, kid, cx, cy, sz):
    ic = icon_textures.icon_image(kid, TM_COLORS[kid]).convert('RGBA').resize((sz, sz), Image.LANCZOS)
    img.alpha_composite(ic, (int(cx - sz / 2), int(cy - sz / 2)))


def me(img, cx, cy, s=1.0, up=(0, -1)):
    d = ImageDraw.Draw(img)
    k = max(2, round(4 * s))
    d.rectangle((cx - k - 2, cy - k - 2, cx + k + 2, cy + k + 2), fill=(12, 12, 14, 255))
    d.rectangle((cx - k, cy - k, cx + k, cy + k), fill=(255, 255, 255, 255))
    for i in range(1, 5):
        x, y = cx + up[0] * i * 5 * s, cy + up[1] * i * 5 * s
        d.rectangle((x - 2 * s, y - 2 * s, x + 2 * s, y + 2 * s), fill=(255, 255, 255, 255))


def label(img, text, y, size=40, color=YEL):
    d = ImageDraw.Draw(img)
    f = font(size)
    w = d.textlength(text, font=f)
    d.text(((S - w) / 2 + 2, y + 2), text, font=f, fill=(0, 0, 0, 255))
    d.text(((S - w) / 2, y), text, font=f, fill=color)


def scatter(img, cx, cy, r):
    for kid, x, y in (('medal', 0.42, 0.45), ('credit', -0.55, 0.2), ('super', 0.25, -0.55), ('rare', -0.35, -0.35), ('common', 0.6, -0.1)):
        icon(img, kid, cx + x * r, cy - y * r, max(16, round(r * 0.3)))


def checker(img, box, step=16):
    d = ImageDraw.Draw(img)
    x0, y0, x1, y1 = box
    for y in range(y0, y1, step):
        for x in range(x0, x1, step):
            if ((x - x0) // step + (y - y0) // step) % 2 == 0:
                d.rectangle((x, y, min(x + step, x1) - 1, min(y + step, y1) - 1), fill=(70, 74, 78, 255))


def make_core():
    img = canvas(); disc(img, 128, 128, 112); scatter(img, 128, 128, 112); me(img, 128, 128, 1.4); return img


def make_ledger():
    img = canvas()
    d = ImageDraw.Draw(img)
    f = font(34)
    for i, (kid, n) in enumerate((('credit', None), ('medal', '5'), ('common', '11'), ('rare', '4'))):
        y0 = 26 + i * 54
        col = TM_COLORS[kid] if n else (80, 80, 80)
        d.rounded_rectangle((40, y0, 216, y0 + 46), radius=23, fill=(8, 10, 12, 255), outline=col + (255,), width=4)
        ic = icon_textures.icon_image(kid, TM_COLORS[kid]).convert('RGBA').resize((36, 36), Image.LANCZOS)
        if not n: ic.putalpha(ic.getchannel('A').point(lambda v: v * 4 // 10))
        img.alpha_composite(ic, (54, y0 + 5))
        if n:
            w = d.textlength(n, font=f); d.text((198 - w, y0 + 1), n, font=f, fill=(245, 245, 245, 255))
        else:
            d.line((168, y0 + 25, 180, y0 + 36, 200, y0 + 12), fill=(140, 230, 140, 255), width=6, joint='curve')
    return img


def make_opacity(pct=None):
    img = canvas()
    checker(img, (8, 8, S - 8, S - 8))
    a = 0.5 if pct is None else pct / 100
    disc(img, 128, 128, 104, a); scatter(img, 128, 128, 104); me(img, 128, 128, 1.2)
    label(img, 'OPACITY' if pct is None else f'{pct}%', 196 if pct is None else 188, 36 if pct is None else 48)
    return img


def make_size(k=None):
    img = canvas()
    if k is None:
        for r, a in ((110, 0.45), (84, 0.7), (62, 1.0)):
            disc(img, 246 - r - 8, 246 - r - 8, r, a)
        me(img, 246 - 62 - 8, 246 - 62 - 8, 1.0)
        label(img, 'SIZE', 12, 40)
    else:
        r = {'small': 66, 'medium': 84, 'large': 110}[k]
        disc(img, 246 - r - 8, 246 - r - 8, r); me(img, 246 - r - 8, 246 - r - 8, r / 84)
        label(img, k.upper(), 12, 36)
    return img


def make_rotate():
    img = canvas()
    disc(img, 128, 128, 100, plain=True)
    d = ImageDraw.Draw(img)
    ang = math.radians(35)      # north is off to the side: my view is up
    nx, ny = 128 + math.sin(ang) * 80, 128 - math.cos(ang) * 80
    d.text((nx - 11, ny - 18), 'N', font=font(30), fill=(235, 230, 215, 255))
    # the turning arrow round the outside
    d.arc((14, 14, 242, 242), 200, 320, fill=YEL, width=9)
    tip = math.radians(320)
    tx, ty = 128 + math.cos(tip) * 114, 128 + math.sin(tip) * 114
    d.polygon([(tx + 16, ty - 2), (tx - 8, ty - 16), (tx - 2, ty + 14)], fill=YEL)
    icon(img, 'medal', 128 + 40, 128 + 30, 34); icon(img, 'credit', 128 - 50, 128 - 10, 32)
    me(img, 128, 128, 1.3)
    return img


def make_markers(m=None):
    img = canvas()
    d = ImageDraw.Draw(img)
    # the ground going away from me
    for i, y in enumerate((150, 172, 200, 236)):
        d.line((10, y, S - 10, y), fill=(55, 58, 60, 255), width=2)
    for x in (-300, -120, 60, 240, 420):
        d.line((128, 120, x, 256), fill=(55, 58, 60, 255), width=2)
    for kid, x, y, sz, t in (('medal', 70, 128, 46, '18M'), ('credit', 180, 112, 34, '31M'), ('ammo', 150, 186, 54, '6M')):
        icon(img, kid, x, y, sz)
        f = font(max(16, sz // 2))
        w = d.textlength(t, font=f)
        d.text((x - w / 2, y - sz / 2 - f.size - 2), t, font=f, fill=(235, 235, 235, 255))
    label(img, 'MARKERS' if m is None else f'{m} M', 18, 38 if m is None else 48)
    return img


def make_calibrate():
    img = canvas(); disc(img, 128, 128, 92)
    d = ImageDraw.Draw(img)
    for i in range(48):
        a = i / 48 * 2 * math.pi
        x, y = 128 + math.cos(a) * 112, 128 + math.sin(a) * 112
        d.rectangle((x - 2, y - 2, x + 2, y + 2), fill=MAG)
    d.rectangle((108, 126, 148, 130), fill=MAG); d.rectangle((126, 108, 130, 148), fill=MAG)
    return img


def make_range(m=None):
    img = canvas(); disc(img, 128, 128, 112); me(img, 128, 128, 1.2)
    d = ImageDraw.Draw(img)
    d.line((136, 128, 230, 128), fill=YEL, width=6)
    d.polygon([(238, 128), (222, 118), (222, 138)], fill=YEL)
    label(img, 'RANGE' if m is None else f'{m} M', 150, 40 if m is None else 44)
    return img


def make_kind(kid):
    img = canvas(); icon(img, kid, 128, 128, 176); return img


def all_images(kinds):
    out = {'core': make_core(), 'ledger': make_ledger(), 'opacity': make_opacity(), 'size': make_size(), 'rotate': make_rotate(),
           'markers': make_markers(), 'calibrate': make_calibrate(), 'range': make_range()}
    for pct in (100, 75, 50, 25, 0): out[f'opacity_{pct}'] = make_opacity(pct)
    for k in ('small', 'medium', 'large'): out[f'size_{k}'] = make_size(k)
    for m in (25, 50, 100): out[f'markers_{m}'] = make_markers(m)
    for m in (75, 100, 150, 200, 250, 300): out[f'range_{m}'] = make_range(m)
    for k in kinds: out[k] = make_kind(k)
    return out


if __name__ == '__main__':
    dest = sys.argv[1]
    os.makedirs(dest, exist_ok=True)
    for name, img in all_images(sys.argv[2:]).items():
        img.convert('RGB').save(os.path.join(dest, name + '.png'))
        print(name)
