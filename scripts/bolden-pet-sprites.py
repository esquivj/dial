#!/usr/bin/env python3
"""
Add enough pixel weight for Dial's pet to survive small HUD rendering.

The app often renders the pet at 47px tall. Thin one-pixel source strokes
look fine in a full-size audit sheet but vanish in the actual HUD. This pass
keeps every frame on the canonical 559x559 canvas and expands the black pixel
mask just enough to read at app scale.
"""

from __future__ import annotations

import argparse
import json
import shutil
from dataclasses import asdict, dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "Dial/Resources/Pets"
DEFAULT_OUT_DIR = ROOT / "output/pet-bold-pass"

CANONICAL_CANVAS = (559, 559)
PREVIEW_HEIGHTS = (47, 88)
LCD_BG = (215, 217, 169, 255)
SURFACE = (12, 19, 23, 255)
TEXT = (226, 238, 240, 255)
MUTED = (143, 153, 160, 255)
ACCENT = (35, 183, 245, 255)

SPRITES = [
  "egg", "hatching", "hatchling", "juvenile", "companion", "elder",
  "companion-idle", "companion-idle-blink", "companion-walk-a",
  "companion-walk-b", "companion-beat-sync", "companion-first-listen",
  "companion-rediscovered", "companion-paused", "companion-dormant",
  "companion-level-up", "companion-eating-a", "companion-eating-b",
  "companion-sleeping-a", "companion-sleeping-b",
  "companion-spark-step-a", "companion-spark-step-b",
  "companion-memory-spin-a", "companion-memory-spin-b",
  "companion-beat-bounce-a", "companion-beat-bounce-b",
]


@dataclass
class Boldening:
  name: str
  source_bounds: tuple[int, int, int, int]
  output_bounds: tuple[int, int, int, int]
  source_visible: tuple[int, int]
  output_visible: tuple[int, int]
  stroke_kernel: int


def alpha_bounds(img: Image.Image) -> tuple[int, int, int, int]:
  bounds = img.convert("RGBA").split()[-1].getbbox()
  if bounds is None:
    raise ValueError("empty sprite")
  return bounds


def visible_size(bounds: tuple[int, int, int, int]) -> tuple[int, int]:
  x0, y0, x1, y1 = bounds
  return (x1 - x0, y1 - y0)


def load_font(size: int, bold: bool = False) -> ImageFont.ImageFont:
  candidates = [
    "/System/Library/Fonts/Monaco.ttf",
    "/System/Library/Fonts/Menlo.ttc",
    "/System/Library/Fonts/SFNSMono.ttf",
  ]
  for candidate in candidates:
    try:
      return ImageFont.truetype(candidate, size=size, index=1 if bold and candidate.endswith(".ttc") else 0)
    except Exception:
      continue
  return ImageFont.load_default()


def resize_full_canvas(img: Image.Image, target_height: int) -> Image.Image:
  scale = target_height / img.size[1]
  width = max(1, round(img.size[0] * scale))
  return img.resize((width, target_height), Image.Resampling.NEAREST)


def bolden_sprite(name: str, source_dir: Path, frames_dir: Path, stroke_kernel: int) -> Boldening:
  source_path = source_dir / f"{name}.png"
  output_path = frames_dir / f"{name}.png"
  img = Image.open(source_path).convert("RGBA")
  if img.size != CANONICAL_CANVAS:
    raise ValueError(f"{name} is {img.size}, expected {CANONICAL_CANVAS}")

  source_bounds = alpha_bounds(img)
  alpha = img.split()[-1].point(lambda px: 255 if px > 12 else 0)
  alpha = alpha.filter(ImageFilter.MaxFilter(stroke_kernel))

  output = Image.new("RGBA", CANONICAL_CANVAS, (0, 0, 0, 0))
  black = Image.new("RGBA", CANONICAL_CANVAS, (0, 0, 0, 255))
  output = Image.composite(black, output, alpha)
  output.save(output_path)

  output_bounds = alpha_bounds(output)
  return Boldening(
    name=name,
    source_bounds=source_bounds,
    output_bounds=output_bounds,
    source_visible=visible_size(source_bounds),
    output_visible=visible_size(output_bounds),
    stroke_kernel=stroke_kernel,
  )


def draw_lcd(
  sheet: Image.Image,
  rect: tuple[int, int, int, int],
  img: Image.Image,
  preview_height: int,
  label: str,
  font: ImageFont.ImageFont,
) -> None:
  draw = ImageDraw.Draw(sheet)
  draw.rounded_rectangle(rect, radius=5, fill=LCD_BG)
  cx = (rect[0] + rect[2]) // 2
  cy = (rect[1] + rect[3]) // 2
  draw.line((cx, rect[1] + 5, cx, rect[3] - 5), fill=(180, 183, 143, 255), width=1)
  draw.line((rect[0] + 5, cy, rect[2] - 5, cy), fill=(180, 183, 143, 255), width=1)
  preview = resize_full_canvas(img, preview_height)
  px = rect[0] + (rect[2] - rect[0] - preview.size[0]) // 2
  py = rect[1] + (rect[3] - rect[1] - preview.size[1]) // 2
  sheet.alpha_composite(preview, (px, py))
  draw.text((rect[0] + 6, rect[3] - 16), label, font=font, fill=(49, 58, 48, 255))


