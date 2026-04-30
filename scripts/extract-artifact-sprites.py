#!/usr/bin/env python3
"""Extract Dial artifact template sprites from a generated 4x3 sheet.

The app renders artifact PNGs as SwiftUI template images, so only dark pixels
should survive. This script removes generated white/checkerboard pixels,
recenters each cell, and exports crisp 128x128 transparent PNGs.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from shutil import copyfile

from PIL import Image


ARTIFACTS = [
    "first_listen_spark",
    "new_artist_token",
    "rediscovered_cassette",
    "deep_cut_gem",
    "streak_flame",
    "repeat_loop",
    "album_stack",
    "play_10_trophy",
    "play_50_trophy",
    "play_100_trophy",
    "anniversary_relic",
    "beat_bounce_charm",
]


def is_dark(pixel: tuple[int, int, int]) -> bool:
    r, g, b = pixel
    return r < 96 and g < 96 and b < 96


def dark_mask(cell: Image.Image) -> Image.Image:
    cell = cell.convert("RGB")
    out = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    src = cell.load()
    dst = out.load()
    for y in range(cell.height):
      for x in range(cell.width):
        if is_dark(src[x, y]):
          dst[x, y] = (0, 0, 0, 255)
    return out


def trim(image: Image.Image) -> Image.Image:
    bbox = image.getbbox()
    return image.crop(bbox) if bbox else image


def fit_sprite(sprite: Image.Image, size: int = 128, max_extent: int = 96) -> Image.Image:
    sprite = trim(sprite)
    if sprite.width == 0 or sprite.height == 0:
        return Image.new("RGBA", (size, size), (0, 0, 0, 0))

    scale = min(max_extent / sprite.width, max_extent / sprite.height)
    target = (max(1, round(sprite.width * scale)), max(1, round(sprite.height * scale)))
    sprite = sprite.resize(target, Image.Resampling.NEAREST)

    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    x = (size - sprite.width) // 2
    y = (size - sprite.height) // 2
    canvas.alpha_composite(sprite, (x, y))
    return canvas


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("sheet", type=Path)
    parser.add_argument("--out", type=Path, default=Path("Dial/Resources/Artifacts"))
    args = parser.parse_args()

    sheet = Image.open(args.sheet).convert("RGB")
    args.out.mkdir(parents=True, exist_ok=True)
    copyfile(args.sheet, args.out / "artifact_sheet_source.png")

    cell_w = sheet.width / 4
    cell_h = sheet.height / 3
    for index, name in enumerate(ARTIFACTS):
        col = index % 4
        row = index // 4
        box = (
            round(col * cell_w),
            round(row * cell_h),
            round((col + 1) * cell_w),
            round((row + 1) * cell_h),
        )
        sprite = fit_sprite(dark_mask(sheet.crop(box)))
        sprite.save(args.out / f"{name}.png")


if __name__ == "__main__":
    main()
