#!/usr/bin/env python3
"""Validate the modern app icon and generate runtime brand assets."""

import json
from pathlib import Path
from shutil import copy2

from PIL import Image


ROOT = Path(__file__).resolve().parent.parent
BRAND_ROOT = ROOT / "Pointrans_Logo_Design_Files"
APP_ICON = ROOT / "Sources" / "Pointrans" / "Resources" / "AppIcon.icon"
APP_ICON_MANIFEST = APP_ICON / "icon.json"
APP_ICON_LAYER_NAME = "pointrans_symbol_white_icon_layer_1024.png"
APP_ICON_LAYER = APP_ICON / "Assets" / APP_ICON_LAYER_NAME
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


def validate_app_icon() -> None:
    manifest = json.loads(APP_ICON_MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("fill", {}).get("solid") != "extended-srgb:0.00000,0.00000,0.00000,1.00000":
        raise SystemExit("Expected AppIcon.icon to use a pure-black Icon Composer background")

    groups = manifest.get("groups", [])
    layers = [layer for group in groups for layer in group.get("layers", [])]
    if len(layers) != 1 or layers[0].get("image-name") != APP_ICON_LAYER_NAME:
        raise SystemExit("Expected AppIcon.icon to contain only the transparent white symbol layer")
    if any(group.get("translucency", {}).get("enabled", False) for group in groups):
        raise SystemExit("AppIcon.icon groups must remain opaque")

    with Image.open(APP_ICON_LAYER) as source:
        layer = source.convert("RGBA")
        if layer.size != (1024, 1024):
            raise SystemExit(f"Expected a 1024 x 1024 Icon Composer layer, found {layer.size}")
        alpha = layer.getchannel("A")
        bounds = alpha.getbbox()
        if bounds is None or alpha.getextrema() != (0, 255):
            raise SystemExit("Expected a nonempty Pointrans symbol on a transparent canvas")
        left, top, right, bottom = bounds
        if min(left, top, 1024 - right, 1024 - bottom) < 150:
            raise SystemExit("Pointrans symbol must remain inside the approved safe area")
        visible = [pixel for pixel in layer.getdata() if pixel[3] > 240]
        if not visible or min(min(red, green, blue) for red, green, blue, _ in visible) < 247:
            raise SystemExit("Expected an opaque white Pointrans symbol layer")


def main() -> None:
    required = (APP_ICON_MANIFEST, APP_ICON_LAYER, SYMBOL_SOURCE, LOGO_SOURCE)
    missing = [str(path.relative_to(ROOT)) for path in required if not path.is_file()]
    if missing:
        raise SystemExit(f"Missing approved Pointrans brand source: {', '.join(missing)}")

    validate_app_icon()

    SYMBOL_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    LOGO_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    copy2(SYMBOL_SOURCE, SYMBOL_OUTPUT)
    copy2(LOGO_SOURCE, LOGO_OUTPUT)
    print(
        "Validated AppIcon.icon and copied the approved vector mark and lockup"
    )


if __name__ == "__main__":
    main()
