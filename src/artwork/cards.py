"""Treasure Radar release art: thumbnail (1254x1254, and the 512x512 Arsenal one), gallery photo (1920x1080), GitHub
social preview (1280x640) and the AyakaMods cover (1600x1000, everything inside the middle that the site's mod cards
show). The scene comes from hero.py; the title, version badge and text are HTML rendered with Playwright Chromium
(Anton + Barlow Condensed in fonts/, SIL Open Font License, from @fontsource).
python cards.py <out dir> [version badge, e.g. 0.5]"""
import base64, io, os, sys
from playwright.sync_api import sync_playwright
import hero

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = {'Anton': 'fonts/anton-latin-400-normal.woff2',
         'Barlow Condensed': 'fonts/barlow-condensed-latin-600-normal.woff2',
         'Barlow Condensed B': 'fonts/barlow-condensed-latin-800-normal.woff2'}

TAGLINE = 'Every sample, medal, Super Credit, Requisition Slip and supply around you, on a sonar radar where your map opens'
FEATURES = ['SONAR SWEEP', 'LOOT LEDGER', 'WORLD MARKERS', 'ZOOM & ROTATE', 'FITS YOUR HUD']


def b64(path_or_img):
    if isinstance(path_or_img, str):
        return base64.b64encode(open(os.path.join(HERE, path_or_img), 'rb').read()).decode()
    buf = io.BytesIO(); path_or_img.save(buf, 'PNG'); return base64.b64encode(buf.getvalue()).decode()


def font_css():
    return '\n'.join("@font-face{font-family:'%s';src:url(data:font/woff2;base64,%s) format('woff2');}" % (n, b64(f))
                     for n, f in FONTS.items())


CSS = """
* { margin:0; padding:0; box-sizing:border-box; }
body { width:%(W)dpx; height:%(H)dpx; overflow:hidden; background:#000; position:relative; }
.bg { position:absolute; inset:0; background:url(data:image/png;base64,%(bg)s) no-repeat; background-size:100%% 100%%; }
.title { font-family:'Anton'; color:#ffe710; letter-spacing:0.02em; line-height:0.95; text-transform:uppercase;
  text-shadow: 0 0.04em 0 #000, 0 0 0.12em rgba(0,0,0,.9), 0 0 0.35em rgba(0,0,0,.6); }
.badge { display:inline-block; font-family:'Barlow Condensed B'; background:#ffe710; color:#111; padding:0.04em 0.32em 0.02em;
  border:0.06em solid #111; box-shadow:0 0.08em 0.25em rgba(0,0,0,.6); letter-spacing:0.03em; }
.tag { font-family:'Barlow Condensed'; color:#f6ead2; line-height:1.15;
  text-shadow: 0 0.05em 0.05em #000, 0 0 0.3em rgba(0,0,0,.95), 0 0 0.6em rgba(0,0,0,.7); }
.feat { font-family:'Barlow Condensed B'; color:#111; display:flex; flex-wrap:wrap; gap:0.35em; }
.feat span { background:rgba(255,231,16,.95); padding:0.06em 0.4em 0.02em; border:0.05em solid #111; letter-spacing:0.04em;
  box-shadow:0 0.06em 0.2em rgba(0,0,0,.55); }
.plate { position:absolute; background:linear-gradient(rgba(10,9,7,.84),rgba(10,9,7,.76)); border:3px solid #ffe710;
  box-shadow:0 8px 30px rgba(0,0,0,.6); }
"""


def render(page, W, H, bg, body):
    html = '<html><head><style>%s\n%s</style></head><body><div class="bg"></div>%s</body></html>' % (
        font_css(), CSS % {'W': W, 'H': H, 'bg': b64(bg)}, body)
    page.set_viewport_size({'width': W, 'height': H})
    page.set_content(html)
    page.wait_for_timeout(300)
    return page.screenshot(type='png')


def feats(size):
    return '<div class="feat" style="font-size:%dpx">%s</div>' % (size, ''.join('<span>%s</span>' % f for f in FEATURES))


