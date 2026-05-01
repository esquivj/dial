#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
import random

ROOT = Path(__file__).resolve().parents[1]
PREP = ROOT / "MarketingAssets" / "XReady" / "prepared"
OUT = ROOT / "MarketingAssets" / "XReady" / "comps"
FONT_DIR = ROOT / "Dial" / "Resources" / "Fonts"
ICON_DIR = ROOT / "Dial" / "Resources" / "Icons"
PET_DIR = ROOT / "Dial" / "Resources" / "Pets"
ROOM_DIR = ROOT / "Dial" / "Resources" / "RoomObjects"
ARTIFACT_DIR = ROOT / "Dial" / "Resources" / "Artifacts"
OUT.mkdir(parents=True, exist_ok=True)

MONO_MED = FONT_DIR / "GeistMono-Medium.ttf"
MONO_REG = FONT_DIR / "GeistMono-Regular.ttf"
PIXEL = FONT_DIR / "GeistPixel-Square.ttf"

CYAN = "#21C7FF"
PINK = "#FF4DD2"
SLIME = "#B8FF38"
WHITE = "#E9EEF2"
MUTE = "#8F98A3"
BLACK = "#040507"


def font(path, size):
    return ImageFont.truetype(str(path), size)


def rgba(hex_color, alpha=255):
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4)) + (alpha,)


def fit(im, width=None, height=None, resample=Image.Resampling.LANCZOS):
    if width is None and height is None:
        return im.copy()
    if width is None:
        scale = height / im.height
        width = round(im.width * scale)
    if height is None:
        scale = width / im.width
        height = round(im.height * scale)
    return im.resize((width, height), resample)


def asset(name):
    return Image.open(PREP / name).convert("RGBA")


def text_width(draw, text, text_font):
    box = draw.textbbox((0, 0), text, font=text_font)
    return box[2] - box[0]


def rich_text(draw, xy, runs):
    x, y = xy
    for text, text_font, fill in runs:
        draw.text((x, y), text, font=text_font, fill=fill)
        x += text_width(draw, text, text_font)


def paste_shadowed(canvas, im, xy, blur=30, offset=(0, 18), opacity=115):
    x, y = xy
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sh = Image.new("RGBA", im.size, (0, 0, 0, opacity))
    sh.putalpha(im.getchannel("A"))
    shadow.alpha_composite(sh, (x + offset[0], y + offset[1]))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))
    canvas.alpha_composite(im, (x, y))


def paste_glow(canvas, im, xy, color, blur=36, opacity=74):
    x, y = xy
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    g = Image.new("RGBA", im.size, rgba(color, opacity))
    g.putalpha(im.getchannel("A"))
    glow.alpha_composite(g, (x, y))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(blur)))
    canvas.alpha_composite(im, (x, y))


def trim_alpha(im, pad=0):
    bbox = im.getchannel("A").getbbox()
    if not bbox:
        return im.copy()
    left = max(0, bbox[0] - pad)
    top = max(0, bbox[1] - pad)
    right = min(im.width, bbox[2] + pad)
    bottom = min(im.height, bbox[3] + pad)
    return im.crop((left, top, right, bottom))


def tint_from_alpha(im, color, alpha=244):
    tinted = Image.new("RGBA", im.size, rgba(color, alpha))
    tinted.putalpha(im.getchannel("A"))
    return tinted


def glyph(path, height, color):
    im = trim_alpha(Image.open(path).convert("RGBA"), pad=3)
    im = fit(im, height=height, resample=Image.Resampling.NEAREST)
    return tint_from_alpha(im, color)


