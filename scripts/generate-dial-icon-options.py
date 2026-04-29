#!/usr/bin/env python3
from __future__ import annotations

import math
from collections import deque
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
WORDMARK = ROOT / "Dial/Resources/Brand/dial-wordmark-chrome.png"
OUT = ROOT / "MarketingAssets/app-icon-options"
CANVAS = 1024
RECT = (88, 88, 936, 936)
RADIUS = 198


RGB = tuple[int, int, int]


def mix(a: RGB, b: RGB, t: float) -> RGB:
    t = max(0.0, min(1.0, t))
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


def rounded_mask(size: int, rect: tuple[int, int, int, int], radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(rect, radius=radius, fill=255)
    return mask


def alpha_components(image: Image.Image) -> list[tuple[int, tuple[int, int, int, int], list[tuple[int, int]]]]:
    alpha = image.getchannel("A")
    w, h = alpha.size
    px = alpha.load()
    seen: set[tuple[int, int]] = set()
    comps: list[tuple[int, tuple[int, int, int, int], list[tuple[int, int]]]] = []

    for y in range(h):
        for x in range(w):
            if px[x, y] <= 24 or (x, y) in seen:
                continue
            stack = [(x, y)]
            seen.add((x, y))
            points: list[tuple[int, int]] = []
            min_x = max_x = x
            min_y = max_y = y
            while stack:
                cx, cy = stack.pop()
                points.append((cx, cy))
                min_x = min(min_x, cx)
                max_x = max(max_x, cx)
                min_y = min(min_y, cy)
                max_y = max(max_y, cy)
                for nx in range(cx - 1, cx + 2):
                    for ny in range(cy - 1, cy + 2):
                        if nx < 0 or ny < 0 or nx >= w or ny >= h:
                            continue
                        if (nx, ny) in seen or px[nx, ny] <= 24:
                            continue
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            if len(points) > 50:
                comps.append((len(points), (min_x, min_y, max_x + 1, max_y + 1), points))
    return comps


def star_sources() -> tuple[Image.Image, Image.Image]:
    wordmark = Image.open(WORDMARK).convert("RGBA")
    stars = [
        (box, points)
        for area, box, points in alpha_components(wordmark)
        if area < 12_000 and abs((box[2] - box[0]) - (box[3] - box[1])) < 18
    ]
    stars = sorted(stars, key=lambda item: item[0][0])
    if len(stars) < 2:
        raise RuntimeError("Could not isolate the two sparkle marks from the wordmark.")

    isolated: list[Image.Image] = []
    for box, points in (stars[0], stars[-1]):
        pad = 12
        crop_box = (
            max(0, box[0] - pad),
            max(0, box[1] - pad),
            min(wordmark.width, box[2] + pad),
            min(wordmark.height, box[3] + pad),
        )
        crop = wordmark.crop(crop_box)
        mask = Image.new("L", crop.size, 0)
        mask_px = mask.load()
        for px, py in points:
            mask_px[px - crop_box[0], py - crop_box[1]] = 255
        mask = mask.filter(ImageFilter.MaxFilter(3))
        out = Image.new("RGBA", crop.size, (0, 0, 0, 0))
        out.paste(crop, (0, 0), mask)
        isolated.append(out)
    return isolated[0], isolated[1]


def chrome_gradient(size: tuple[int, int], cool: bool = True, smooth: bool = True) -> Image.Image:
    w, h = size
    img = Image.new("RGBA", size)
    px = img.load()
    for y in range(h):
        v = y / max(1, h - 1)
        for x in range(w):
            u = x / max(1, w - 1)
            base = mix((222, 229, 235), (95, 111, 128), max(0, (v - 0.48) / 0.48))
            base = mix(base, (250, 253, 255), max(0, 1 - abs(v - 0.18) / 0.20) * 0.46)
            base = mix(base, (169, 187, 203), max(0, 1 - abs(v - 0.52) / 0.30) * 0.34)
            base = mix(base, (28, 38, 52), max(0, (v - 0.72) / 0.24) * 0.55)
            diagonal = max(0, 1 - abs((u * 0.78 + v * 0.22) - 0.56) / 0.16)
            base = mix(base, (255, 255, 255), diagonal * (0.15 if smooth else 0.24))
            if cool:
                base = mix(base, (42, 157, 242), max(0, 1 - abs(u - 0.30) / 0.32) * 0.10)
            px[x, y] = (*base, 255)
    return img


def plastic_base(kind: str) -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    mask = rounded_mask(CANVAS, RECT, RADIUS)

    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    d = ImageDraw.Draw(shadow)
    d.rounded_rectangle((98, 74, 946, 922), radius=RADIUS, fill=(0, 0, 0, 105))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)))

    fill = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    fpx = fill.load()
    for y in range(CANVAS):
        v = y / (CANVAS - 1)
        for x in range(CANVAS):
            u = x / (CANVAS - 1)
            if kind == "lcd":
                color = mix((8, 15, 20), (4, 7, 10), v)
                color = mix(color, (0, 90, 130), max(0, 1 - math.hypot(u - 0.34, v - 0.23) / 0.62) * 0.18)
            else:
                color = mix((11, 18, 25), (4, 6, 9), v)
                color = mix(color, (13, 72, 104), max(0, 1 - math.hypot(u - 0.38, v - 0.30) / 0.58) * 0.26)
                color = mix(color, (255, 255, 255), max(0, 1 - abs(v - 0.12) / 0.10) * 0.08)
            fpx[x, y] = (*color, 255)
    canvas.paste(fill, (0, 0), mask)

    edge = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ed = ImageDraw.Draw(edge)
    ed.rounded_rectangle(RECT, radius=RADIUS, outline=(255, 255, 255, 90), width=4)
    ed.rounded_rectangle((101, 101, 923, 923), radius=RADIUS - 14, outline=(0, 0, 0, 94), width=4)
    canvas.alpha_composite(edge)
    return canvas


