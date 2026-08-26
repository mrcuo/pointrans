#!/usr/bin/env python3
"""Generate the Pointrans AppIcon from code-defined brand geometry."""

from pathlib import Path
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Sources" / "Pointrans" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"


def icon(size: int) -> Image.Image:
    scale = size / 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    margin = int(74 * scale)
    radius = int(228 * scale)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (margin, margin, size - margin, size - margin), radius=radius, fill=255
    )

    # Code-defined cobalt gradient matching the menu-bar control center.
    gradient = Image.new("RGBA", (size, size))
    pixels = gradient.load()
    start = (28, 118, 255)
    end = (20, 62, 221)
    denominator = max(1, (size - 1) * 2)
    for y in range(size):
        for x in range(size):
            amount = (x + y) / denominator
            pixels[x, y] = tuple(
                round(start[channel] * (1 - amount) + end[channel] * amount)
                for channel in range(3)
            ) + (255,)
    image.paste(gradient, (0, 0), mask)
    draw = ImageDraw.Draw(image)

    # P stroke, intentionally geometric so it remains legible at 16 pt.
    glyph = (255, 255, 255, 255)
    width = max(2, int(68 * scale))
    points = [
        (int(320 * scale), int(725 * scale)),
        (int(320 * scale), int(295 * scale)),
        (int(505 * scale), int(295 * scale)),
        (int(645 * scale), int(330 * scale)),
        (int(700 * scale), int(455 * scale)),
        (int(650 * scale), int(575 * scale)),
        (int(505 * scale), int(610 * scale)),
        (int(405 * scale), int(610 * scale)),
    ]
    draw.line(points, fill=glyph, width=width, joint="curve")

    cursor = [
        (int(545 * scale), int(515 * scale)),
        (int(790 * scale), int(750 * scale)),
        (int(678 * scale), int(755 * scale)),
        (int(632 * scale), int(864 * scale)),
    ]
    draw.polygon(cursor, fill=glyph)
    return image


def main() -> None:
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
    for filename, size in files.items():
        icon(size).save(OUTPUT / filename, optimize=True)
    print(f"Generated {len(files)} icon files in {OUTPUT}")


if __name__ == "__main__":
    main()
