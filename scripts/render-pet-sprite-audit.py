#!/usr/bin/env python3
"""
Render a contact-sheet audit of every pet sprite.

The app renders pet frames with SwiftUI's `.scaledToFit().frame(height:)`.
That means canvas size and transparent padding directly affect perceived
sprite size. This script previews the assets the same way: each full PNG is
scaled to one fixed frame height, then placed inside a common LCD tile.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
PETS_DIR = ROOT / "Dial/Resources/Pets"
DEFAULT_OUT_DIR = ROOT / "output/pet-sprite-audit"

CANONICAL_CANVAS = (559, 559)
LCD_BG = (215, 217, 169, 255)
SURFACE = (12, 19, 23, 255)
TEXT = (226, 238, 240, 255)
MUTED = (143, 153, 160, 255)
ACCENT = (35, 183, 245, 255)
WARN = (255, 82, 210, 255)
BLACK = (0, 0, 0, 255)

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
class SpriteAudit:
  name: str
  path: str
  canvas: tuple[int, int] | None
  bounds: tuple[int, int, int, int] | None
  visible_size: tuple[int, int] | None
  center_offset: tuple[float, float] | None
  baseline: int | None
  warnings: list[str]


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


def alpha_bounds(img: Image.Image) -> tuple[int, int, int, int] | None:
  alpha = img.convert("RGBA").split()[-1]
  return alpha.getbbox()


def display_path(path: Path) -> str:
  try:
    return str(path.relative_to(ROOT))
  except ValueError:
    return str(path)


def image_path(path_text: str) -> Path:
  path = Path(path_text)
  if path.is_absolute():
    return path
  return ROOT / path


def audit_sprite(name: str, pets_dir: Path) -> SpriteAudit:
  path = pets_dir / f"{name}.png"
  if not path.exists():
    return SpriteAudit(
      name=name,
      path=display_path(path),
      canvas=None,
      bounds=None,
      visible_size=None,
      center_offset=None,
      baseline=None,
      warnings=["missing"],
    )

  img = Image.open(path).convert("RGBA")
  bounds = alpha_bounds(img)
  warnings: list[str] = []
  if img.size != CANONICAL_CANVAS:
    warnings.append(f"canvas {img.size[0]}x{img.size[1]}")
  if bounds is None:
    warnings.append("empty")
    return SpriteAudit(name, display_path(path), img.size, None, None, None, None, warnings)

  x0, y0, x1, y1 = bounds
  visible = (x1 - x0, y1 - y0)
  center_x = (x0 + x1) / 2
  center_y = (y0 + y1) / 2
  offset = (round(center_x - img.size[0] / 2, 1), round(center_y - img.size[1] / 2, 1))
  baseline = img.size[1] - y1

  if abs(offset[0]) > img.size[0] * 0.10:
    warnings.append(f"x offset {offset[0]:g}")
  if baseline > img.size[1] * 0.35:
    warnings.append(f"high baseline {baseline}")
  if visible[1] < img.size[1] * 0.32:
    warnings.append(f"small art {visible[1]}")

  return SpriteAudit(
    name=name,
    path=display_path(path),
    canvas=img.size,
    bounds=bounds,
    visible_size=visible,
    center_offset=offset,
    baseline=baseline,
    warnings=warnings,
  )


def resize_full_canvas(img: Image.Image, target_height: int) -> Image.Image:
  scale = target_height / img.size[1]
  width = max(1, round(img.size[0] * scale))
  return img.resize((width, target_height), Image.Resampling.NEAREST)


def draw_tile(
  sheet: Image.Image,
  xy: tuple[int, int],
  audit: SpriteAudit,
  sprite_height: int,
  tile_size: tuple[int, int],
  fonts: dict[str, ImageFont.ImageFont],
) -> None:
  x, y = xy
  tile_w, tile_h = tile_size
  draw = ImageDraw.Draw(sheet)

  draw.rounded_rectangle((x, y, x + tile_w, y + tile_h), radius=8, fill=SURFACE, outline=(48, 60, 66, 255), width=1)
  lcd = (x + 12, y + 12, x + tile_w - 12, y + 12 + sprite_height + 22)
  draw.rounded_rectangle(lcd, radius=5, fill=LCD_BG)
  cx = (lcd[0] + lcd[2]) // 2
  cy = (lcd[1] + lcd[3]) // 2
  draw.line((cx, lcd[1] + 5, cx, lcd[3] - 5), fill=(180, 183, 143, 255), width=1)
  draw.line((lcd[0] + 5, cy, lcd[2] - 5, cy), fill=(180, 183, 143, 255), width=1)

  if audit.canvas is not None:
    img = Image.open(image_path(audit.path)).convert("RGBA")
    preview = resize_full_canvas(img, sprite_height)
    px = x + (tile_w - preview.size[0]) // 2
    py = lcd[1] + (lcd[3] - lcd[1] - preview.size[1]) // 2
    sheet.alpha_composite(preview, (px, py))
  else:
    msg = "MISSING"
    tw, th = text_size(draw, msg, fonts["label"])
    draw.text((x + (tile_w - tw) / 2, y + 52), msg, font=fonts["label"], fill=WARN)

  label_y = lcd[3] + 8
  draw.text((x + 12, label_y), audit.name, font=fonts["label"], fill=TEXT)
  meta = "missing"
  if audit.canvas is not None:
    meta = f"{audit.canvas[0]}x{audit.canvas[1]}"
    if audit.visible_size:
      meta += f" / art {audit.visible_size[0]}x{audit.visible_size[1]}"
  draw.text((x + 12, label_y + 18), meta, font=fonts["small"], fill=MUTED)
  if audit.warnings:
    warn_text = " | ".join(audit.warnings[:2])
    draw.text((x + 12, label_y + 34), warn_text, font=fonts["small"], fill=WARN)
  else:
    draw.text((x + 12, label_y + 34), "canonical", font=fonts["small"], fill=ACCENT)


def render_contact_sheet(audits_by_group: list[tuple[str, list[SpriteAudit]]], out: Path, sprite_height: int) -> None:
  cols = 4
  tile = (252, 188)
  gap = 14
  left = 24
  top = 28
  group_gap = 52
  header_h = 34
  width = left * 2 + cols * tile[0] + (cols - 1) * gap
  height = top
  for _, audits in audits_by_group:
    rows = (len(audits) + cols - 1) // cols
    height += header_h + rows * tile[1] + (rows - 1) * gap + group_gap

  sheet = Image.new("RGBA", (width, height), (6, 10, 12, 255))
  draw = ImageDraw.Draw(sheet)
  fonts = {
    "title": load_font(22, bold=True),
    "group": load_font(16, bold=True),
    "label": load_font(12, bold=True),
    "small": load_font(10),
  }
  title = f"Dial Pet Sprite Audit · app preview height {sprite_height}px · canonical {CANONICAL_CANVAS[0]}x{CANONICAL_CANVAS[1]}"
  draw.text((left, top), title, font=fonts["title"], fill=TEXT)
  y = top + 44

  for group, audits in audits_by_group:
    warnings = sum(1 for audit in audits if audit.warnings)
    detail = f"{group} · {len(audits)} frames · {warnings} flagged"
    draw.text((left, y), detail, font=fonts["group"], fill=ACCENT if warnings == 0 else TEXT)
    y += header_h
    for idx, audit in enumerate(audits):
      row = idx // cols
      col = idx % cols
      x = left + col * (tile[0] + gap)
      ty = y + row * (tile[1] + gap)
      draw_tile(sheet, (x, ty), audit, sprite_height, tile, fonts)
    rows = (len(audits) + cols - 1) // cols
    y += rows * tile[1] + (rows - 1) * gap + group_gap

  out.parent.mkdir(parents=True, exist_ok=True)
  sheet.convert("RGB").save(out, quality=95)


def flatten(groups: Iterable[tuple[str, list[str]]]) -> list[str]:
  out: list[str] = []
  for _, names in groups:
    out.extend(names)
  return out


def main() -> None:
  parser = argparse.ArgumentParser(description="Render Dial pet sprite audit contact sheet.")
  parser.add_argument("--pets-dir", type=Path, default=PETS_DIR)
  parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
  parser.add_argument("--sprite-height", type=int, default=104)
  args = parser.parse_args()

  pets_dir = args.pets_dir.expanduser().resolve()
  audits_by_group = [(group, [audit_sprite(name, pets_dir) for name in names]) for group, names in GROUPS]
  all_audits = [audit for _, audits in audits_by_group for audit in audits]

  out_dir = args.out_dir
  out_dir.mkdir(parents=True, exist_ok=True)
  sheet_path = out_dir / "pet-sprite-contact-sheet.png"
  json_path = out_dir / "pet-sprite-audit.json"

  render_contact_sheet(audits_by_group, sheet_path, args.sprite_height)
  json_path.write_text(json.dumps([asdict(audit) for audit in all_audits], indent=2) + "\n")

  expected = set(flatten(GROUPS))
  extras = sorted(
    p.stem for p in pets_dir.glob("*.png")
    if p.stem not in expected and not p.stem.endswith("-sheet")
  )
  flagged = [audit for audit in all_audits if audit.warnings]

  print(f"Contact sheet: {sheet_path}")
  print(f"Audit JSON:    {json_path}")
  print(f"Frames:        {len(all_audits)} expected, {len(flagged)} flagged")
  if extras:
    print(f"Extra PNGs:     {', '.join(extras)}")
  if flagged:
    print("\nFlagged:")
    for audit in flagged:
      print(f"  {audit.name:28s} {', '.join(audit.warnings)}")


if __name__ == "__main__":
  main()
