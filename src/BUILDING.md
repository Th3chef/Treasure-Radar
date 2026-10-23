# Treasure Radar - source

The mod is a Chef Shared Loader addon packed as an Arsenal mod with Options. It needs the standalone Chef Shared Loader
(1.0.0 or newer, its own mod); the loader's source lives only in the Chef Shared Loader kit, and loader changes go there.
Everything here is built by `build.py` (Python 3 and Pillow), run from this folder:

    python3 build.py out --weapons-from Treasure-Radar-<ver>.zip
                                      -> out/Treasure-Radar-<ver>.zip (the release, byte for byte)
    python3 build.py out --tester ... -> out/Treasure-Radar-<ver>-Tester.zip (the release on the Tester's id)

The weapon silhouettes are made from the game's own weapon marker icons, which aren't in this repository: put them
in weapon_icons/<unit id>.png (from your game, with Filediver), or pass --weapons-from with the release zip to take the
finished textures (and the Weapons option's picture) from it. Without either, every weapon gets my generic shape.

    treasure_radar.lua  the addon: the radar, the ledger, the world markers, the options, the HUD placement.
                        The version is set in it (local M = { version = ... }) and in build.py (TM_VERSION).
    radar_textures.py   the radar panel, the sweep's frames, the ledger's tile, the check mark, the glow, the number characters
    ui_calib.py         the color curves for the textures' copies below native Render Scale (measured in game)
    weapon_textures.py  the weapon silhouettes (from the game's marker icons, see above)
    icon_textures.py    the pickup icons as textures (icons.py: the game's pickup icons redrawn as vector shapes)
    option_icons.py     the Arsenal option pictures
    hd2_patch.py, patch_writer.py    write the patch files
    fonts/              Poppins Bold (SIL Open Font License), for the numbers and the option pictures
    artwork/            hero.py + cards.py: the thumbnail, gallery photo, AyakaMods cover and GitHub social picture
                        (python3 cards.py <out dir> 0.6; needs Playwright Chromium, numpy and scipy); scene.jpg is the
                        game shot behind them; thumbnail.png is the Arsenal icon build.py uses.
