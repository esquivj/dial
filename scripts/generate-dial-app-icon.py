#!/usr/bin/env python3
from __future__ import annotations

import json
import math
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
WORDMARK = ROOT / "Dial/Resources/Brand/dial-wordmark-chrome.png"
BRAND_DIR = ROOT / "Dial/Resources/Brand"
ICON_PNG = BRAND_DIR / "dial-app-icon.png"
ASSET_DIR = ROOT / "Dial/Assets.xcassets/AppIcon.appiconset"

CANVAS = 1024
INSET = 88
ICON_RECT = (INSET, INSET, CANVAS - INSET, CANVAS - INSET)
RADIUS = 198


def alpha_components(image: Image.Image) -> list[tuple[int, tuple[int, int, int, int], list[tuple[int, int]]]]:
    alpha = image.getchannel("A")
    width, height = alpha.size
    pixels = alpha.load()
    seen: set[tuple[int, int]] = set()
    components: list[tuple[int, tuple[int, int, int, int], list[tuple[int, int]]]] = []

    for y in range(height):
        for x in range(width):
            if pixels[x, y] <= 24 or (x, y) in seen:
                continue

            queue = deque([(x, y)])
            seen.add((x, y))
            min_x = max_x = x
            min_y = max_y = y
            area = 0
            points: list[tuple[int, int]] = []

            while queue:
                cx, cy = queue.pop()
                area += 1
                points.append((cx, cy))
                min_x = min(min_x, cx)
                max_x = max(max_x, cx)
                min_y = min(min_y, cy)
                max_y = max(max_y, cy)

                for nx in range(cx - 1, cx + 2):
                    for ny in range(cy - 1, cy + 2):
                        if nx < 0 or ny < 0 or nx >= width or ny >= height:
                            continue
                        if (nx, ny) in seen or pixels[nx, ny] <= 24:
                            continue
                        seen.add((nx, ny))
                        queue.append((nx, ny))

            if area > 50:
                components.append((area, (min_x, min_y, max_x + 1, max_y + 1), points))

    return components


def star_crops(wordmark: Image.Image) -> tuple[Image.Image, Image.Image]:
    components = alpha_components(wordmark)
    stars = [
        (box, points)
        for area, box, points in components
        if area < 12_000 and abs((box[2] - box[0]) - (box[3] - box[1])) < 18
    ]
    stars = sorted(stars, key=lambda item: item[0][0])
    if len(stars) < 2:
        raise RuntimeError("Could not isolate both wordmark sparkle components")

    padded: list[Image.Image] = []
    for box, points in (stars[0], stars[-1]):
        pad = 10
        crop_box = (
            max(0, box[0] - pad),
            max(0, box[1] - pad),
            min(wordmark.width, box[2] + pad),
            min(wordmark.height, box[3] + pad),
        )
        source = wordmark.crop(crop_box)
        mask = Image.new("L", source.size, 0)
        mask_pixels = mask.load()
        for px, py in points:
            mask_pixels[px - crop_box[0], py - crop_box[1]] = 255
        mask = mask.filter(ImageFilter.MaxFilter(3))
        isolated = Image.new("RGBA", source.size, (0, 0, 0, 0))
        isolated.paste(source, (0, 0), mask)
        padded.append(isolated)

    return padded[0], padded[1]


def sample_chrome_rows(wordmark: Image.Image, count: int = 220) -> list[tuple[int, int, int]]:
    bbox = wordmark.getchannel("A").getbbox()
    if bbox is None:
        raise RuntimeError("Wordmark has no visible pixels")

    crop = wordmark.crop(bbox)
    alpha = crop.getchannel("A")
    rgb = crop.convert("RGB")
    rows: list[tuple[int, int, int] | None] = []

    for y in range(crop.height):
        weighted = [0.0, 0.0, 0.0]
        total = 0.0
        for x in range(crop.width):
            a = alpha.getpixel((x, y))
            if a <= 18:
                continue
            r, g, b = rgb.getpixel((x, y))
            weighted[0] += r * a
            weighted[1] += g * a
            weighted[2] += b * a
            total += a
        if total > 0:
            rows.append(tuple(int(v / total) for v in weighted))
        else:
            rows.append(None)

    last = (215, 225, 236)
    forward: list[tuple[int, int, int]] = []
    for row in rows:
        if row is not None:
            last = row
        forward.append(last)

    last = forward[-1]
    for index in range(len(forward) - 1, -1, -1):
        if rows[index] is not None:
            last = rows[index]  # type: ignore[assignment]
        elif forward[index] == (215, 225, 236):
            forward[index] = last

    sampled: list[tuple[int, int, int]] = []
    for i in range(count):
        t = i / max(1, count - 1)
        sampled.append(forward[int(t * (len(forward) - 1))])
    return sampled


