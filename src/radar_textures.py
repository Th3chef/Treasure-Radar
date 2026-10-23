"""Treasure Radar's textures: the sonar radar panel and its sweep, the ledger's pill, the check mark, the blip glow and
the characters for numbers. Every picture is white or drawn in its final color, 4x and scaled down for smooth edges; the addon tints them."""
import math
from PIL import Image, ImageDraw, ImageFont

import os as _os
FONT = _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), 'fonts', 'Poppins-Bold.ttf')   # SIL Open Font License
GREEN, LIGHT = (90, 255, 140), (150, 255, 180)
DISC, SWEEP, SWEEP_FRAMES = 512, 256, 64
DISC_TOP = 724                        # the biggest panel shipped (a 4K screen at Size Large draws it 820 px across)


def _letters(d, c, r, size, col):
    f = ImageFont.truetype(FONT, size)
    for ch, deg in zip('NESW', (0, 90, 180, 270)):
        a = math.radians(deg)
        x, y = c + math.sin(a) * r, c - math.cos(a) * r
        w = d.textlength(ch, font=f)
        d.text((x - w / 2, y - size * 0.62), ch, font=f, fill=col)


def sonar_disc(with_letters=True, master=False):
    """the round panel (0.6.0 Test 22, redrawn): a dark green face, darker toward the edge; faint cross hairs; rings at a
    quarter, half and three quarters of the range, each with a soft glow; a bright rim with a glow inside it; ticks every
    10 degrees (longer every 30, longest at N E S W); and N E S W (left off for Rotate With View: the addon places them).
    Drawn at 4x of DISC_TOP; master: that 4x picture, for shrinking straight to each size the radar draws it at."""
    import numpy as np
    B = 4 * DISC_TOP
    k = DISC_TOP / 512
    c = B / 2
    r = c - 10 * k
    yy, xx = np.mgrid[0:B, 0:B].astype(np.float32)
    dist = np.hypot(xx - c + 0.5, yy - c + 0.5) / r            # 0 at the middle, 1 at the rim
    inside = dist <= 1.0
    # the face: from (8,30,16) at 196 in the middle to (2,12,6) at 228 at the rim
    f = np.clip(dist, 0, 1) ** 1.6
    face = np.zeros((B, B, 4), np.float32)
    face[..., 0] = 8 + (2 - 8) * f
    face[..., 1] = 30 + (12 - 30) * f
    face[..., 2] = 16 + (6 - 16) * f
    face[..., 3] = np.where(inside, 196 + (228 - 196) * f, 0)
    img = Image.fromarray(face.clip(0, 255).astype(np.uint8), 'RGBA')

    def glow_line(draw_fn, color, alpha, width, glow_w, glow_a):
        """a line with a soft glow: a blurred wide copy under a crisp one"""
        from PIL import ImageFilter
        layer = Image.new('L', (B, B), 0)
        draw_fn(ImageDraw.Draw(layer), max(1, round(glow_w)))
        layer = layer.filter(ImageFilter.GaussianBlur(glow_w * 0.6))
        g = Image.new('RGBA', (B, B), color + (0,)); g.putalpha(layer.point(lambda p: round(p * glow_a / 255)))
        img.alpha_composite(g)
        core = Image.new('L', (B, B), 0)
        draw_fn(ImageDraw.Draw(core), max(1, round(width)))
        g = Image.new('RGBA', (B, B), color + (0,)); g.putalpha(core.point(lambda p: round(p * alpha / 255)))
        img.alpha_composite(g)

    # cross hairs
    for deg in (0, 90):
        a = math.radians(deg)
        glow_line(lambda d, w, a=a: d.line((c - math.sin(a) * r, c - math.cos(a) * r, c + math.sin(a) * r, c + math.cos(a) * r), fill=255, width=w),
                  GREEN, 26, 3 * k, 0, 0)
    for f2 in (0.25, 0.5, 0.75):
        rr = r * f2
        glow_line(lambda d, w, rr=rr: d.ellipse((c - rr, c - rr, c + rr, c + rr), outline=255, width=w), GREEN, 60, 4 * k, 14 * k, 40)
    # the rim, with a glow inside and out
    glow_line(lambda d, w: d.ellipse((c - r, c - r, c + r, c + r), outline=255, width=w), GREEN, 150, 9 * k, 30 * k, 120)
    for deg in range(0, 360, 10):
        a = math.radians(deg)
        big = deg % 90 == 0 and with_letters
        L, W, al = ((46, 10, 140) if big else (26, 6, 115) if deg % 30 == 0 else (12, 4, 80))
        L, W, e = L * k, max(1, round(W * k)), 10 * k
        ImageDraw.Draw(img).line((c + math.sin(a) * (r - e), c - math.cos(a) * (r - e), c + math.sin(a) * (r - e - L), c - math.cos(a) * (r - e - L)),
                                 fill=GREEN + (al,), width=W)
    if with_letters:
        _letters(ImageDraw.Draw(img), c, r - 108 * k, round(84 * k), LIGHT + (185,))
    return img if master else img.resize((DISC, DISC), Image.LANCZOS)