def main():
    out = sys.argv[1]
    ver = sys.argv[2] if len(sys.argv) > 2 else '0.5'
    os.makedirs(out, exist_ok=True)
    jobs = []
    # square thumbnail: the title at the top, the radar and ledger in the middle, the tagline at the bottom
    W = H = 1254
    bg = hero.hero(W, H, 742, 655, 380)
    jobs.append(('thumbnail_1254.png', W, H, bg, """
      <div style="position:absolute;left:0;right:0;top:56px;display:flex;justify-content:center;align-items:flex-start;gap:24px">
        <div class="title" style="font-size:132px;white-space:nowrap">Treasure Radar</div>
        <span class="badge" style="font-size:48px;margin-top:8px">v%(v)s</span>
      </div>
      <div style="position:absolute;left:70px;right:70px;bottom:52px;text-align:center">
        <div class="tag" style="font-size:42px">%(t)s</div>
      </div>""" % {'v': ver, 't': TAGLINE}))
    # gallery photo 16:9: the radar on the right, the text on the left
    W, H = 1920, 1080
    bg = hero.hero(W, H, 1400, 560, 400)
    jobs.append(('gallery_1920x1080.png', W, H, bg, """
      <div class="plate" style="left:70px;top:170px;width:600px;padding:44px 40px 46px">
        <div class="title" style="font-size:118px">Treasure<br>Radar</div>
        <div style="margin:26px 0 30px"><span class="badge" style="font-size:46px">v%(v)s</span></div>
        <div class="tag" style="font-size:38px">%(t)s</div>
        <div style="margin-top:34px">%(f)s</div>
      </div>""" % {'v': ver, 't': TAGLINE, 'f': feats(30)}))
    # GitHub social preview 2:1 (40 px clear at the edges)
    W, H = 1280, 640
    bg = hero.hero(W, H, 950, 322, 255)
    jobs.append(('GitHub-Social-1280x640.png', W, H, bg, """
      <div class="plate" style="left:48px;top:62px;width:440px;padding:30px 30px 32px">
        <div class="title" style="font-size:84px">Treasure<br>Radar</div>
        <div style="margin:18px 0 20px"><span class="badge" style="font-size:34px">v%(v)s</span></div>
        <div class="tag" style="font-size:26px">%(t)s</div>
        <div style="margin-top:20px">%(f)s</div>
      </div>""" % {'v': ver, 't': TAGLINE, 'f': feats(20)}))
    # AyakaMods cover 1.6:1: everything inside the middle 1190x800 (the mod cards crop it to 1.2:1 .. 2:1)
    W, H = 1600, 1000
    bg = hero.hero(W, H, 1120, 500, 285)
    jobs.append(('AyakaMods-Cover-1600x1000.png', W, H, bg, """
      <div class="plate" style="left:226px;top:168px;width:440px;padding:32px 32px 34px">
        <div class="title" style="font-size:90px">Treasure<br>Radar</div>
        <div style="margin:18px 0 22px"><span class="badge" style="font-size:36px">v%(v)s</span></div>
        <div class="tag" style="font-size:28px">%(t)s</div>
        <div style="margin-top:22px">%(f)s</div>
      </div>""" % {'v': ver, 't': TAGLINE, 'f': feats(21)}))
    with sync_playwright() as p:
        b = p.chromium.launch()
        page = b.new_page()
        for name, W, H, bg, body in jobs:
            open(os.path.join(out, name), 'wb').write(render(page, W, H, bg, body))
            print(name)
        b.close()
    # the Arsenal thumbnail inside the mod zip: 512x512 from the 1254 art
    from PIL import Image
    Image.open(os.path.join(out, 'thumbnail_1254.png')).convert('RGB').resize((512, 512), Image.LANCZOS).save(
        os.path.join(out, 'thumbnail.png'))
    print('thumbnail.png')


if __name__ == '__main__':
    main()