def blend(a: tuple[int, int, int], b: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    amount = max(0.0, min(1.0, amount))
    return tuple(int(a[i] * (1 - amount) + b[i] * amount) for i in range(3))


def chrome_plate(wordmark: Image.Image) -> Image.Image:
    rows = sample_chrome_rows(wordmark)
    plate_w = ICON_RECT[2] - ICON_RECT[0]
    plate_h = ICON_RECT[3] - ICON_RECT[1]
    plate = Image.new("RGBA", (plate_w, plate_h), (0, 0, 0, 0))
    px = plate.load()

    for y in range(plate_h):
        t = y / max(1, plate_h - 1)
        base = rows[int(t * (len(rows) - 1))]
        for x in range(plate_w):
            u = x / max(1, plate_w - 1)
            color = base

            top_sheen = max(0.0, 1.0 - abs(t - 0.18) / 0.20) * 0.30
            mid_sheen = max(0.0, 1.0 - abs(t - 0.47) / 0.12) * 0.20
            lower_shade = max(0.0, (t - 0.62) / 0.34) * 0.42
            diagonal = (math.sin((u * 2.4 + t * 1.15) * math.pi) + 1) * 0.5
            blue_lift = max(0.0, 1.0 - abs((u - t * 0.18) - 0.20) / 0.22) * 0.18

            color = blend(color, (248, 252, 255), top_sheen)
            color = blend(color, (235, 243, 252), mid_sheen * (0.35 + diagonal * 0.65))
            color = blend(color, (35, 45, 60), lower_shade)
            color = blend(color, (72, 170, 255), blue_lift)
            px[x, y] = (*color, 255)

    mask = Image.new("L", (CANVAS, CANVAS), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(ICON_RECT, radius=RADIUS, fill=255)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (INSET + 8, INSET - 8, CANVAS - INSET + 8, CANVAS - INSET - 8),
        radius=RADIUS,
        fill=(0, 0, 0, 84),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    canvas.alpha_composite(shadow)

    canvas.paste(plate, (INSET, INSET), mask.crop(ICON_RECT))

    overlay = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    d.rounded_rectangle(ICON_RECT, radius=RADIUS, outline=(255, 255, 255, 100), width=4)
    d.rounded_rectangle(
        (INSET + 9, INSET + 9, CANVAS - INSET - 9, CANVAS - INSET - 9),
        radius=RADIUS - 12,
        outline=(19, 83, 132, 92),
        width=4,
    )
    d.arc((INSET + 24, INSET + 20, CANVAS - INSET - 24, CANVAS - INSET + 220), 185, 355, fill=(255, 255, 255, 88), width=5)
    canvas.alpha_composite(overlay)
    return canvas


def resize_contain(image: Image.Image, target_height: int) -> Image.Image:
    scale = target_height / image.height
    target = (round(image.width * scale), target_height)
    return image.resize(target, Image.Resampling.LANCZOS)


def paste_star(canvas: Image.Image, star: Image.Image, height: int, center: tuple[int, int], rotation: float = 0) -> None:
    star = resize_contain(star, height)
    if rotation:
        star = star.rotate(rotation, resample=Image.Resampling.BICUBIC, expand=True)

    alpha = star.getchannel("A")
    outline_alpha = alpha.filter(ImageFilter.MaxFilter(19)).filter(ImageFilter.GaussianBlur(4))
    shadow = Image.new("RGBA", star.size, (3, 8, 12, 0))
    shadow.putalpha(outline_alpha.point(lambda p: int(p * 0.78)))

    x = center[0] - star.width // 2
    y = center[1] - star.height // 2
    canvas.alpha_composite(shadow, (x + 10, y - 10))

    rim_alpha = alpha.filter(ImageFilter.MaxFilter(9))
    rim = Image.new("RGBA", star.size, (12, 70, 116, 0))
    rim.putalpha(rim_alpha.point(lambda p: int(p * 0.44)))
    canvas.alpha_composite(rim, (x, y))

    star = ImageEnhance.Contrast(star).enhance(1.18)
    star = ImageEnhance.Brightness(star).enhance(1.07)
    canvas.alpha_composite(star, (x, y))


def dark_plastic_plate() -> Image.Image:
    mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(ICON_RECT, radius=RADIUS, fill=255)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (INSET + 10, INSET - 14, CANVAS - INSET + 10, CANVAS - INSET - 14),
        radius=RADIUS,
        fill=(0, 0, 0, 108),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)))

    fill = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    pixels = fill.load()
    for y in range(CANVAS):
        v = y / max(1, CANVAS - 1)
        for x in range(CANVAS):
            u = x / max(1, CANVAS - 1)
            color = blend((11, 18, 25), (3, 6, 9), v)
            color = blend(
                color,
                (14, 77, 108),
                max(0.0, 1.0 - math.hypot(u - 0.36, v - 0.28) / 0.58) * 0.28,
            )
            color = blend(color, (255, 255, 255), max(0.0, 1.0 - abs(v - 0.12) / 0.10) * 0.08)
            pixels[x, y] = (*color, 255)
    canvas.paste(fill, (0, 0), mask)

    edge = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    d = ImageDraw.Draw(edge)
    d.rounded_rectangle(ICON_RECT, radius=RADIUS, outline=(255, 255, 255, 86), width=4)
    d.rounded_rectangle(
        (INSET + 13, INSET + 13, CANVAS - INSET - 13, CANVAS - INSET - 13),
        radius=RADIUS - 18,
        outline=(0, 0, 0, 92),
        width=4,
    )
    canvas.alpha_composite(edge)
    return canvas