def feature_chip_grid():
    """Compact card with enough right-side breathing room for brand layouts."""
    w, h = 1600, 560
    card = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(card, "RGBA")
    draw.rounded_rectangle(
        (40, 34, w - 40, h - 34),
        radius=38,
        fill=rgba("#05070A", 184),
        outline=rgba("#FFFFFF", 44),
        width=2,
    )
    draw.text((88, 76), "FEATURES", font=font(MONO_MED, 34), fill=rgba(WHITE, 236))
    draw.text(
        (88, 122),
        "The HUD keeps track, memory, and companion in one tiny surface.",
        font=font(MONO_REG, 23),
        fill=rgba(MUTE, 220),
    )

    items = [
        ("LIVE HUD", ICON_DIR / "music.note.png", CYAN),
        ("HISTORY", ICON_DIR / "clock.arrow.circlepath.png", WHITE),
        ("BADGES", ICON_DIR / "sparkles.png", PINK),
        ("STATS", ICON_DIR / "chart.bar.fill.png", WHITE),
        ("PET", PET_DIR / "companion.png", SLIME),
        ("ROOM", ROOM_DIR / "window.png", SLIME),
        ("ARTIFACTS", ARTIFACT_DIR / "rediscovered_cassette.png", PINK),
        ("THEMES", ICON_DIR / "brand.sparkles.png", CYAN),
    ]
    chip_w = 304
    chip_h = 112
    gap_x = 46
    gap_y = 28
    start_x = 112
    start_y = 198
    for index, (label, path, color) in enumerate(items):
        row = index // 4
        col = index % 4
        x = start_x + col * (chip_w + gap_x)
        y = start_y + row * (chip_h + gap_y)
        draw.rounded_rectangle(
            (x, y, x + chip_w, y + chip_h),
            radius=24,
            fill=rgba("#06090C", 224),
            outline=rgba(color, 96),
            width=2,
        )
        draw.line(
            (x + 24, y + 2, x + chip_w - 24, y + 2),
            fill=rgba("#FFFFFF", 28),
            width=1,
        )
        size = 56 if label in {"PET", "ROOM", "ARTIFACTS"} else 46
        icon = glyph(path, size, color)
        icon_x = round(x + 60 - icon.width / 2)
        icon_y = round(y + chip_h / 2 - icon.height / 2)
        paste_glow(card, icon, (icon_x, icon_y), color, blur=9, opacity=48)
        draw.text((x + 112, y + 31), label, font=font(MONO_MED, 24), fill=rgba(WHITE, 238))
        draw.rectangle((x + 112, y + 68, x + 168, y + 72), fill=rgba(color, 190))
    return card


def base_bg(seed=1, accent=CYAN):
    w, h = 1600, 900
    im = Image.new("RGBA", (w, h), rgba(BLACK, 255))
    px = im.load()
    for y in range(h):
        gy = y / h
        for x in range(w):
            gx = x / w
            vignette = 1 - min(0.64, math.hypot(gx - 0.54, gy - 0.45) * 0.72)
            base = int(8 + 5 * vignette)
            px[x, y] = (base, base + 1, base + 4, 255)

    draw = ImageDraw.Draw(im, "RGBA")
    random.seed(seed)
    for _ in range(170):
        x = random.randrange(w)
        y = random.randrange(h)
        a = random.randrange(2, 8)
        draw.point((x, y), fill=(255, 255, 255, a))

    # Product-table hairlines, not decorative glow soup.
    for y in (78, 810):
        draw.line((68, y, w - 68, y), fill=rgba("#FFFFFF", 16), width=1)
    for x in (86, w - 86):
        draw.line((x, 74, x, 826), fill=rgba("#FFFFFF", 10), width=1)

    tint = Image.new("RGBA", im.size, (0, 0, 0, 0))
    td = ImageDraw.Draw(tint, "RGBA")
    td.rectangle((0, 0, w, h), fill=rgba(accent, 8))
    im.alpha_composite(tint)
    return im


def draw_lockup(canvas, xy, width=410, with_slogan=True):
    mark = fit(asset("dial-lockup-wordmark.png"), width=width)
    paste_shadowed(canvas, mark, xy, blur=24, offset=(0, 12), opacity=90)
    if not with_slogan:
        return mark.height
    draw = ImageDraw.Draw(canvas, "RGBA")
    size = max(22, round(width * 0.064))
    slogan = font(MONO_MED, size)
    y = xy[1] + mark.height + round(size * 0.92)
    rich_text(
        draw,
        (xy[0] + 4, y),
        [
            ("Now playing, ", slogan, rgba(WHITE, 238)),
            ("remembered.", slogan, rgba(CYAN, 242)),
        ],
    )
    return mark.height + size * 2


def draw_micro_labels(draw, labels, start_x, y, gap=34):
    x = start_x
    label_font = font(PIXEL, 21)
    for text, color in labels:
        draw.text((x, y), text, font=label_font, fill=rgba(color, 216))
        x += text_width(draw, text, label_font) + gap


