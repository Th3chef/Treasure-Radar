"""Treasure Radar's in-action clip: the hero scene (hero.py) animated, as frames for a video. The sweep turns every 3
seconds as in game; I walk north, so everything drifts south on the radar; I pick up the ammo pile and a medal (the
ledger counts down); the bug pack closes in, the heavy with it, and one of the pack dies and drops off; the troopers
and my squad move about.
python clip.py <out dir> [seconds] [fps] -> <out dir>/frame_0000.jpg ... (1280x720), which any encoder turns into
the video (ffmpeg, or Windows' own H.264 encoder: clip_encode.ps1)."""
import math, os, sys
import hero

W, H, CX, CY, R = 1280, 720, 820, 360, 292
WALK = 0.018                      # radar radii a second the world drifts south while I walk north


def pickups_at(t):
    out = []
    for x, y, kid, cnt in hero.PICKUPS:
        if kid == 'ammo':
            # the ammo pile right ahead of me: one box picked up every 1.2 s from 4.5 s
            cnt = max(0, cnt - max(0, int((t - 4.5) / 1.2) + 1)) if t >= 4.5 else cnt
            if cnt == 0:
                continue
        if kid == 'medal' and cnt == 1 and t >= 8.5:
            continue                  # the medal north-east of me, picked up
        out.append((x, y - WALK * t, kid, cnt))
    return out


def foes_at(t):
    out = []
    for i, (x, y, kid, tier) in enumerate(hero.FOES):
        if kid == 'enemydot' and x > 0.5 and tier == 1 and i == 0 and t >= 9.2:
            continue                  # one of the pack shot dead: it drops off at once
        if kid in ('enemydot', 'enemy') and x > 0.5:
            # the bug pack and its heavy close in from the east
            k = min(1, t / 12) * 0.28
            x, y = x - k, y - k * 0.2
        elif kid in ('frienddot', 'squaddot'):
            x, y = x + 0.03 * math.sin(t * 1.3 + i), y + 0.03 * math.cos(t * 1.1 + i)
        elif kid in ('enemydot', 'enemy'):
            x, y = x + 0.02 * math.sin(t * 0.7 + i), y + 0.02 * math.cos(t * 0.6 + i)
        out.append((x, y - WALK * t * (0 if kid in ('frienddot', 'squaddot') else 1), kid, tier))
    return out


def rows_at(t):
    ammo = 5 - (min(4, max(0, int((t - 4.5) / 1.2) + 1)) if t >= 4.5 else 0)
    medal = 4 - (1 if t >= 8.5 else 0)
    rows = []
    for row in hero.LEDGER_ROWS:
        rows.append([(k, ammo if k == 'ammo' else (medal if k == 'medal' else n)) for k, n in row])
    return rows


def main():
    out = sys.argv[1]
    secs = float(sys.argv[2]) if len(sys.argv) > 2 else 12
    fps = int(sys.argv[3]) if len(sys.argv) > 3 else 30
    os.makedirs(out, exist_ok=True)
    bg = hero.background(W, H)
    n = int(secs * fps)
    for i in range(n):
        t = i / fps
        img = hero.hero(W, H, CX, CY, R, bg=bg, sweep_at=(t / 3 * 360) % 360, pickups=pickups_at(t), foes=foes_at(t),
                        rows=rows_at(t))
        img.convert('RGB').save(os.path.join(out, 'frame_%04d.jpg' % i), quality=92)
        if i % 60 == 0:
            print('frame %d / %d' % (i, n), flush=True)
    print('%d frames, %d fps' % (n, fps))


if __name__ == '__main__':
    main()
