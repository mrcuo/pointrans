#!/usr/bin/env python3
"""Generate runtime brand assets from the approved Pointrans v1.1 artwork."""

from pathlib import Path
from shutil import copy2

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Sources" / "Pointrans" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
BRAND_ROOT = ROOT / "Pointrans_Logo_Design_Files"
APP_ICON_SOURCE = BRAND_ROOT / "02_Symbol" / "pointrans_symbol_black_on_white_1024.png"
SYMBOL_SOURCE = BRAND_ROOT / "02_Symbol" / "pointrans_symbol_black.svg"
LOGO_SOURCE = BRAND_ROOT / "01_Master_Vector" / "pointrans_logo_master_black.svg"
SYMBOL_OUTPUT = (
    ROOT
    / "Sources"
    / "Pointrans"
    / "Resources"
    / "Assets.xcassets"
    / "PointransSymbol.imageset"
    / "pointrans_symbol_black.svg"
)
LOGO_OUTPUT = (
    ROOT
    / "Sources"
    / "Pointrans"
    / "Resources"
    / "Assets.xcassets"
    / "PointransLogo.imageset"
    / "pointrans_logo_master_black.svg"
)


def icon(master: Image.Image, size: int) -> Image.Image:
    if master.size == (size, size):
        return master.copy()
    return master.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    required = (APP_ICON_SOURCE, SYMBOL_SOURCE, LOGO_SOURCE)
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    if missing:
        raise SystemExit(f"Missing approved Pointrans brand source: {', '.join(missing)}")

    OUTPUT.mkdir(parents=True, exist_ok=True)
    files = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    with Image.open(APP_ICON_SOURCE) as source:
        master = source.convert("RGBA")
        if master.size != (1024, 1024):
            raise SystemExit(f"Expected a 1024 x 1024 AppIcon source, found {master.size}")
        for filename, size in files.items():
            icon(master, size).save(OUTPUT / filename, optimize=True)

    SYMBOL_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    LOGO_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    copy2(SYMBOL_SOURCE, SYMBOL_OUTPUT)
    copy2(LOGO_SOURCE, LOGO_OUTPUT)
    print(f"Generated {len(files)} AppIcon files and copied the approved vector mark and lockup")


if __name__ == "__main__":
    main()
