#!/usr/bin/env python3
"""
Refine the six generated trick sprites so they match the core pet better.

The generated trick sheet was usable, but the frames landed too small and
thin next to the original Dial pet. This pass keeps the poses, preserves
pixel crispness, scales the visible art to the same app-size family as the
core companion, and adds one pixel of line weight.
"""

from __future__ import annotations

import argparse
import json
import shutil
from dataclasses import asdict, dataclass
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "Dial/Resources/Pets"
DEFAULT_OUT_DIR = ROOT / "output/pet-trick-art-pass"

CANONICAL_CANVAS = (559, 559)
LCD_BG = (215, 217, 169, 255)
SURFACE = (12, 19, 23, 255)
TEXT = (226, 238, 240, 255)
MUTED = (143, 153, 160, 255)
ACCENT = (35, 183, 245, 255)

TRICK_CONFIG: dict[str, tuple[int, int]] = {
  "companion-spark-step-a": (420, 486),
  "companion-spark-step-b": (420, 486),
  "companion-memory-spin-a": (420, 486),
  "companion-memory-spin-b": (420, 486),
  "companion-beat-bounce-a": (404, 472),
  "companion-beat-bounce-b": (420, 486),
}


@dataclass
class TrickRefinement:
  name: str
  source_bounds: tuple[int, int, int, int]
  output_bounds: tuple[int, int, int, int]
  source_visible: tuple[int, int]
  output_visible: tuple[int, int]
  target_height: int
  target_bottom: int


def alpha_bounds(img: Image.Image) -> tuple[int, int, int, int]:
  bounds = img.convert("RGBA").split()[-1].getbbox()
  if bounds is None:
    raise ValueError("empty sprite")
  return bounds


def display_path(path: Path) -> str:
  try:
    return str(path.relative_to(ROOT))
  except ValueError:
    return str(path)


def refine_sprite(name: str, source_dir: Path, frames_dir: Path) -> TrickRefinement:
  target_height, target_bottom = TRICK_CONFIG[name]
  source_path = source_dir / f"{name}.png"
  output_path = frames_dir / f"{name}.png"

  img = Image.open(source_path).convert("RGBA")
  bounds = alpha_bounds(img)
  x0, y0, x1, y1 = bounds
  visible = (x1 - x0, y1 - y0)
  crop = img.crop(bounds)

  scale = target_height / visible[1]
  target_width = min(CANONICAL_CANVAS[0] - 2, max(1, round(visible[0] * scale)))
  if target_width == CANONICAL_CANVAS[0] - 2:
    target_height = max(1, round(visible[1] * (target_width / visible[0])))

  resized = crop.resize((target_width, target_height), Image.Resampling.NEAREST)
  alpha = resized.split()[-1].point(lambda px: 255 if px > 20 else 0)
  alpha = alpha.filter(ImageFilter.MaxFilter(3))

  # Keep the generated poses, but make the line language match the core pet:
  # pure black pixels, no antialias haze, one-pixel heavier strokes.
  refined = Image.new("RGBA", resized.size, (0, 0, 0, 0))
  black = Image.new("RGBA", resized.size, (0, 0, 0, 255))
  refined = Image.composite(black, refined, alpha)

  center_ratio = ((x0 + x1) / 2) / img.size[0]
  target_center_x = center_ratio * CANONICAL_CANVAS[0]
  paste_x = round(target_center_x - refined.size[0] / 2)
  paste_y = round(target_bottom - refined.size[1])
  paste_x = min(max(0, paste_x), CANONICAL_CANVAS[0] - refined.size[0])
  paste_y = min(max(0, paste_y), CANONICAL_CANVAS[1] - refined.size[1])

  output = Image.new("RGBA", CANONICAL_CANVAS, (0, 0, 0, 0))
  output.alpha_composite(refined, (paste_x, paste_y))
  output.save(output_path)

  output_bounds = alpha_bounds(output)
  ox0, oy0, ox1, oy1 = output_bounds
  return TrickRefinement(
    name=name,
    source_bounds=bounds,
    output_bounds=output_bounds,
    source_visible=visible,
    output_visible=(ox1 - ox0, oy1 - oy0),
    target_height=target_height,
    target_bottom=target_bottom,
  )


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


