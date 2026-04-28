#!/usr/bin/env python3
"""
Normalize Dial pet sprite canvases without changing the live app assets.

SwiftUI renders these PNGs with `.scaledToFit().frame(height:)`, so a
sprite's full canvas height controls the apparent art size. This script
rewraps every visible sprite into a canonical 559x559 transparent canvas
while preserving the current on-screen scale and baseline as closely as
pixel rounding allows.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "Dial/Resources/Pets"
DEFAULT_OUT_DIR = ROOT / "output/pet-sprite-normalized"

CANONICAL_CANVAS = (559, 559)
PREVIEW_HEIGHT = 104
SURFACE = (12, 19, 23, 255)
LCD_BG = (215, 217, 169, 255)
TEXT = (226, 238, 240, 255)
MUTED = (143, 153, 160, 255)
ACCENT = (35, 183, 245, 255)
WARN = (255, 82, 210, 255)

GROUPS: list[tuple[str, list[str]]] = [
  ("Lifecycle", [
    "egg", "hatching", "hatchling", "juvenile", "companion", "elder",
  ]),
  ("Companion Core", [
    "companion-idle", "companion-idle-blink", "companion-walk-a",
    "companion-walk-b", "companion-beat-sync", "companion-first-listen",
    "companion-rediscovered", "companion-paused", "companion-dormant",
    "companion-level-up",
  ]),
  ("Companion Loops", [
    "companion-eating-a", "companion-eating-b", "companion-sleeping-a",
    "companion-sleeping-b",
  ]),
  ("Tricks", [
    "companion-spark-step-a", "companion-spark-step-b",
    "companion-memory-spin-a", "companion-memory-spin-b",
    "companion-beat-bounce-a", "companion-beat-bounce-b",
  ]),
]


@dataclass
class Normalization:
  name: str
  source_path: str
  output_path: str
  source_canvas: tuple[int, int] | None
  source_bounds: tuple[int, int, int, int] | None
  source_visible: tuple[int, int] | None
  output_canvas: tuple[int, int] | None
  output_bounds: tuple[int, int, int, int] | None
  output_visible: tuple[int, int] | None
  source_screen_visible: tuple[float, float] | None
  output_screen_visible: tuple[float, float] | None
  scale: float | None
  warnings: list[str]


def flatten(groups: Iterable[tuple[str, list[str]]]) -> list[str]:
  names: list[str] = []
  for _, group_names in groups:
    names.extend(group_names)
  return names


def display_path(path: Path) -> str:
  try:
    return str(path.relative_to(ROOT))
  except ValueError:
    return str(path)


def alpha_bounds(img: Image.Image) -> tuple[int, int, int, int] | None:
  return img.convert("RGBA").split()[-1].getbbox()


def screen_visible(visible: tuple[int, int], canvas_height: int, preview_height: int) -> tuple[float, float]:
  width, height = visible
  scale = preview_height / canvas_height
  return (round(width * scale, 2), round(height * scale, 2))


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


def text_size(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont) -> tuple[int, int]:
  box = draw.textbbox((0, 0), text, font=font)
  return box[2] - box[0], box[3] - box[1]


def resize_full_canvas(img: Image.Image, target_height: int) -> Image.Image:
  scale = target_height / img.size[1]
  width = max(1, round(img.size[0] * scale))
  return img.resize((width, target_height), Image.Resampling.NEAREST)


def normalize_sprite(name: str, source_dir: Path, frames_dir: Path, preview_height: int) -> Normalization:
  source_path = source_dir / f"{name}.png"
  output_path = frames_dir / f"{name}.png"
  warnings: list[str] = []

  if not source_path.exists():
    return Normalization(
      name=name,
      source_path=display_path(source_path),
      output_path=display_path(output_path),
      source_canvas=None,
      source_bounds=None,
      source_visible=None,
      output_canvas=None,
      output_bounds=None,
      output_visible=None,
      source_screen_visible=None,
      output_screen_visible=None,
      scale=None,
      warnings=["missing"],
    )

  img = Image.open(source_path).convert("RGBA")
  bounds = alpha_bounds(img)
  if bounds is None:
    output = Image.new("RGBA", CANONICAL_CANVAS, (0, 0, 0, 0))
    output.save(output_path)
    return Normalization(
      name=name,
      source_path=display_path(source_path),
      output_path=display_path(output_path),
      source_canvas=img.size,
      source_bounds=None,
      source_visible=None,
      output_canvas=output.size,
      output_bounds=None,
      output_visible=None,
      source_screen_visible=None,
      output_screen_visible=None,
      scale=None,
      warnings=["empty"],
    )

  x0, y0, x1, y1 = bounds
  visible = (x1 - x0, y1 - y0)
  scale = CANONICAL_CANVAS[1] / img.size[1]
  target_width = max(1, round(visible[0] * scale))
  target_height = max(1, round(visible[1] * scale))

  max_width = CANONICAL_CANVAS[0] - 2
  max_height = CANONICAL_CANVAS[1] - 2
  if target_width > max_width or target_height > max_height:
    clamp = min(max_width / target_width, max_height / target_height)
    target_width = max(1, round(target_width * clamp))
    target_height = max(1, round(target_height * clamp))
    warnings.append("clamped")

  crop = img.crop(bounds)
  resized = crop.resize((target_width, target_height), Image.Resampling.NEAREST)

  center_ratio = ((x0 + x1) / 2) / img.size[0]
  bottom_margin_ratio = (img.size[1] - y1) / img.size[1]
  target_center_x = center_ratio * CANONICAL_CANVAS[0]
  target_bottom = CANONICAL_CANVAS[1] - (bottom_margin_ratio * CANONICAL_CANVAS[1])

  paste_x = round(target_center_x - target_width / 2)
  paste_y = round(target_bottom - target_height)
  clamped_x = min(max(0, paste_x), CANONICAL_CANVAS[0] - target_width)
  clamped_y = min(max(0, paste_y), CANONICAL_CANVAS[1] - target_height)
  if (clamped_x, clamped_y) != (paste_x, paste_y):
    warnings.append("position clamped")

  output = Image.new("RGBA", CANONICAL_CANVAS, (0, 0, 0, 0))
  output.alpha_composite(resized, (clamped_x, clamped_y))
  output.save(output_path)

  output_bounds = alpha_bounds(output)
  output_visible = None
  output_screen = None
  if output_bounds is not None:
    ox0, oy0, ox1, oy1 = output_bounds
    output_visible = (ox1 - ox0, oy1 - oy0)
    output_screen = screen_visible(output_visible, CANONICAL_CANVAS[1], preview_height)

  return Normalization(
    name=name,
    source_path=display_path(source_path),
    output_path=display_path(output_path),
    source_canvas=img.size,
    source_bounds=bounds,
    source_visible=visible,
    output_canvas=output.size,
    output_bounds=output_bounds,
    output_visible=output_visible,
    source_screen_visible=screen_visible(visible, img.size[1], preview_height),
    output_screen_visible=output_screen,
    scale=round(scale, 4),
    warnings=warnings,
  )


def draw_lcd(
  sheet: Image.Image,
  rect: tuple[int, int, int, int],
  img: Image.Image | None,
  preview_height: int,
  label: str,
  fonts: dict[str, ImageFont.ImageFont],
) -> None:
  draw = ImageDraw.Draw(sheet)
  draw.rounded_rectangle(rect, radius=5, fill=LCD_BG)
  cx = (rect[0] + rect[2]) // 2
  cy = (rect[1] + rect[3]) // 2
  draw.line((cx, rect[1] + 5, cx, rect[3] - 5), fill=(180, 183, 143, 255), width=1)
  draw.line((rect[0] + 5, cy, rect[2] - 5, cy), fill=(180, 183, 143, 255), width=1)
  if img is not None:
    preview = resize_full_canvas(img, preview_height)
    px = rect[0] + (rect[2] - rect[0] - preview.size[0]) // 2
    py = rect[1] + (rect[3] - rect[1] - preview.size[1]) // 2
    sheet.alpha_composite(preview, (px, py))
  draw.text((rect[0] + 8, rect[3] - 18), label, font=fonts["tiny"], fill=(49, 58, 48, 255))


def draw_review_tile(
  sheet: Image.Image,
  xy: tuple[int, int],
  item: Normalization,
  source_dir: Path,
  frames_dir: Path,
  preview_height: int,
  tile_size: tuple[int, int],
  fonts: dict[str, ImageFont.ImageFont],
) -> None:
  x, y = xy
  tile_w, tile_h = tile_size
  draw = ImageDraw.Draw(sheet)
  draw.rounded_rectangle((x, y, x + tile_w, y + tile_h), radius=8, fill=SURFACE, outline=(48, 60, 66, 255), width=1)

  lcd_top = y + 12
  lcd_h = preview_height + 22
  panel_gap = 10
  panel_w = (tile_w - 24 - panel_gap) // 2
  left = (x + 12, lcd_top, x + 12 + panel_w, lcd_top + lcd_h)
  right = (left[2] + panel_gap, lcd_top, x + tile_w - 12, lcd_top + lcd_h)

  source_img = None
  output_img = None
  source_path = source_dir / f"{item.name}.png"
  output_path = frames_dir / f"{item.name}.png"
  if source_path.exists():
    source_img = Image.open(source_path).convert("RGBA")
  if output_path.exists():
    output_img = Image.open(output_path).convert("RGBA")

  draw_lcd(sheet, left, source_img, preview_height, "before", fonts)
  draw_lcd(sheet, right, output_img, preview_height, "normalized", fonts)

  label_y = left[3] + 8
  draw.text((x + 12, label_y), item.name, font=fonts["label"], fill=TEXT)
  if item.source_canvas and item.output_canvas and item.source_visible and item.output_visible:
    meta = f"{item.source_canvas[0]}x{item.source_canvas[1]} -> {item.output_canvas[0]}x{item.output_canvas[1]}"
    art = f"art {item.source_visible[0]}x{item.source_visible[1]} -> {item.output_visible[0]}x{item.output_visible[1]}"
    draw.text((x + 12, label_y + 18), meta, font=fonts["small"], fill=MUTED)
    draw.text((x + 12, label_y + 34), art, font=fonts["small"], fill=MUTED)
  else:
    draw.text((x + 12, label_y + 18), "missing/empty", font=fonts["small"], fill=WARN)

  if item.warnings:
    draw.text((x + 12, label_y + 50), " | ".join(item.warnings), font=fonts["small"], fill=WARN)
  else:
    draw.text((x + 12, label_y + 50), "scale preserved", font=fonts["small"], fill=ACCENT)


def render_review_sheet(
  groups: list[tuple[str, list[Normalization]]],
  out_path: Path,
  source_dir: Path,
  frames_dir: Path,
  preview_height: int,
) -> None:
  cols = 3
  tile = (354, 214)
  gap = 14
  left = 24
  top = 28
  group_gap = 52
  header_h = 34
  width = left * 2 + cols * tile[0] + (cols - 1) * gap
  height = top
  for _, items in groups:
    rows = (len(items) + cols - 1) // cols
    height += header_h + rows * tile[1] + (rows - 1) * gap + group_gap

  sheet = Image.new("RGBA", (width, height), (6, 10, 12, 255))
  draw = ImageDraw.Draw(sheet)
  fonts = {
    "title": load_font(22, bold=True),
    "group": load_font(16, bold=True),
    "label": load_font(12, bold=True),
    "small": load_font(10),
    "tiny": load_font(9),
  }
  title = f"Dial Pet Sprite Normalization · preview {preview_height}px · output {CANONICAL_CANVAS[0]}x{CANONICAL_CANVAS[1]}"
  draw.text((left, top), title, font=fonts["title"], fill=TEXT)
  y = top + 44

  for group, items in groups:
    warning_count = sum(1 for item in items if item.warnings)
    draw.text(
      (left, y),
      f"{group} · {len(items)} frames · {warning_count} warnings",
      font=fonts["group"],
      fill=ACCENT if warning_count == 0 else TEXT,
    )
    y += header_h
    for idx, item in enumerate(items):
      row = idx // cols
      col = idx % cols
      x = left + col * (tile[0] + gap)
      ty = y + row * (tile[1] + gap)
      draw_review_tile(sheet, (x, ty), item, source_dir, frames_dir, preview_height, tile, fonts)
    rows = (len(items) + cols - 1) // cols
    y += rows * tile[1] + (rows - 1) * gap + group_gap

  out_path.parent.mkdir(parents=True, exist_ok=True)
  sheet.convert("RGB").save(out_path, quality=95)


def main() -> None:
  parser = argparse.ArgumentParser(description="Normalize Dial pet sprite canvases into a review folder.")
  parser.add_argument("--source-dir", type=Path, default=SOURCE_DIR)
  parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
  parser.add_argument("--preview-height", type=int, default=PREVIEW_HEIGHT)
  args = parser.parse_args()

  source_dir = args.source_dir.expanduser().resolve()
  out_dir = args.out_dir.expanduser().resolve()
  frames_dir = out_dir / "frames"
  frames_dir.mkdir(parents=True, exist_ok=True)

  groups: list[tuple[str, list[Normalization]]] = []
  all_items: list[Normalization] = []
  for group, names in GROUPS:
    items = [normalize_sprite(name, source_dir, frames_dir, args.preview_height) for name in names]
    groups.append((group, items))
    all_items.extend(items)

  report_path = out_dir / "pet-sprite-normalization-report.json"
  review_path = out_dir / "pet-sprite-normalization-review.png"
  report_path.write_text(json.dumps([asdict(item) for item in all_items], indent=2) + "\n")
  render_review_sheet(groups, review_path, source_dir, frames_dir, args.preview_height)

  extras = sorted(
    path.name for path in source_dir.glob("*.png")
    if path.stem not in set(flatten(GROUPS)) and not path.stem.endswith("-sheet")
  )
  warnings = [item for item in all_items if item.warnings]

  print(f"Frames:        {frames_dir}")
  print(f"Review sheet:  {review_path}")
  print(f"Report JSON:   {report_path}")
  print(f"Normalized:    {len(all_items)} frames, {len(warnings)} warnings")
  if extras:
    print(f"Extra PNGs:     {', '.join(extras)}")
  if warnings:
    print("\nWarnings:")
    for item in warnings:
      print(f"  {item.name:28s} {', '.join(item.warnings)}")


if __name__ == "__main__":
  main()