def theme_variant_a():
    canvas = base_bg(11, CYAN)
    draw = ImageDraw.Draw(canvas, "RGBA")
    draw_lockup(canvas, (74, 78), 390, True)
    headline = font(MONO_MED, 52)
    draw.text((78, 306), "THEMES FOLLOW", font=headline, fill=rgba(WHITE, 242))
    draw.text((78, 363), "THE SOUND", font=headline, fill=rgba(CYAN, 242))
    draw.text((82, 444), "Artist and genre signals choose the HUD cartridge.", font=font(MONO_REG, 25), fill=rgba(MUTE, 224))
    draw_micro_labels(draw, [("SMOKE", WHITE), ("SLIME", SLIME), ("AQUA", CYAN), ("MAGENTA", PINK)], 84, 748)

    themes = [
        ("dial-hud-theme-smoke.png", 590, 130, WHITE),
        ("dial-hud-theme-slime.png", 928, 130, SLIME),
        ("dial-hud-theme-aqua.png", 590, 470, CYAN),
        ("dial-hud-theme-ember.png", 928, 470, PINK),
    ]
    for name, x, y, color in themes:
        hud = fit(asset(name), width=322)
        paste_glow(canvas, hud, (x, y), color, blur=32, opacity=44)
    canvas.save(OUT / "dial-x-theme-variant-a.png")


def theme_variant_b():
    canvas = base_bg(12, PINK)
    draw = ImageDraw.Draw(canvas, "RGBA")
    draw_lockup(canvas, (86, 72), 330, True)
    draw.text((92, 748), "Artist and genre signals choose the HUD cartridge.", font=font(MONO_REG, 24), fill=rgba(MUTE, 224))
    draw.text((92, 690), "THEMES FOLLOW THE SOUND", font=font(MONO_MED, 42), fill=rgba(WHITE, 240))

    xs = [130, 470, 810, 1150]
    names = ["smoke", "slime", "aqua", "ember"]
    labels = ["SMOKE", "SLIME", "AQUA", "MAGENTA"]
    colors = [WHITE, SLIME, CYAN, PINK]
    for i, (key, color, label) in enumerate(zip(names, colors, labels)):
        hud = fit(asset(f"dial-hud-theme-{key}.png"), width=360)
        y = 230 if i % 2 == 0 else 178
        paste_glow(canvas, hud, (xs[i], y), color, blur=34, opacity=46)
        draw.text((xs[i] + 30, y + 392), label, font=font(PIXEL, 24), fill=rgba(color, 230))
    canvas.save(OUT / "dial-x-theme-variant-b.png")


def theme_variant_c():
    canvas = base_bg(13, CYAN)
    draw = ImageDraw.Draw(canvas, "RGBA")
    draw_lockup(canvas, (70, 70), 360, True)
    draw.text((920, 82), "THEMES FOLLOW THE SOUND", font=font(MONO_MED, 35), fill=rgba(WHITE, 238))
    draw.text((922, 132), "Artist and genre signals choose the HUD cartridge.", font=font(MONO_REG, 20), fill=rgba(MUTE, 220))

    hero = fit(asset("dial-hud-theme-smoke.png"), width=620)
    paste_glow(canvas, hero, (130, 220), WHITE, blur=10, opacity=2)
    smalls = [
        ("dial-hud-theme-slime.png", 762, 262, SLIME, "SLIME"),
        ("dial-hud-theme-aqua.png", 1012, 262, CYAN, "AQUA"),
        ("dial-hud-theme-ember.png", 1262, 262, PINK, "MAGENTA"),
    ]
    for name, x, y, color, label in smalls:
        hud = fit(asset(name), width=218)
        paste_glow(canvas, hud, (x, y), color, blur=12, opacity=6)
        draw.text((x + 34, y + 238), label, font=font(PIXEL, 21), fill=rgba(color, 228))
    draw.text((742, 684), "SMOKE GEL / DEFAULT", font=font(PIXEL, 24), fill=rgba(WHITE, 220))
    canvas.save(OUT / "dial-x-theme-variant-c.png")


def brand_variant_a():
    canvas = base_bg(21, PINK)
    draw = ImageDraw.Draw(canvas, "RGBA")
    draw_lockup(canvas, (78, 74), 690, False)
    slogan = font(MONO_MED, 53)
    rich_text(draw, (88, 264), [("Now playing, ", slogan, rgba(WHITE, 240)), ("remembered.", slogan, rgba(CYAN, 242))])
    draw.text((94, 352), "Live playback, personal history, badges, stats, artifacts,", font=font(MONO_REG, 25), fill=rgba(MUTE, 224))
    draw.text((94, 388), "and a pixel companion that grows with what you listen to.", font=font(MONO_REG, 25), fill=rgba(MUTE, 224))

    device = fit(asset("dial-device-floating.png"), height=760)
    paste_shadowed(canvas, device, (1008, 86), blur=42, offset=(0, 30), opacity=150)
    room = fit(asset("dial-pet-room-lcd.png"), width=640)
    evo = fit(asset("dial-pet-evolution-strip.png"), width=660)
    paste_shadowed(canvas, room, (82, 486), blur=30, offset=(0, 18), opacity=105)
    paste_shadowed(canvas, evo, (770, 558), blur=28, offset=(0, 16), opacity=96)
    canvas.save(OUT / "dial-x-brand-variant-a.png")


