#!/usr/bin/env python3
"""
Slice a 4x3 generated badge sprite sheet into template PNGs.

Input: black pixel glyphs on a white/light grid background.
Output: solid black on transparent 128x128 PNGs under Resources/Badges.
"""

from __future__ import annotations

import sys
from pathlib import Path
from PIL import Image

BADGE_NAMES = [
    "first_listen",
    "new_artist",
    "rediscovered",
    "deep_cut",
    "on_streak",
    "repeat_track",
    "album_mode",
    "play_10",
    "play_50",
    "play_100",
    "anniversary",
    "fallback",
]

OUTPUT_SIZE = 128
PAD_FRACTION = 0.10
BACKGROUND_THRESHOLD = 585


def to_template_alpha(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    pixels = img.load()
    width, height = img.size

    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0 or red + green + blue > BACKGROUND_THRESHOLD:
                pixels[x, y] = (0, 0, 0, 0)
            else:
                pixels[x, y] = (0, 0, 0, 255)

    return img


def fit_to_square(img: Image.Image) -> Image.Image:
    bbox = img.getbbox()
    if bbox is None:
        return Image.new("RGBA", (OUTPUT_SIZE, OUTPUT_SIZE), (0, 0, 0, 0))

    cropped = img.crop(bbox)
    inner = int(OUTPUT_SIZE * (1 - 2 * PAD_FRACTION))
    scale = inner / max(cropped.size)
    width = max(1, round(cropped.width * scale))
    height = max(1, round(cropped.height * scale))
    resized = cropped.resize((width, height), Image.Resampling.NEAREST)

    canvas = Image.new("RGBA", (OUTPUT_SIZE, OUTPUT_SIZE), (0, 0, 0, 0))
    origin = ((OUTPUT_SIZE - width) // 2, (OUTPUT_SIZE - height) // 2)
    canvas.alpha_composite(resized, origin)
    return canvas


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: slice-badge-sheet.py <input.png> <output_dir>", file=sys.stderr)
        return 1

    source = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    output_dir.mkdir(parents=True, exist_ok=True)

    sheet = Image.open(source).convert("RGBA")
    columns = 4
    rows = 3
    cell_width = sheet.width // columns
    cell_height = sheet.height // rows

    print(f"sheet: {sheet.width}x{sheet.height}, cell: {cell_width}x{cell_height}")

    for index, name in enumerate(BADGE_NAMES):
        row = index // columns
        column = index % columns
        cell = sheet.crop((
            column * cell_width,
            row * cell_height,
            (column + 1) * cell_width,
            (row + 1) * cell_height,
        ))
        badge = fit_to_square(to_template_alpha(cell))
        out_path = output_dir / f"{name}.png"
        badge.save(out_path)
        print(f"  [{index:02d}] {name} -> {out_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
