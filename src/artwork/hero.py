"""Treasure Radar release art: the hero scene (the sonar radar with its sweep, the pickups lighting up and the pill
ledger, over a blurred shot of the game). hero(W, H, cx, cy, r) -> RGBA image; the text is added by cards.py."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import icon_textures, radar_textures

FONT = os.path.join(os.path.dirname(HERE), 'fonts', 'Poppins-Bold.ttf')   # SIL Open Font License
RGB = {'credit': (115, 233, 242), 'medal': (255, 221, 31), 'common': (95, 220, 60), 'rare': (255, 151, 64),
       'super': (255, 114, 211), 'requisition': (244, 247, 56), 'ammo': (255, 234, 128), 'grenade': (135, 170, 45),
       'stim': (60, 140, 255)}
LIGHT = (150, 255, 180)
SWEEP_AT = 52                       # degrees clockwise from north where the sweep's line is in the pictures

# pickups on the radar: (east, north) as a fraction of the radius, kind, pile count
PICKUPS = [(0.30, 0.58, 'medal', 1), (0.62, 0.30, 'credit', 1), (-0.48, 0.40, 'common', 3), (0.18, -0.36, 'rare', 1),
           (-0.30, -0.52, 'super', 1), (-0.70, -0.18, 'requisition', 1), (0.52, -0.55, 'medal', 2), (-0.10, 0.22, 'ammo', 4),
           (0.40, 0.05, 'grenade', 2), (-0.36, 0.05, 'stim', 1), (0.12, 0.74, 'common', 1), (0.66, -0.10, 'ammo', 1),
           (0.90, 0.40, 'rare', 1), (-0.84, 0.48, 'medal', 1)]
LEDGER = [('credit', 1), ('medal', 4), ('common', 4), ('rare', 2), ('super', 0), ('requisition', 1), ('ammo', 5),
          ('grenade', 2), ('stim', 1)]


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
    ic = icon_textures.icon_image(kid, RGB[kid]).convert('RGBA').resize((size, size), Image.LANCZOS)
    if alpha < 1:
        ic.putalpha(ic.getchannel('A').point(lambda v: int(v * alpha)))
    return ic


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
    for x, y, kid, cnt in sorted(PICKUPS, key=lambda p: p[2] in ('ammo', 'grenade', 'stim'), reverse=True):
        px, py = c + x * inner, c - y * inner
        since = (sweep - math.atan2(x, y)) % (2 * math.pi)
        pulse = math.exp(-since / 0.5)
        sz = int((h * 0.78 if kid in ('ammo', 'grenade', 'stim') else h) * (1 + 0.12 * pulse))
        if pulse > 0.08:
            g = int(sz * 1.2)
            halo = Image.new('RGBA', (4 * g, 4 * g), (0, 0, 0, 0))
            ImageDraw.Draw(halo).ellipse((g, g, 3 * g, 3 * g), fill=LIGHT + (int(140 * pulse),))
            out.alpha_composite(halo.filter(ImageFilter.GaussianBlur(g / 2.2)), (int(px - 2 * g), int(py - 2 * g)))
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
    """the ledger's pills as drawn in game, `scale` px per game cell"""
    lh, gap, lw = 12 * scale, 2 * scale, 32 * scale
    W, H = int(lw + 4), int(len(LEDGER) * (lh + gap) - gap + 4)
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT, int(8.6 * scale))
    for i, (kid, left) in enumerate(LEDGER):
        y0 = 2 + i * (lh + gap)
        done = left == 0
        d.rounded_rectangle((2, y0, 2 + lw, y0 + lh), radius=lh / 2, fill=(8, 10, 12, 120 if done else 205),
                            outline=(80, 80, 80, 170) if done else RGB[kid] + (235,), width=max(2, int(scale * 0.75)))
        ic = icon(kid, int(9.5 * scale), 0.4 if done else 1)
        img.alpha_composite(ic, (int(2 + 2.5 * scale), int(y0 + (lh - 9.5 * scale) / 2)))
        if done:
            cs = 7.5 * scale
            x1, y1 = 2 + lw - 4.5 * scale - cs, y0 + (lh - cs) / 2
            d.line((x1, y1 + cs * 0.55, x1 + cs * 0.38, y1 + cs * 0.9, x1 + cs, y1 + cs * 0.15), fill=(140, 230, 140, 255),
                   width=max(2, int(scale * 1.1)), joint='curve')
        else:
            t = str(left)
            d.text((2 + lw - 5 * scale, y0 + lh / 2), t, font=f, fill=(245, 245, 245, 255), anchor='rm')
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
