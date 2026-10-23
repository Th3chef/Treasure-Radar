"""Treasure Radar's below-native colors: measured, not modeled.

Color swatches (16 steps of 17 per channel, drawn the radar's way) screenshotted at Native and at Ultra Quality on a
3440x1440 HDR screen. At native my GUI is drawn in the game's world and goes through its tone mapping (N: a steep curve,
colors hot and saturated: 136 already comes out 204-255); below native it's drawn in the UI world (U: close to a line,
17 -> 35, 255 -> 255). Both blend before their curve (white at alpha a over black comes out exactly as gray a).
So for each color of mine I store, below native, the value that comes out of U the way the original comes out of N:
s = U^-1(N(c)) per channel; a see-through one also gets the alpha that best matches over two typical backgrounds.
The same tables are in Chef Shared Loader (ui_color), for the colors it's handed."""
import numpy as np

STEP = 17
N = {'r': [0, 7, 27, 51, 78, 110, 148, 196, 255, 255, 255, 255, 255, 255, 255, 255],
     'g': [0, 7, 25, 44, 65, 89, 120, 165, 221, 255, 255, 255, 255, 255, 255, 255],
     'b': [0, 5, 20, 41, 64, 91, 124, 165, 220, 255, 255, 255, 255, 255, 255, 255]}
U = {'r': [0, 35, 58, 79, 98, 117, 136, 155, 175, 195, 217, 238, 255, 255, 255, 255],
     'g': [0, 38, 57, 74, 91, 110, 130, 151, 173, 193, 215, 235, 255, 255, 255, 255],
     'b': [0, 33, 54, 74, 93, 111, 129, 148, 167, 187, 207, 228, 248, 255, 255, 255]}
XS = np.arange(16) * STEP
BACKS = (6.0, 40.0, 110.0)     # the backgrounds a see-through color is matched over, as they show on screen: the
                               # radar's dark face, dark ground, and mid ground
ALPHAS = np.linspace(0, 1, 65)


def _rising(ys):
    """the strictly rising part of a curve (for its inverse): x and y up to where it first reaches its top"""
    ys = np.asarray(ys, float)
    top = int(np.argmax(ys >= ys.max()))
    return XS[:top + 1].astype(float), ys[:top + 1]


def n(ch, v): return np.interp(v, XS, N[ch])
def u(ch, v): return np.interp(v, XS, U[ch])
def n_inv(ch, t): x, y = _rising(N[ch]); return np.interp(t, y, x)
def u_inv(ch, t): x, y = _rising(U[ch]); return np.interp(t, y, x)


def m(ch, v):
    """the stored value below native that comes out as v does at native: U^-1(N(v))"""
    return u_inv(ch, n(ch, v))


def ui_rgba(rgba):
    """an array (..., 4) of 0..255 colors as I designed them (as they look at native) -> the values to store below native.
    An opaque color: m(c) per channel. A see-through one: both ways blend before their curve, so in U's input space the
    native result over a background b is m(a c + (1 - a) b), and mine is a2 s + (1 - a2) m(b); for each alpha a2 the
    best s (per channel) is the least-squares fit over BACKS, and the alpha that fits best wins."""
    rgba = np.asarray(rgba, float)
    out = np.empty_like(rgba)
    for i, ch in enumerate('rgb'):
        out[..., i] = m(ch, rgba[..., i])
    out[..., 3] = rgba[..., 3]
    a_all = rgba[..., 3] / 255
    part = (a_all > 0) & (a_all < 1)
    if part.any():
        c, a = rgba[part], a_all[part]
        nb = len(BACKS)
        want = np.stack([np.stack([m(ch, a * c[:, i] + (1 - a) * n_inv(ch, bk)) for i, ch in enumerate('rgb')], 1) for bk in BACKS])
        mb = np.array([[m(ch, n_inv(ch, bk)) for ch in 'rgb'] for bk in BACKS])          # (nb, 3)
        best_err = np.full(a.shape, np.inf); best_a = a.copy(); best_s = c[:, :3].copy()
        for a2 in ALPHAS[1:]:
            s_ = ((want - (1 - a2) * mb[:, None, :]) / a2).mean(0).clip(0, 255)          # (k, 3)
            got = a2 * s_[None] + (1 - a2) * mb[:, None, :]
            err = ((got - want) ** 2).sum((0, 2))
            better = err < best_err
            best_err = np.where(better, err, best_err); best_a = np.where(better, a2, best_a)
            best_s = np.where(better[:, None], s_, best_s)
        sub = out[part]; sub[:, :3] = best_s; sub[:, 3] = best_a * 255; out[part] = sub
    return np.clip(out, 0, 255)


def lua_tables():
    """the tables as Lua, for the loader"""
    f = lambda t: '{ ' + ', '.join(str(v) for v in t) + ' }'
    return '\n'.join('local UI_%s_%s = %s' % (k, ch.upper(), f(t[ch])) for k, t in (('N', N), ('U', U)) for ch in 'rgb')
