#!/usr/bin/env python3
"""Reject app icons that reintroduce a legacy nested compatibility enclosure."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image


def fail(message: str) -> None:
    raise SystemExit(message)


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: verify_compiled_app_icon.py /path/to/AppIcon.icns")

    icon = Path(sys.argv[1])
    if not icon.is_file():
        fail(f"Compiled AppIcon is missing: {icon}")

    with tempfile.TemporaryDirectory(prefix="pointrans-icon-") as directory:
        output = Path(directory) / "AppIcon.iconset"
        subprocess.run(
            ["iconutil", "-c", "iconset", str(icon), "-o", str(output)],
            check=True,
        )
        images = list(output.glob("*.png"))
        if not images:
            fail("Compiled AppIcon.icns contains no raster rendition")

        def pixel_area(path: Path) -> int:
            with Image.open(path) as image:
                return image.width * image.height

        with Image.open(max(images, key=pixel_area)) as source:
            rendition = source.convert("RGBA")

    width, height = rendition.size
    if width != height or width < 128:
        fail(f"Expected a square compiled AppIcon rendition, found {rendition.size}")

    alpha = rendition.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None or alpha.getextrema() != (0, 255):
        fail("Expected the system-rendered AppIcon enclosure with transparent corners")

    # A modern Icon Composer background reaches the one system enclosure near
    # the outer edge. A precomposed rounded-square PNG leaves a broad gray ring
    # here after macOS applies its legacy compatibility enclosure a second time.
    inset = round(width * 0.14)
    edge_samples = (
        rendition.getpixel((width // 2, inset)),
        rendition.getpixel((inset, height // 2)),
        rendition.getpixel((width // 2, height - inset - 1)),
        rendition.getpixel((width - inset - 1, height // 2)),
    )
    if any(alpha_value < 240 or max(red, green, blue) > 12 for red, green, blue, alpha_value in edge_samples):
        fail("Compiled AppIcon has a secondary inset enclosure instead of one black system enclosure")

    opaque_pixels = [pixel for pixel in rendition.getdata() if pixel[3] > 240]
    if not opaque_pixels or max(max(red, green, blue) for red, green, blue, _ in opaque_pixels) < 247:
        fail("Compiled AppIcon is missing the approved white Pointrans symbol")

    print(f"Verified modern compiled AppIcon rendition {rendition.size} without a nested enclosure")


if __name__ == "__main__":
    main()