def brand_variant_b():
    canvas = base_bg(22, CYAN)
    draw = ImageDraw.Draw(canvas, "RGBA")
    device = fit(asset("dial-device-floating.png"), height=820)
    paste_shadowed(canvas, device, (76, 44), blur=44, offset=(0, 32), opacity=150)
    draw_lockup(canvas, (760, 82), 610, False)
    slogan = font(MONO_MED, 46)
    rich_text(draw, (770, 262), [("Now playing, ", slogan, rgba(WHITE, 240)), ("remembered.", slogan, rgba(CYAN, 244))])
    draw.text((774, 336), "A tiny private music-memory device for Spotify.", font=font(MONO_REG, 25), fill=rgba(MUTE, 224))

    chips = fit(feature_chip_grid(), width=730)
    paste_shadowed(canvas, chips, (762, 420), blur=30, offset=(0, 18), opacity=100)
    canvas.save(OUT / "dial-x-brand-variant-b.png")


def brand_variant_c():
    canvas = base_bg(23, SLIME)
    draw = ImageDraw.Draw(canvas, "RGBA")
    draw_lockup(canvas, (78, 62), 500, False)
    draw.text((84, 210), "Now playing, remembered.", font=font(MONO_MED, 38), fill=rgba(WHITE, 238))
    draw.text((88, 268), "Playback becomes a small remembered world.", font=font(MONO_REG, 24), fill=rgba(MUTE, 224))

    device = fit(asset("dial-device-floating.png"), height=590)
    paste_shadowed(canvas, device, (1050, 156), blur=42, offset=(0, 28), opacity=146)
    room = fit(asset("dial-pet-room-lcd.png"), width=830)
    paste_shadowed(canvas, room, (76, 354), blur=32, offset=(0, 20), opacity=108)
    chips = fit(asset("dial-feature-chip-grid.png"), width=642)
    paste_shadowed(canvas, chips, (664, 578), blur=28, offset=(0, 14), opacity=86)
    canvas.save(OUT / "dial-x-brand-variant-c.png")


def contact_sheet(paths, out_path, title):
    thumb_w, thumb_h = 500, 281
    w, h = 1600, 720
    canvas = base_bg(88, WHITE)
    draw = ImageDraw.Draw(canvas, "RGBA")
    draw.text((70, 50), title, font=font(MONO_MED, 38), fill=rgba(WHITE, 238))
    for idx, path in enumerate(paths):
        im = Image.open(path).convert("RGBA")
        thumb = fit(im, width=thumb_w)
        if thumb.height > thumb_h:
            thumb = fit(im, height=thumb_h)
        x = 70 + idx * 510
        y = 152
        draw.rounded_rectangle((x - 10, y - 10, x + thumb_w + 10, y + thumb_h + 52), radius=22, fill=rgba("#0A0D11", 216), outline=rgba("#FFFFFF", 34), width=1)
        canvas.alpha_composite(thumb, (x, y))
        draw.text((x, y + thumb_h + 22), chr(ord("A") + idx), font=font(MONO_MED, 26), fill=rgba(CYAN if idx == 0 else WHITE, 230))
    canvas.save(out_path)


def main():
    feature_chip_grid().save(PREP / "dial-feature-chip-grid.png")
    theme_variant_a()
    theme_variant_b()
    theme_variant_c()
    brand_variant_a()
    brand_variant_b()
    brand_variant_c()
    contact_sheet(
        [OUT / "dial-x-theme-variant-a.png", OUT / "dial-x-theme-variant-b.png", OUT / "dial-x-theme-variant-c.png"],
        OUT / "dial-x-theme-variants-contact.png",
        "THEME ASSET VARIANTS",
    )
    contact_sheet(
        [OUT / "dial-x-brand-variant-a.png", OUT / "dial-x-brand-variant-b.png", OUT / "dial-x-brand-variant-c.png"],
        OUT / "dial-x-brand-variants-contact.png",
        "BRAND HERO VARIANTS",
    )
    for path in sorted(OUT.glob("dial-x-*-variant-*.png")):
        im = Image.open(path).convert("RGBA")
        print(f"{path.name}: {im.size}")
    print(f"contact: {OUT / 'dial-x-theme-variants-contact.png'}")
    print(f"contact: {OUT / 'dial-x-brand-variants-contact.png'}")


if __name__ == "__main__":
    main()
