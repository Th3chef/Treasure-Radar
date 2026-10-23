"""Treasure Radar's weapon silhouettes: the game's own HUD marker icon for each support weapon (the one it shows when a
dropped weapon is pinged), cut down to the weapon itself and given the same dark outline as my pickup icons.

The icons are game files, so they aren't in this repository: `weapon_icons/<unit id>.png` comes from the player's game
(tools/extract_weapon_icons.py) or from the release zip. The red channel is the weapon (green holds an ammo symbol);
some have a small backpack badge in the top-right corner, which is dropped: only the weapon's own shape is kept.
A weapon with no game icon (the SG-88) gets my generic one."""
import os
from PIL import Image, ImageDraw, ImageFilter

W, H = 128, 48                 # every weapon texture (wide: the silhouettes are 2.5-4 times as wide as they are tall)
COLOR = (235, 235, 235)        # the weapons' color on the radar: the game's own markers are white

# The support weapons and expendables that can lie on the ground: unit id -> name (the HD2 Codex, all confirmed by the
# game's entity data). The 28 with a game icon, then the SG-88 (no icon in the game).
WEAPONS = {
    '6cfcc7f8801a0266': '40-K Meltagun', 'a8cffb316f0b5c5f': 'AC-8 Autocannon', '89c5493e08ca4207': 'APW-1 Anti-Materiel Rifle',
    '96de9cd50f7306e6': 'ARC-3 Arc Thrower', '78a8185f63a70795': 'B/FLAM-80 Cremator', '80932fa0ed6901d3': 'EAT-17 Expendable Anti-Tank',
    '7617642765ac38c7': 'EAT-411 Leveller', 'b2b5e0d185605f9e': 'EAT-700 Expendable Napalm', '25aa2fd4643cf4ee': 'FAF-14 Spear',
    '39ab99895147a3bf': 'FLAM-40 Flamethrower', '02eecd0b1fa49630': 'GL-21 Grenade Launcher', '88c2d09ad85a7c9f': 'GL-28 Belt-Fed Grenade Launcher',
    'fe3b29b2cfa63f9b': 'GL-52 De-Escalator', '9f80d67a12a7e40f': 'GR-8 Recoilless Rifle', 'd54b9505c0f72873': 'LAS-98 Laser Cannon',
    '35a61296619cc47e': 'LAS-99 Quasar Cannon', '43a58cb89cfa197c': 'M-1000 Maxigun', 'a6a735accb4a327f': 'M-105 Stalwart',
    '2152d5147b0ac418': 'MG-206 Heavy Machine Gun', '11c27d3babb38956': 'MG-43 Machine Gun', 'b16c9d490aa59b77': 'MGX-42 Bullet Storm',
    '5990123d142b16cb': 'MLS-4X Commando', 'e8d5f49ad7780e54': 'PLAS-45 Epoch', '26e40437ea275296': 'RL-77 Airburst Rocket Launcher',
    '2e9d0bdc48b09e60': 'RS-422 Railgun', '3828e2051aa9e897': 'S-11 Speargun', 'cc786f6491fe7e65': 'StA-X3 W.A.S.P. Launcher',
    '43b2d7766120203b': 'TX-41 Sterilizer', '52071f49263415e4': 'SG-88 Break-Action Shotgun',
}


def _components(mask):
    """the mask's connected shapes (8-neighbor), each as (pixel count, bbox, pixel list)"""
    w, h = mask.size
    px = mask.load()
    seen = bytearray(w * h)
    out = []
    for y0 in range(h):
        for x0 in range(w):
            if px[x0, y0] < 128 or seen[y0 * w + x0]:
                continue
            stack, pts = [(x0, y0)], []
            seen[y0 * w + x0] = 1
            while stack:
                x, y = stack.pop()
                pts.append((x, y))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx] and px[nx, ny] >= 128:
                            seen[ny * w + nx] = 1
                            stack.append((nx, ny))
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            out.append((len(pts), (min(xs), min(ys), max(xs) + 1, max(ys) + 1), pts))
    return out


