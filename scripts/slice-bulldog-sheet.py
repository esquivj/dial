#!/usr/bin/env python3
"""
Slice the bulldog sprite sheet into individual transparent PNGs.

Paper's image-gen rendered "transparency" as a solid light-gray fill
(RGB ≈ 238/238/238) — alpha is 255 everywhere. So we:
  1) chroma-key the gray background → real alpha = 0
  2) detect sprite bounding boxes via the now-real alpha channel
  3) crop each cell with a small padding margin
  4) save as individual PNGs with semantic names

Output order (matches Dial's state model):
  Row 1 — lifecycle:   egg, hatching, hatchling, juvenile, companion, elder
  Row 2 — behaviors:   companion-idle, companion-beat-sync, companion-first-listen,
                       companion-rediscovered, companion-paused, companion-paused-b,
                       companion-dormant
  Row 3 — animations:  companion-walk-a, companion-walk-b,
                       companion-eating-a, companion-eating-b,
                       companion-sleeping-a, companion-sleeping-b
"""

from PIL import Image
from pathlib import Path
import sys

SHEET = Path(__file__).resolve().parent / "sprite-sources/bulldog-sheet.png"
OUT_DIR = Path(__file__).resolve().parent.parent / "Dial/Resources/Pets"

NAMES = [
    ["egg", "hatching", "hatchling", "juvenile", "companion", "elder"],
    ["companion-idle", "companion-beat-sync", "companion-first-listen",
     "companion-rediscovered", "companion-paused", "companion-dormant"],
    ["companion-walk-a", "companion-walk-b",
     "companion-eating-a", "companion-eating-b",
     "companion-sleeping-a", "companion-sleeping-b"],
]


def find_runs(presence):
    runs, in_run, start = [], False, 0
    for i, p in enumerate(presence):
        if p and not in_run:
            in_run, start = True, i
        elif not p and in_run:
            in_run = False
            runs.append((start, i - 1))
    if in_run:
        runs.append((start, len(presence) - 1))
    return runs


def merge_close_runs(runs, gap_threshold):
    if not runs:
        return runs
    merged = [runs[0]]
    for start, end in runs[1:]:
        prev_start, prev_end = merged[-1]
        if start - prev_end <= gap_threshold:
            merged[-1] = (prev_start, end)
        else:
            merged.append((start, end))
    return merged


def is_background(r, g, b, a):
    """The 'transparent' areas in this sheet are actually solid pale gray
    around (238,238,238). Treat any pixel that's near-neutral and very
    light as background."""
    if a < 8:
        return True
    # Near-neutral (R, G, B all close)
    if abs(r - g) < 12 and abs(g - b) < 12 and abs(r - b) < 12:
        # Bright enough to be the gray background, not e.g. the dark eye
        if min(r, g, b) >= 215:
            return True
    return False


def chroma_key(img):
    """Return a copy of the image with background gray replaced by alpha=0."""
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if is_background(r, g, b, a):
                px[x, y] = (0, 0, 0, 0)
    return img


def main():
    if not SHEET.exists():
        print(f"sheet not found: {SHEET}", file=sys.stderr)
        sys.exit(1)

    img = Image.open(SHEET).convert("RGBA")
    w, h = img.size
    print(f"Loaded {SHEET.name}  {w}×{h}")

    # 1) Replace background gray with true transparency.
    img = chroma_key(img)
    a = img.split()[-1]
    A_MIN = 32

    # Save the keyed full sheet next to the source for debugging / reuse.
    keyed_path = SHEET.with_name("bulldog-sheet-keyed.png")
    img.save(keyed_path, optimize=True)
    print(f"Saved chroma-keyed sheet: {keyed_path}")

    # 2) Detect rows.
    a_pixels = a.load()
    row_presence = []
    for y in range(h):
        any_pixel = False
        for x in range(w):
            if a_pixels[x, y] > A_MIN:
                any_pixel = True
                break
        row_presence.append(any_pixel)

    raw_rows = find_runs(row_presence)
    rows = merge_close_runs(raw_rows, gap_threshold=15)
    print(f"Detected {len(rows)} sprite rows: {rows}")

    if len(rows) != 3:
        print(f"Expected 3 rows, got {len(rows)}.", file=sys.stderr)
        sys.exit(2)

    PADDING = 6
    saved = 0

    for row_idx, (y0, y1) in enumerate(rows):
        # Per-row column scan (only inside this row's vertical band).
        band_cols = []
        for x in range(w):
            any_pixel = False
            for y in range(y0, y1 + 1):
                if a_pixels[x, y] > A_MIN:
                    any_pixel = True
                    break
            band_cols.append(any_pixel)
        raw_cols = find_runs(band_cols)
        cols = merge_close_runs(raw_cols, gap_threshold=18)

        names = NAMES[row_idx] if row_idx < len(NAMES) else None
        print(f"\nRow {row_idx+1}: {len(cols)} cells", end="")
        if names:
            print(f" (expected {len(names)})")
            if len(cols) != len(names):
                print(f"  raw runs: {raw_cols}", file=sys.stderr)
                print(f"  merged runs: {cols}", file=sys.stderr)
        else:
            print()

        for col_idx, (x0, x1) in enumerate(cols):
            crop_x0 = max(0, x0 - PADDING)
            crop_y0 = max(0, y0 - PADDING)
            crop_x1 = min(w, x1 + 1 + PADDING)
            crop_y1 = min(h, y1 + 1 + PADDING)
            crop = img.crop((crop_x0, crop_y0, crop_x1, crop_y1))

            name = names[col_idx] if names and col_idx < len(names) else f"row{row_idx+1}-extra-{col_idx+1}"
            out = OUT_DIR / f"{name}.png"
            crop.save(out, optimize=True)
            print(f"  → {out.name:36s}  ({crop.size[0]}×{crop.size[1]})")
            saved += 1

    print(f"\nDone. Saved {saved} sprite files to {OUT_DIR}")


if __name__ == "__main__":
    main()
