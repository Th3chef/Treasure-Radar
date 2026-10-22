"""Treasure Radar's textures: the sonar radar panel and its sweep, the ledger's pill, the check mark, the blip glow and
the characters for numbers. Every picture is white or drawn in its final color, 4x and scaled down for smooth edges; the addon tints them."""
import math
from PIL import Image, ImageDraw, ImageFont

import os as _os
FONT = _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), 'fonts', 'Poppins-Bold.ttf')   # SIL Open Font License
GREEN, LIGHT = (90, 255, 140), (150, 255, 180)
DISC, SWEEP, SWEEP_FRAMES = 512, 256, 64


def _letters(d, c, r, size, col):
    f = ImageFont.truetype(FONT, size)
    for ch, deg in zip('NESW', (0, 90, 180, 270)):
        a = math.radians(deg)
        x, y = c + math.sin(a) * r, c - math.cos(a) * r
        w = d.textlength(ch, font=f)
        d.text((x - w / 2, y - size * 0.62), ch, font=f, fill=col)


def sonar_disc(with_letters=True):
    """the round panel: a dark green face, rings at a quarter, half and three quarters of the range, a bright rim
    with ticks every 30 degrees, and N E S W (left off for Rotate With View: the addon places them)"""
    B = 4 * DISC
    img = Image.new('RGBA', (B, B), (0, 0, 0, 0)); d = ImageDraw.Draw(img); c = B / 2; r = c - 10
    d.ellipse((c - r, c - r, c + r, c + r), fill=(4, 18, 10, 185))
    for k in (0.25, 0.5, 0.75):
        rr = r * k
        d.ellipse((c - rr, c - rr, c + rr, c + rr), outline=GREEN + (60,), width=5)
    d.ellipse((c - r, c - r, c + r, c + r), outline=GREEN + (215,), width=13)
    for deg in range(0, 360, 30):
        a = math.radians(deg)
        # the long ticks mark N E S W; turning with my view they'd point the wrong way, so all short then
        L, W = (46, 10) if (deg % 90 == 0 and with_letters) else (24, 6)
        d.line((c + math.sin(a) * (r - 6), c - math.cos(a) * (r - 6), c + math.sin(a) * (r - 6 - L), c - math.cos(a) * (r - 6 - L)),
               fill=GREEN + (170,), width=W)
    if with_letters:
        _letters(d, c, r - 104, 84, LIGHT + (235,))
    return img.resize((DISC, DISC), Image.LANCZOS)


def sweep_frame(i, n=SWEEP_FRAMES):
    """the sweep at turn i of n (clockwise from north): a bright leading line and a fading green trail behind it"""
    B = 4 * SWEEP
    img = Image.new('RGBA', (B, B), (0, 0, 0, 0)); d = ImageDraw.Draw(img); c = B / 2; r = c - 30
    lead = 360 * i / n - 90               # PIL angles: 0 = east, clockwise; north = -90
    steps, span = 90, 60
    for s in range(steps):
        a1 = lead - s * span / steps
        d.pieslice((c - r, c - r, c + r, c + r), a1 - span / steps - 0.3, a1, fill=GREEN + (int(92 * (1 - s / steps) ** 1.6),))
    a = math.radians(lead)
    d.line((c, c, c + math.cos(a) * r, c + math.sin(a) * r), fill=LIGHT + (215,), width=12)
    return img.resize((SWEEP, SWEEP), Image.LANCZOS)


def pill(ring):
    """a ledger row's pill, 32 x 12 cells (256 x 96): the dark fill, or the outline (tinted the kind's color)"""
    W, H = 4 * 256, 4 * 96
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    t = 22
    if ring:
        d.rounded_rectangle((t / 2, t / 2, W - t / 2, H - t / 2), radius=(H - t) / 2, outline=(255, 255, 255, 255), width=t)
    else:
        d.rounded_rectangle((t / 2, t / 2, W - t / 2, H - t / 2), radius=(H - t) / 2, fill=(255, 255, 255, 255))
    return img.resize((256, 96), Image.LANCZOS)


def check():
    B = 4 * 64
    img = Image.new('RGBA', (B, B), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.line((30, 140, 100, 205, 228, 52), fill=(255, 255, 255, 255), width=40, joint='curve')
    return img.resize((64, 64), Image.LANCZOS)


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
GLYPH_SIZES = (14, 20, 28, 40)        # cap heights in px: the addon picks the one nearest the size it draws
GLYPH_PAD = 2


def glyph(ch, cap):
    """One character (one big texture shrunk 3-4x shimmers, so there are four sizes): one character in Poppins Bold at its own width, white, the cap height
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