def render_review(items: list[Boldening], source_dir: Path, frames_dir: Path, out_path: Path) -> None:
  featured = [
    "companion-idle", "companion-walk-a", "companion-beat-sync",
    "companion-rediscovered", "companion-spark-step-a", "companion-beat-bounce-b",
    "companion-eating-a", "companion-sleeping-a",
  ]
  by_name = {item.name: item for item in items}
  items = [by_name[name] for name in featured]

  tile = (520, 200)
  gap = 14
  pad = 24
  width = pad * 2 + tile[0]
  height = 88 + len(items) * tile[1] + (len(items) - 1) * gap + pad
  sheet = Image.new("RGBA", (width, height), (6, 10, 12, 255))
  draw = ImageDraw.Draw(sheet)
  title_font = load_font(21, True)
  label_font = load_font(12, True)
  small_font = load_font(10)
  tiny_font = load_font(9)

  draw.text((pad, 28), "Dial Pet Bold Pass", font=title_font, fill=TEXT)
  draw.text((pad, 58), "actual HUD scale first, pet view scale second", font=small_font, fill=ACCENT)

  for idx, item in enumerate(items):
    x = pad
    y = 88 + idx * (tile[1] + gap)
    draw.rounded_rectangle((x, y, x + tile[0], y + tile[1]), radius=8, fill=SURFACE, outline=(48, 60, 66, 255), width=1)
    source = Image.open(source_dir / f"{item.name}.png").convert("RGBA")
    output = Image.open(frames_dir / f"{item.name}.png").convert("RGBA")

    lcd_top = y + 12
    lcd_h = 104
    panel_gap = 8
    panel_w = (tile[0] - 24 - panel_gap * 3) // 4
    rects = []
    left = x + 12
    for _ in range(4):
      rects.append((left, lcd_top, left + panel_w, lcd_top + lcd_h))
      left += panel_w + panel_gap

    draw_lcd(sheet, rects[0], source, PREVIEW_HEIGHTS[0], "47 before", tiny_font)
    draw_lcd(sheet, rects[1], output, PREVIEW_HEIGHTS[0], "47 bold", tiny_font)
    draw_lcd(sheet, rects[2], source, PREVIEW_HEIGHTS[1], "88 before", tiny_font)
    draw_lcd(sheet, rects[3], output, PREVIEW_HEIGHTS[1], "88 bold", tiny_font)

    label_y = rects[0][3] + 8
    draw.text((x + 12, label_y), item.name, font=label_font, fill=TEXT)
    draw.text(
      (x + 12, label_y + 18),
      f"art {item.source_visible[0]}x{item.source_visible[1]} -> {item.output_visible[0]}x{item.output_visible[1]} · kernel {item.stroke_kernel}",
      font=small_font,
      fill=MUTED,
    )
    draw.text((x + 12, label_y + 34), "heavier source mask, same canvas", font=small_font, fill=ACCENT)

  out_path.parent.mkdir(parents=True, exist_ok=True)
  sheet.convert("RGB").save(out_path, quality=95)


def main() -> None:
  parser = argparse.ArgumentParser(description="Bolden Dial pet sprites for small HUD rendering.")
  parser.add_argument("--source-dir", type=Path, default=SOURCE_DIR)
  parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
  parser.add_argument("--stroke-kernel", type=int, default=5)
  args = parser.parse_args()

  if args.stroke_kernel % 2 == 0 or args.stroke_kernel < 3:
    raise SystemExit("--stroke-kernel must be an odd integer >= 3")

  source_dir = args.source_dir.expanduser().resolve()
  out_dir = args.out_dir.expanduser().resolve()
  frames_dir = out_dir / "frames"
  frames_dir.mkdir(parents=True, exist_ok=True)

  for png in source_dir.glob("*.png"):
    shutil.copy2(png, frames_dir / png.name)

  items = [bolden_sprite(name, source_dir, frames_dir, args.stroke_kernel) for name in SPRITES]
  report_path = out_dir / "pet-bold-pass-report.json"
  review_path = out_dir / "pet-bold-pass-review.png"
  report_path.write_text(json.dumps([asdict(item) for item in items], indent=2) + "\n")
  render_review(items, source_dir, frames_dir, review_path)

  print(f"Frames:       {frames_dir}")
  print(f"Review sheet: {review_path}")
  print(f"Report JSON:  {report_path}")
  print(f"Boldened:     {len(items)} frames, kernel {args.stroke_kernel}")


if __name__ == "__main__":
  main()