def draw_lcd(
  sheet: Image.Image,
  rect: tuple[int, int, int, int],
  img: Image.Image,
  label: str,
  font: ImageFont.ImageFont,
) -> None:
  draw = ImageDraw.Draw(sheet)
  draw.rounded_rectangle(rect, radius=5, fill=LCD_BG)
  cx = (rect[0] + rect[2]) // 2
  cy = (rect[1] + rect[3]) // 2
  draw.line((cx, rect[1] + 5, cx, rect[3] - 5), fill=(180, 183, 143, 255), width=1)
  draw.line((rect[0] + 5, cy, rect[2] - 5, cy), fill=(180, 183, 143, 255), width=1)
  preview = resize_full_canvas(img, 104)
  px = rect[0] + (rect[2] - rect[0] - preview.size[0]) // 2
  py = rect[1] + (rect[3] - rect[1] - preview.size[1]) // 2
  sheet.alpha_composite(preview, (px, py))
  draw.text((rect[0] + 8, rect[3] - 18), label, font=font, fill=(49, 58, 48, 255))


def render_review(items: list[TrickRefinement], source_dir: Path, frames_dir: Path, out_path: Path) -> None:
  cols = 2
  tile = (420, 202)
  gap = 14
  pad = 24
  width = pad * 2 + cols * tile[0] + (cols - 1) * gap
  rows = (len(items) + cols - 1) // cols
  height = 86 + rows * tile[1] + (rows - 1) * gap + pad
  sheet = Image.new("RGBA", (width, height), (6, 10, 12, 255))
  draw = ImageDraw.Draw(sheet)
  title_font = load_font(21, True)
  label_font = load_font(12, True)
  small_font = load_font(10)
  tiny_font = load_font(9)

  draw.text((pad, 28), "Dial Trick Sprite Art Pass", font=title_font, fill=TEXT)
  draw.text((pad, 58), "before / refined at app preview scale", font=small_font, fill=ACCENT)

  for idx, item in enumerate(items):
    row = idx // cols
    col = idx % cols
    x = pad + col * (tile[0] + gap)
    y = 86 + row * (tile[1] + gap)
    draw.rounded_rectangle((x, y, x + tile[0], y + tile[1]), radius=8, fill=SURFACE, outline=(48, 60, 66, 255), width=1)

    lcd_top = y + 12
    lcd_h = 126
    panel_gap = 10
    panel_w = (tile[0] - 24 - panel_gap) // 2
    left = (x + 12, lcd_top, x + 12 + panel_w, lcd_top + lcd_h)
    right = (left[2] + panel_gap, lcd_top, x + tile[0] - 12, lcd_top + lcd_h)
    before = Image.open(source_dir / f"{item.name}.png").convert("RGBA")
    after = Image.open(frames_dir / f"{item.name}.png").convert("RGBA")
    draw_lcd(sheet, left, before, "before", tiny_font)
    draw_lcd(sheet, right, after, "refined", tiny_font)

    label_y = left[3] + 8
    draw.text((x + 12, label_y), item.name, font=label_font, fill=TEXT)
    draw.text(
      (x + 12, label_y + 18),
      f"art {item.source_visible[0]}x{item.source_visible[1]} -> {item.output_visible[0]}x{item.output_visible[1]}",
      font=small_font,
      fill=MUTED,
    )
    draw.text((x + 12, label_y + 34), "larger, heavier, canonical", font=small_font, fill=ACCENT)

  out_path.parent.mkdir(parents=True, exist_ok=True)
  sheet.convert("RGB").save(out_path, quality=95)


def main() -> None:
  parser = argparse.ArgumentParser(description="Refine generated Dial pet trick sprites.")
  parser.add_argument("--source-dir", type=Path, default=SOURCE_DIR)
  parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
  args = parser.parse_args()

  source_dir = args.source_dir.expanduser().resolve()
  out_dir = args.out_dir.expanduser().resolve()
  frames_dir = out_dir / "frames"
  frames_dir.mkdir(parents=True, exist_ok=True)

  for png in source_dir.glob("*.png"):
    shutil.copy2(png, frames_dir / png.name)

  items = [refine_sprite(name, source_dir, frames_dir) for name in TRICK_CONFIG]
  report_path = out_dir / "pet-trick-art-pass-report.json"
  review_path = out_dir / "pet-trick-art-pass-review.png"
  report_path.write_text(json.dumps([asdict(item) for item in items], indent=2) + "\n")
  render_review(items, source_dir, frames_dir, review_path)

  print(f"Frames:       {frames_dir}")
  print(f"Review sheet: {review_path}")
  print(f"Report JSON:  {report_path}")
  print(f"Refined:      {len(items)} trick frames")


if __name__ == "__main__":
  main()