def silhouette(path):
    """the weapon's own shape from a game marker icon (red channel), without the backpack badge: the biggest shape plus
    the pieces that sit on it (a scope, a strap), never a separate shape off in the top-right corner"""
    red = Image.open(path).convert('RGB').split()[0]
    comps = sorted(_components(red), key=lambda c: -c[0])
    if not comps:
        return None
    main = comps[0]
    bx0, by0, bx1, by1 = main[1]
    keep = [main]
    for c in comps[1:]:
        x0, y0, x1, y1 = c[1]
        # a piece of the weapon overlaps the main shape's box (with a small margin); the badge sits above it, apart
        if x0 <= bx1 + 3 and x1 >= bx0 - 3 and y1 >= by0 - 3 and y0 <= by1 + 3:
            keep.append(c)
            bx0, by0, bx1, by1 = min(bx0, x0), min(by0, y0), max(bx1, x1), max(by1, y1)
    m = Image.new('L', red.size, 0)
    mp = m.load()
    for c in keep:
        for x, y in c[2]:
            mp[x, y] = 255
    # the edges' antialiasing back from the original, inside the kept shape's neighborhood only
    soft = Image.composite(red, Image.new('L', red.size, 0), m.filter(ImageFilter.MaxFilter(3)))
    return soft.crop((bx0, by0, bx1, by1))


def generic():
    """my own plain support-weapon shape (for a weapon without a game icon): a long barrel, a stock and a grip"""
    big = Image.new('L', (400, 120), 0)
    d = ImageDraw.Draw(big)
    d.rectangle((40, 40, 360, 62), fill=255)          # barrel and body
    d.rectangle((120, 32, 250, 70), fill=255)         # receiver
    d.polygon([(40, 40), (0, 46), (0, 78), (40, 66)], fill=255)   # stock
    d.polygon([(170, 70), (200, 70), (192, 110), (166, 110)], fill=255)   # grip
    d.rectangle((260, 62, 290, 76), fill=255)         # fore grip
    return big


def texture(mask, master=False):
    """W x H, the shape in COLOR with a dark outline, centered (master: at 4x, for shrinking to each size)"""
    big_w, big_h = 4 * W, 4 * H
    pad = 14
    k = min((big_w - 2 * pad) / mask.width, (big_h - 2 * pad) / mask.height)
    m = mask.resize((max(1, round(mask.width * k)), max(1, round(mask.height * k))), Image.LANCZOS)
    full = Image.new('L', (big_w, big_h), 0)
    full.paste(m, ((big_w - m.width) // 2, (big_h - m.height) // 2))
    outline = full.filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.GaussianBlur(1.4))
    img = Image.new('RGBA', (big_w, big_h), (0, 0, 0, 0))
    dark = Image.new('RGBA', (big_w, big_h), (12, 12, 12, 255)); dark.putalpha(outline.point(lambda p: round(p * 0.9)))
    img = Image.alpha_composite(img, dark)
    body = Image.new('RGBA', (big_w, big_h), COLOR + (255,)); body.putalpha(full)
    img = Image.alpha_composite(img, body)
    return img if master else img.resize((W, H), Image.LANCZOS)


def all_textures(icon_dir, master=False):
    """unit id -> RGBA texture for every weapon; the generic one (key 'generic') for those without an icon file"""
    out = {'generic': texture(generic(), master)}
    for uid in WEAPONS:
        p = os.path.join(icon_dir, uid + '.png') if icon_dir else None
        if p and os.path.exists(p):
            s = silhouette(p)
            if s is not None:
                out[uid] = texture(s, master)
    return out


if __name__ == '__main__':
    import sys
    src, dest = sys.argv[1], sys.argv[2]
    os.makedirs(dest, exist_ok=True)
    for k, im in all_textures(src).items():
        im.save(os.path.join(dest, k + '.png'))
    print(len(all_textures(src)))