def lcd_panel(canvas: Image.Image) -> None:
    rect = (154, 194, 870, 828)
    radius = 118
    panel = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    mask = rounded_mask(CANVAS, rect, radius)
    fill = Image.new("RGBA", (CANVAS, CANVAS), (181, 186, 145, 255))
    panel.paste(fill, (0, 0), mask)

    scan = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    sd = ImageDraw.Draw(scan)
    for y in range(rect[1] + 18, rect[3] - 18, 15):
        sd.line((rect[0] + 8, y, rect[2] - 8, y), fill=(10, 18, 12, 42), width=2)
    panel.alpha_composite(scan)

    d = ImageDraw.Draw(panel)
    d.rounded_rectangle(rect, radius=radius, outline=(255, 255, 255, 102), width=5)
    d.rounded_rectangle((rect[0] + 10, rect[1] + 10, rect[2] - 10, rect[3] - 10), radius=radius - 14, outline=(0, 0, 0, 70), width=4)
    canvas.alpha_composite(panel)


def chrome_base() -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    mask = rounded_mask(CANVAS, RECT, RADIUS)

    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((100, 78, 948, 924), radius=RADIUS, fill=(0, 0, 0, 102))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)))

    chrome = chrome_gradient((CANVAS, CANVAS), cool=True, smooth=True)
    canvas.paste(chrome, (0, 0), mask)

    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle(RECT, radius=RADIUS, outline=(255, 255, 255, 122), width=5)
    d.rounded_rectangle((103, 103, 921, 921), radius=RADIUS - 15, outline=(35, 79, 112, 88), width=5)
    d.rounded_rectangle((122, 122, 902, 902), radius=RADIUS - 35, outline=(255, 255, 255, 42), width=2)
    return canvas


def resize_contain(image: Image.Image, target_h: int) -> Image.Image:
    scale = target_h / image.height
    return image.resize((round(image.width * scale), target_h), Image.Resampling.LANCZOS)