def sweep_frame(i, n=SWEEP_FRAMES):
    """the sweep at turn i of n (clockwise from north): a bright leading line with a glow, and a green trail behind it
    that fades smoothly (0.6.0 Test 22: finer steps and a softer falloff)"""
    from PIL import ImageFilter
    B = 4 * SWEEP
    img = Image.new('RGBA', (B, B), (0, 0, 0, 0)); d = ImageDraw.Draw(img); c = B / 2; r = c - 30
    lead = 360 * i / n - 90               # PIL angles: 0 = east, clockwise; north = -90
    steps, span = 240, 70
    for s_ in range(steps):
        a1 = lead - s_ * span / steps
        f = 1 - s_ / steps
        d.pieslice((c - r, c - r, c + r, c + r), a1 - span / steps - 0.2, a1, fill=GREEN + (int(78 * f ** 2.2),))
    a = math.radians(lead)
    line = Image.new('L', (B, B), 0)
    ImageDraw.Draw(line).line((c, c, c + math.cos(a) * r, c + math.sin(a) * r), fill=255, width=26)
    glow = Image.new('RGBA', (B, B), GREEN + (0,)); glow.putalpha(line.filter(ImageFilter.GaussianBlur(10)).point(lambda p: round(p * 0.55)))
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img)
    d.line((c, c, c + math.cos(a) * r, c + math.sin(a) * r), fill=LIGHT + (175,), width=10)
    return img.resize((SWEEP, SWEEP), Image.LANCZOS)


def pill(ring, master=False):
    """a ledger row's pill, 32 x 12 cells (256 x 96): the dark fill, or the outline (tinted the kind's color)"""
    W, H = 4 * 256, 4 * 96
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    t = 22
    if ring:
        d.rounded_rectangle((t / 2, t / 2, W - t / 2, H - t / 2), radius=(H - t) / 2, outline=(255, 255, 255, 255), width=t)
    else:
        d.rounded_rectangle((t / 2, t / 2, W - t / 2, H - t / 2), radius=(H - t) / 2, fill=(255, 255, 255, 255))
    return img if master else img.resize((256, 96), Image.LANCZOS)


def tile(master=False):
    """(0.6.0 Test 23) a ledger tile, 15 x 17 cells (120 x 136): a rounded square, white (tinted dark)"""
    W, H = 4 * 120, 4 * 136
    img = Image.new('RGBA', (W, H), (255, 255, 255, 0))
    ImageDraw.Draw(img).rounded_rectangle((2, 2, W - 3, H - 3), radius=40, fill=(255, 255, 255, 255))
    return img if master else img.resize((120, 136), Image.LANCZOS)


