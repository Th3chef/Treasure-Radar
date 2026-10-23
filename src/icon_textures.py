"""Treasure Radar: the icon textures. The icon shapes are in icons.py (vector copies of the game's pickup icons);
each kind's icon is rendered at FILL px tall inside a SIZE x SIZE texture, in the kind's color with a dark outline.
Texture resource: 192-byte Stingray header + DDS header with DX10 extension (DXGI 28, RGBA8,
one mip); pixels go to .gpu_resources."""
import struct
from PIL import Image, ImageFilter
import icons

SIZE, FILL = 48, 40     # 48 px textures, so the icons stay crisp at 1440p and 4K


def icon_image(kid, rgb):
    return icon_master(kid, rgb).resize((SIZE, SIZE), Image.LANCZOS)


def icon_master(kid, rgb):
    """the icon at 4x (192 px), for shrinking straight to each size the radar draws it at"""
    big, fill = 4 * SIZE, 4 * FILL
    a = icons.mask(kid, fill)
    w, h = a.size
    mask = Image.new('L', (big, big), 0)
    mask.paste(a, ((big - w) // 2, (big - h) // 2))
    outline = mask.filter(ImageFilter.MaxFilter(11)).filter(ImageFilter.GaussianBlur(1.4))
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    dark = Image.new('RGBA', (big, big), (12, 12, 12, 255)); dark.putalpha(outline.point(lambda p: round(p * 0.9)))
    img = Image.alpha_composite(img, dark)
    body = Image.new('RGBA', (big, big), tuple(rgb) + (255,)); body.putalpha(mask)
    return Image.alpha_composite(img, body)


def texture_resource(size, height=None):
    """size = width; height defaults to it (square)."""
    height = height or size
    head = struct.pack('<III', 0, 0, 0xFFFFFFFF) + b'\0' * 180
    dds = b'DDS ' + struct.pack('<7I', 124, 0x100F, height, size, size * 4, 0, 1) + b'\0' * 44
    dds += struct.pack('<2I4s5I', 32, 4, b'DX10', 0, 0, 0, 0, 0)
    dds += struct.pack('<5I', 0x1000, 0, 0, 0, 0)
    dds += struct.pack('<5I', 28, 3, 0, 1, 0)
    out = head + dds
    assert len(out) == 340
    return out