def enhance_star(source: Image.Image, target_h: int, rotation: float = 0) -> Image.Image:
    star = resize_contain(source, target_h)
    if rotation:
        star = star.rotate(rotation, resample=Image.Resampling.BICUBIC, expand=True)

    alpha = star.getchannel("A")
    alpha = ImageEnhance.Contrast(alpha).enhance(1.2)
    edge = alpha.filter(ImageFilter.FIND_EDGES).filter(ImageFilter.GaussianBlur(0.4))

    chrome = chrome_gradient(star.size, cool=True, smooth=True)
    chrome.putalpha(alpha)
    texture = ImageEnhance.Sharpness(star).enhance(2.2)
    texture = ImageEnhance.Contrast(texture).enhance(1.15)
    chrome = Image.blend(chrome, texture, 0.62)
    chrome.putalpha(alpha)

    out = Image.new("RGBA", star.size, (0, 0, 0, 0))

    outer = alpha.filter(ImageFilter.MaxFilter(17)).filter(ImageFilter.GaussianBlur(2))
    dark = Image.new("RGBA", star.size, (4, 12, 18, 0))
    dark.putalpha(outer.point(lambda p: int(p * 0.75)))
    out.alpha_composite(dark)

    cyan = alpha.filter(ImageFilter.MaxFilter(9))
    rim = Image.new("RGBA", star.size, (31, 182, 255, 0))
    rim.putalpha(cyan.point(lambda p: int(p * 0.28)))
    out.alpha_composite(rim)

    out.alpha_composite(chrome)

    black_line = Image.new("RGBA", star.size, (2, 8, 12, 0))
    black_line.putalpha(edge.point(lambda p: min(210, int(p * 1.7))))
    out.alpha_composite(black_line)
    white_line = Image.new("RGBA", star.size, (255, 255, 255, 0))
    white_line.putalpha(edge.point(lambda p: min(120, int(p * 0.8))))
    out.alpha_composite(white_line, (-2, 2))
    return out


def paste_center(canvas: Image.Image, img: Image.Image, center: tuple[int, int], shadow: bool = True) -> None:
    x = center[0] - img.width // 2
    y = center[1] - img.height // 2
    if shadow:
        a = img.getchannel("A").filter(ImageFilter.MaxFilter(17)).filter(ImageFilter.GaussianBlur(7))
        s = Image.new("RGBA", img.size, (0, 0, 0, 0))
        s.putalpha(a.point(lambda p: int(p * 0.48)))
        canvas.alpha_composite(s, (x + 16, y - 14))
    canvas.alpha_composite(img, (x, y))


def option_a(left: Image.Image, right: Image.Image) -> Image.Image:
    icon = plastic_base("dark")
    paste_center(icon, enhance_star(left, 448, -4), (402, 586))
    paste_center(icon, enhance_star(right, 286, 3), (688, 342))
    return icon


def option_b(left: Image.Image, right: Image.Image) -> Image.Image:
    icon = plastic_base("lcd")
    lcd_panel(icon)
    paste_center(icon, enhance_star(left, 318, -4), (420, 580))
    paste_center(icon, enhance_star(right, 195, 4), (666, 388))
    return icon


def option_c(left: Image.Image, right: Image.Image) -> Image.Image:
    icon = chrome_base()
    paste_center(icon, enhance_star(left, 330, -4), (410, 572))
    paste_center(icon, enhance_star(right, 205, 3), (668, 362))
    return icon


def contact_sheet(options: list[tuple[str, Image.Image]]) -> Image.Image:
    swatch = 280
    gap = 42
    small = 64
    label_h = 54
    width = gap + len(options) * swatch + (len(options) - 1) * gap + gap
    height = 470
    sheet = Image.new("RGBA", (width, height), (7, 10, 13, 255))
    draw = ImageDraw.Draw(sheet)
    try:
        label_font = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", 18)
        small_font = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", 12)
    except OSError:
        label_font = ImageFont.load_default()
        small_font = ImageFont.load_default()

    for i, (label, icon) in enumerate(options):
        x = gap + i * (swatch + gap)
        draw.text((x, 24), label, fill=(232, 235, 237, 255), font=label_font)
        preview = icon.resize((swatch, swatch), Image.Resampling.LANCZOS)
        sheet.alpha_composite(preview, (x, 72))
        mini = icon.resize((small, small), Image.Resampling.LANCZOS)
        mini_y = 72 + swatch + 30
        sheet.alpha_composite(mini, (x, mini_y))
        draw.text((x + small + 12, mini_y + 22), "64px check", fill=(137, 143, 152, 255), font=small_font)
    return sheet


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    left, right = star_sources()
    options = [
        ("A / dark plastic", option_a(left, right)),
        ("B / LCD sticker", option_b(left, right)),
        ("C / chrome badge", option_c(left, right)),
    ]
    filenames = [
        "dial-icon-option-a-dark-plastic.png",
        "dial-icon-option-b-lcd-sticker.png",
        "dial-icon-option-c-chrome-badge.png",
    ]
    for (_, image), filename in zip(options, filenames):
        image.save(OUT / filename)
    contact_sheet(options).save(OUT / "dial-icon-options-contact-sheet.png")
    print(f"Wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