def check(master=False):
    B = 4 * 64
    img = Image.new('RGBA', (B, B), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.line((30, 140, 100, 205, 228, 52), fill=(255, 255, 255, 255), width=40, joint='curve')
    return img if master else img.resize((64, 64), Image.LANCZOS)


def glow():
    """a soft round glow, white in the middle fading out (the blip as the sweep passes a pickup)"""
    S = 64
    img = Image.new('RGBA', (S, S), (255, 255, 255, 0))
    px = img.load()
    for y in range(S):
        for x in range(S):
            dd = math.hypot(x - S / 2 + 0.5, y - S / 2 + 0.5) / (S / 2)
            px[x, y] = (255, 255, 255, int(255 * max(0, 1 - dd) ** 1.8))
    return img


GLYPHS = '0123456789MKX.NESW'
GLYPH_SIZES = (7, 10, 14, 20, 28, 40)  # cap heights in px: the addon picks the one nearest the size it draws (7 and 10 since 0.6.0, for the small counts at 1080p)
GLYPH_PAD = 2


def glyph(ch, cap):
    """One character (one big texture shrunk 3-4x shimmers, so there are six sizes): one character in Poppins Bold at its own width, white, the cap height
    `cap` px with GLYPH_PAD px of clear edge. Returns the image and its width over its cap height."""
    S = 4
    f = ImageFont.truetype(FONT, 400)
    probe = ImageDraw.Draw(Image.new('L', (1, 1)))
    ref = probe.textbbox((0, 0), '0', font=f)
    capb = ref[3] - ref[1]
    l, t, r, b = probe.textbbox((0, 0), ch, font=f)
    k = cap * S / capb
    w = max(1, round((r - l) * k))
    W, H = w + 2 * GLYPH_PAD * S, cap * S + 2 * GLYPH_PAD * S
    big = Image.new('L', (r - l + 40, capb + 40), 0)
    ImageDraw.Draw(big).text((20 - l, 20 - ref[1]), ch, font=f, fill=255)
    big = big.resize((round(big.width * k), round(big.height * k)), Image.LANCZOS)
    out = Image.new('L', (W, H), 0)
    out.paste(big, (GLYPH_PAD * S - round(20 * k), GLYPH_PAD * S - round(20 * k)))
    tw, th = max(1, round(W / S)), cap + 2 * GLYPH_PAD
    img = Image.new('RGBA', (W, H), (255, 255, 255, 0)); img.putalpha(out)
    img = img.resize((tw, th), Image.LANCZOS)
    return img, (tw - 2 * GLYPH_PAD) / cap


# ------------------------------------------------------------------ the UI world's copies
# Below native Render Scale the radar is drawn in the game's UI world, which shows colors differently from the game's
# own world (native): ui_copy (at the end) makes each texture's copy for it from the measured curves (ui_calib.py).


# ------------------------------------------------------------------ the color swatches (test and Tester builds)
# 0.6.0 Test 21: below native the radar came out duller than at native (screenshots: a fabricator (190,20,30) shows as
# (255,0,0) at native but (147,16,9) at Ultra Quality). To match the two I measure both ways of drawing: a strip of
# known colors drawn the radar's way, in both, screenshotted. 16 patches a row, 16 px each: grays, reds, greens and
# blues opaque from 0 to 255, then white and the radar's green with alpha from 0 to 255.
SWATCH = 16


def swatches():
    img = Image.new('RGBA', (16 * SWATCH, 6 * SWATCH), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for i in range(16):
        v = i * 17
        rows = [(v, v, v, 255), (v, 0, 0, 255), (0, v, 0, 255), (0, 0, v, 255), (255, 255, 255, v), GREEN + (v,)]
        for r, c in enumerate(rows):
            d.rectangle((i * SWATCH, r * SWATCH, (i + 1) * SWATCH - 1, (r + 1) * SWATCH - 1), fill=c)
    return img


# ------------------------------------------------------------------ the size ladders
# The game's UI material has no mipmaps: a texture drawn at half its size or less skips texels and its edges come out
# as stair steps (Test 14 looked "kinda pixely"). So every picture the radar shrinks ships pre-shrunk at each step of
# 1/sqrt(2) from its biggest size, and the loader draws the one nearest the drawn size (chef.texture_sizes).
LADDER = (1, 0.7071, 0.5, 0.3536, 0.25, 0.1768)


def ladder(w, h, steps=LADDER, least=8):
    """the sizes (width, height) from (w, h) down, the biggest first, none under `least` px tall"""
    out = []
    for f in steps:
        s = (max(1, round(w * f / 2) * 2), max(1, round(h * f / 2) * 2))
        if s[1] < least or (out and s == out[-1]):
            break
        out.append(s)
    return out


def ui_copy(img):
    """the UI world's copy of a texture drawn in its final colors (tinted white): since 0.6.0 Test 24 from the measured
    curves of both ways of drawing (ui_calib.py), so below native it looks as it does at native"""
    import numpy as np, ui_calib
    arr = np.asarray(img.convert('RGBA')).astype(np.float64)
    out = ui_calib.ui_rgba(arr)
    return Image.fromarray((out + 0.5).astype(np.uint8), 'RGBA')