def chrome_star(star: Image.Image, height: int, rotation: float = 0) -> Image.Image:
    star = resize_contain(star, height)
    if rotation:
        star = star.rotate(rotation, resample=Image.Resampling.BICUBIC, expand=True)

    alpha = ImageEnhance.Contrast(star.getchannel("A")).enhance(1.2)
    edge = alpha.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.GaussianBlur(0.4))

    chrome = Image.new("RGBA", star.size, (0, 0, 0, 0))
    chrome_pixels = chrome.load()
    for y in range(star.height):
        v = y / max(1, star.height - 1)
        for x in range(star.width):
            u = x / max(1, star.width - 1)
            color = blend((225, 232, 238), (74, 92, 112), max(0.0, (v - 0.48) / 0.50))
            color = blend(color, (255, 255, 255), max(0.0, 1.0 - abs(v - 0.22) / 0.18) * 0.50)
            color = blend(color, (28, 38, 52), max(0.0, (v - 0.70) / 0.24) * 0.52)
            color = blend(color, (31, 182, 255), max(0.0, 1.0 - abs(u - 0.30) / 0.36) * 0.12)
            chrome_pixels[x, y] = (*color, alpha.getpixel((x, y)))

    texture = ImageEnhance.Sharpness(star).enhance(2.2)
    texture = ImageEnhance.Contrast(texture).enhance(1.18)
    chrome = Image.blend(chrome, texture, 0.62)
    chrome.putalpha(alpha)

    out = Image.new("RGBA", star.size, (0, 0, 0, 0))
    outer = alpha.filter(ImageFilter.MaxFilter(17)).filter(ImageFilter.GaussianBlur(2))
    dark = Image.new("RGBA", star.size, (4, 12, 18, 0))
    dark.putalpha(outer.point(lambda p: int(p * 0.74)))
    out.alpha_composite(dark)

    rim_alpha = alpha.filter(ImageFilter.MaxFilter(9))
    rim = Image.new("RGBA", star.size, (31, 182, 255, 0))
    rim.putalpha(rim_alpha.point(lambda p: int(p * 0.30)))
    out.alpha_composite(rim)
    out.alpha_composite(chrome)

    black_line = Image.new("RGBA", star.size, (2, 8, 12, 0))
    black_line.putalpha(edge.point(lambda p: min(214, int(p * 1.7))))
    out.alpha_composite(black_line)

    white_line = Image.new("RGBA", star.size, (255, 255, 255, 0))
    white_line.putalpha(edge.point(lambda p: min(122, int(p * 0.82))))
    out.alpha_composite(white_line, (-2, 2))
    return out


def paste_center(canvas: Image.Image, image: Image.Image, center: tuple[int, int]) -> None:
    x = center[0] - image.width // 2
    y = center[1] - image.height // 2

    alpha = image.getchannel("A").filter(ImageFilter.MaxFilter(17)).filter(ImageFilter.GaussianBlur(7))
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shadow.putalpha(alpha.point(lambda p: int(p * 0.48)))
    canvas.alpha_composite(shadow, (x + 16, y - 14))
    canvas.alpha_composite(image, (x, y))


def generate_icon() -> Image.Image:
    wordmark = Image.open(WORDMARK).convert("RGBA")
    left_star, right_star = star_crops(wordmark)
    icon = dark_plastic_plate()

    paste_center(icon, chrome_star(left_star, height=448, rotation=-4), center=(402, 586))
    paste_center(icon, chrome_star(right_star, height=286, rotation=3), center=(688, 342))

    return icon


def write_asset_catalog(icon: Image.Image) -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    specs = [
        ("16x16", "1x", 16),
        ("16x16", "2x", 32),
        ("32x32", "1x", 32),
        ("32x32", "2x", 64),
        ("128x128", "1x", 128),
        ("128x128", "2x", 256),
        ("256x256", "1x", 256),
        ("256x256", "2x", 512),
        ("512x512", "1x", 512),
        ("512x512", "2x", 1024),
    ]

    images = []
    for size, scale, pixels in specs:
        filename = f"app-icon-{pixels}.png"
        output = ASSET_DIR / filename
        icon.resize((pixels, pixels), Image.Resampling.LANCZOS).save(output)
        images.append(
            {
                "idiom": "mac",
                "size": size,
                "scale": scale,
                "filename": filename,
            }
        )

    (ASSET_DIR / "Contents.json").write_text(
        json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    BRAND_DIR.mkdir(parents=True, exist_ok=True)
    icon = generate_icon()
    icon.save(ICON_PNG)
    write_asset_catalog(icon)
    print(f"Wrote {ICON_PNG.relative_to(ROOT)}")
    print(f"Wrote {ASSET_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
