# Treasure Radar - source

The mod is a patch that replaces the game's empty `boot` script with its own copy of Chef Loader, which runs the
Treasure Radar addon. Everything is built by `build.py` (Python 3 and Pillow), run from this folder:

    python3 build.py out              -> out/Treasure-Radar-<ver>.zip (the release; the same zip byte for byte every time)
    python3 build.py out --tester     -> out/Treasure-Radar-<ver>-Tester.zip (adds the HUD Calibration option)
    python3 build.py out --loader     -> also out/Chef-Loader-<ver>.zip (the loader on its own)

    loader.lua          Chef Loader: finds the addon and its options in the installed patches, guards every engine call
                        (a call that crashed the game is skipped from the next launch on), lists units, draws.
                        build.py gives Treasure Radar its own copy (its name, log file and the addons it runs).
    treasure_radar.lua  the addon: the radar, the ledger, the world markers, the options, the HUD placement.
                        The version is set in it (local M = { version = ... }) and in build.py (TM_VERSION).
    radar_textures.py   the radar panel, the sweep's frames, the pill, the check mark, the glow, the number characters
    icon_textures.py    the pickup icons as textures (icons.py: the game's pickup icons redrawn as vector shapes)
    option_icons.py     the Arsenal option pictures
    hd2_patch.py, patch_writer.py    write the patch files
    fonts/              Poppins Bold (SIL Open Font License), for the numbers and the option pictures
    artwork/            hero.py + cards.py: the thumbnail, gallery photo, AyakaMods cover and GitHub social picture
                        (python3 cards.py <out dir> 0.5; needs Playwright Chromium, numpy and scipy); scene.jpg is the
                        game shot behind them; thumbnail.png is the Arsenal icon build.py uses.
