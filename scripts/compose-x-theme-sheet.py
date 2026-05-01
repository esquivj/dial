#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
import random

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "MarketingAssets" / "XReady"
GENERATED_DIR = OUT_DIR / "generated"
THEME_OUT = OUT_DIR / "dial-x-theme-cartridges-v1.png"
BRAND_OUT = OUT_DIR / "dial-x-brand-hero-v1.png"

FONT_DIR = ROOT / "Dial" / "Resources" / "Fonts"
ICON_DIR = ROOT / "Dial" / "Resources" / "Icons"
PET_DIR = ROOT / "Dial" / "Resources" / "Pets"
ROOM_DIR = ROOT / "Dial" / "Resources" / "RoomObjects"
MONO_MEDIUM = FONT_DIR / "GeistMono-Medium.ttf"
MONO_REGULAR = FONT_DIR / "GeistMono-Regular.ttf"
PIXEL = FONT_DIR / "GeistPixel-Square.ttf"


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


def trim_alpha(im, pad=0):
    bbox = im.getchannel("A").getbbox()
    if not bbox:
        return im
    left = max(0, bbox[0] - pad)
    top = max(0, bbox[1] - pad)
    right = min(im.width, bbox[2] + pad)
    bottom = min(im.height, bbox[3] + pad)
    return im.crop((left, top, right, bottom))


def text_width(draw, text, text_font):
    box = draw.textbbox((0, 0), text, font=text_font)
    return box[2] - box[0]


def draw_rich_text(draw, xy, runs):
    x, y = xy
    for text, text_font, fill in runs:
        draw.text((x, y), text, font=text_font, fill=fill)
        x += text_width(draw, text, text_font)


def paste_shadowed(canvas, asset, xy, shadow=(0, 34), blur=46, opacity=130):
    x, y = xy
    shadow_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_asset = Image.new("RGBA", asset.size, (0, 0, 0, opacity))
    shadow_asset.putalpha(asset.getchannel("A"))
    shadow_layer.alpha_composite(shadow_asset, (x + shadow[0], y + shadow[1]))
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow_layer)
    canvas.alpha_composite(asset, (x, y))


def shadow_for(asset, opacity=120):
    shadow = Image.new("RGBA", asset.size, (0, 0, 0, opacity))
    shadow.putalpha(asset.getchannel("A"))
    return shadow


def draw_glow(canvas, center, radius, color, alpha):
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow, "RGBA")
    x, y = center
    draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=rgba(color, alpha))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(radius // 2)))


def draw_background(canvas, seed=7, scanlines=False):
    w, h = canvas.size
    pixels = canvas.load()
    for y in range(h):
        gy = y / h
        for x in range(w):
            gx = x / w
            vignette = 1 - min(0.72, math.hypot(gx - 0.54, gy - 0.50) * 1.04)
            base = int(5 + 14 * vignette)
            pixels[x, y] = (base, base + 1, base + 8, 255)

    draw = ImageDraw.Draw(canvas, "RGBA")
    random.seed(seed)
    for _ in range(620):
        x = random.randrange(w)
        y = random.randrange(h)
        canvas.putpixel((x, y), (255, 255, 255, random.randrange(3, 13)))

    if scanlines:
        for y in range(0, h, 16):
            draw.line((0, y, w, y), fill=(255, 255, 255, 2), width=1)

    for x in (w * 0.18, w * 0.44, w * 0.72):
        draw.line((x, 0, x - 120, h), fill=(255, 255, 255, 3), width=1)

    draw.rounded_rectangle(
        (40, 40, w - 40, h - 40),
        radius=48,
        outline=(255, 255, 255, 5),
        width=1,
    )


def wordmark(width):
    im = Image.open(ROOT / "Dial" / "Resources" / "Brand" / "dial-wordmark-chrome.png").convert("RGBA")
    return fit(trim_alpha(im), width=width)


def draw_lockup(canvas, xy, mark_width=420, slogan_size=30):
    x, y = xy
    wm = wordmark(mark_width)
    paste_shadowed(canvas, wm, (x, y), shadow=(0, 14), blur=24, opacity=90)
    draw = ImageDraw.Draw(canvas, "RGBA")
    draw.text((x + 6, y + wm.height + 28), "Now playing, remembered.", font=font(MONO_MEDIUM, slogan_size), fill=rgba("#DDE4E8", 220))


def draw_big_lockup(canvas, xy):
    x, y = xy
    wm = wordmark(760)
    paste_shadowed(canvas, wm, (x, y), shadow=(0, 20), blur=34, opacity=120)
    draw = ImageDraw.Draw(canvas, "RGBA")
    slogan_font = font(MONO_MEDIUM, 58)
    draw_rich_text(
        draw,
        (x + 8, y + wm.height + 52),
        [
            ("Now playing, ", slogan_font, rgba("#E9EEF2", 242)),
            ("remembered.", slogan_font, rgba("#21C7FF", 244)),
        ],
    )


def icon_image(name, color="#DDE4E8", size=30):
    icon = Image.open(ICON_DIR / name).convert("RGBA")
    icon = trim_alpha(icon, pad=2)
    icon = fit(icon, width=size)
    alpha = icon.getchannel("A")
    tinted = Image.new("RGBA", icon.size, rgba(color, 245))
    tinted.putalpha(alpha)
    return tinted


def pet_image(name, width):
    pet = Image.open(PET_DIR / f"{name}.png").convert("RGBA")
    return fit(trim_alpha(pet, pad=8), width=width, resample=Image.Resampling.NEAREST)


def room_object(name, width):
    obj = Image.open(ROOM_DIR / f"{name}.png").convert("RGBA")
    return fit(trim_alpha(obj, pad=3), width=width, resample=Image.Resampling.NEAREST)


def paste_sprite(canvas, sprite, center):
    x = round(center[0] - sprite.width / 2)
    y = round(center[1] - sprite.height / 2)
    canvas.alpha_composite(sprite, (x, y))


def draw_lcd_room(canvas, box):
    draw = ImageDraw.Draw(canvas, "RGBA")
    x1, y1, x2, y2 = box
    draw.rounded_rectangle(box, radius=26, fill=rgba("#C8D0B3", 226), outline=rgba("#FFFFFF", 85), width=3)
    for y in range(y1 + 7, y2 - 6, 8):
        draw.line((x1 + 6, y, x2 - 6, y), fill=rgba("#05090F", 24), width=1)

    paste_sprite(canvas, room_object("plant", 88), (x1 + 96, y2 - 104))
    paste_sprite(canvas, room_object("shelf", 168), (x1 + 242, y1 + 116))
    paste_sprite(canvas, room_object("window", 120), (x1 + 460, y1 + 118))
    paste_sprite(canvas, room_object("mcm_hifi_console", 132), (x2 - 110, y2 - 100))
    paste_sprite(canvas, pet_image("companion", 138), ((x1 + x2) // 2, y2 - 106))

    draw.text((x1 + 34, y2 + 26), "LVL 12", font=font(PIXEL, 22), fill=rgba("#B8FF38", 230))
    draw.text((x1 + 174, y2 + 26), "♥ ♥ ♥", font=font(PIXEL, 22), fill=rgba("#B8FF38", 205))
    draw.rounded_rectangle((x1 + 294, y2 + 30, x1 + 430, y2 + 48), radius=8, fill=rgba("#C8D0B3", 70), outline=rgba("#B8FF38", 90), width=2)
    draw.rounded_rectangle((x1 + 300, y2 + 35, x1 + 402, y2 + 43), radius=4, fill=rgba("#B8FF38", 195))
    draw.text((x1 + 468, y2 + 26), "HAPPY", font=font(PIXEL, 22), fill=rgba("#B8FF38", 200))


def draw_theme_asset():
    canvas = Image.new("RGBA", (3200, 1800), (0, 0, 0, 255))
    draw_background(canvas, seed=21, scanlines=False)
    draw_glow(canvas, (780, 980), 640, "#21C7FF", 26)
    draw_glow(canvas, (1710, 760), 700, "#B8FF38", 18)
    draw_glow(canvas, (2670, 1020), 680, "#FF4DD2", 20)

    draw = ImageDraw.Draw(canvas, "RGBA")
    draw_lockup(canvas, (104, 94), mark_width=430, slogan_size=29)
    draw.text((2478, 108), "GENRE-DRIVEN THEMES", font=font(MONO_MEDIUM, 28), fill=rgba("#DDE4E8", 230))
    draw.text((2478, 150), "The HUD skin follows the sound.", font=font(MONO_REGULAR, 22), fill=rgba("#8F98A3", 220))

    themes = [
        ("SMOKE GEL", "CORE / MIXED SIGNAL", "classic", "#F1F3F4"),
        ("SLIME", "ELECTRONIC / CLUB", "slime", "#B8FF38"),
        ("AQUA", "INDIE / COOL", "aqua", "#21C7FF"),
        ("EMBER", "HEAVY / PUNK / HEAT", "ember", "#FF4DD2"),
    ]
    x_positions = [54, 836, 1618, 2400]
    for (label, tag, key, color), x in zip(themes, x_positions):
        src = GENERATED_DIR / f"dial-hud-{key}-transparent.png"
        hud = trim_alpha(Image.open(src).convert("RGBA"), pad=0)
        hud = fit(hud, width=748)
        paste_shadowed(canvas, hud, (x, 370), shadow=(0, 42), blur=52, opacity=150)
        draw.text((x + 30, 1148), label, font=font(MONO_MEDIUM, 26), fill=rgba(color, 238))
        draw.line((x + 30, 1188, x + 196, 1188), fill=rgba(color, 160), width=3)
        draw.text((x + 30, 1214), tag, font=font(MONO_REGULAR, 18), fill=rgba("#8F98A3", 210))

    draw.text((106, 1484), "Dial reads artist and genre signals, then loads the cartridge that fits the track.", font=font(MONO_MEDIUM, 27), fill=rgba("#DDE4E8", 226))
    draw.text(
        (106, 1532),
        "Smoke for neutral libraries. Slime for electronic. Aqua for indie/cool signal. Ember for heavy, punk, and high-heat tags.",
        font=font(MONO_REGULAR, 24),
        fill=rgba("#8F98A3", 220),
    )
    canvas.save(THEME_OUT)
    return THEME_OUT


def draw_feature_chip(canvas, xy, label, icon, color="#DDE4E8", active=False):
    draw = ImageDraw.Draw(canvas, "RGBA")
    x, y = xy
    fill = rgba("#0B0D10", 224) if not active else rgba("#0D1013", 234)
    outline = rgba(color, 110 if active else 54)
    draw.rounded_rectangle((x, y, x + 366, y + 84), radius=18, fill=fill, outline=outline, width=2)
    if icon.endswith(".png"):
        img = icon_image(icon, color=color, size=34)
        canvas.alpha_composite(img, (x + 24, y + (84 - img.height) // 2))
    else:
        draw.rounded_rectangle((x + 20, y + 21, x + 58, y + 59), radius=8, fill=rgba("#C8D0B3", 218), outline=rgba("#FFFFFF", 42), width=1)
        img = pet_image(icon, 30)
        canvas.alpha_composite(img, (x + 24 + (30 - img.width) // 2, y + 26 + (30 - img.height) // 2))
    draw.text((x + 76, y + 27), label, font=font(MONO_MEDIUM, 24), fill=rgba("#E9EEF2", 235))


def draw_menubar_states(canvas, xy):
    x, y = xy
    draw = ImageDraw.Draw(canvas, "RGBA")
    draw.text((x, y), "MENUBAR", font=font(MONO_MEDIUM, 26), fill=rgba("#FF4DD2", 230))
    rows = [
        ("track", "#E9EEF2", y + 58),
        ("pet", "#B8FF38", y + 126),
        ("plays", "#FF4DD2", y + 194),
    ]
    for name, color, row_y in rows:
        strip = Image.open(ROOT / "MarketingAssets" / "XReady" / "generated" / f"dial-menubar-{name}-transparent.png").convert("RGBA")
        strip = fit(trim_alpha(strip, pad=4), height=42)
        draw.text((x, row_y + 8), name.upper(), font=font(MONO_REGULAR, 17), fill=rgba(color, 170))
        canvas.alpha_composite(strip, (x + 112, row_y))


def draw_pet_strip(canvas, xy):
    draw = ImageDraw.Draw(canvas, "RGBA")
    x0, y = xy
    stages = [
        ("EGG", "egg"),
        ("HATCH", "hatching"),
        ("SMALL", "hatchling"),
        ("JUVIE", "juvenile"),
        ("BOND", "companion"),
        ("ELDER", "elder"),
    ]
    draw.text((x0, y - 54), "PET EVOLUTION", font=font(MONO_MEDIUM, 26), fill=rgba("#21C7FF", 230))
    for i, (label, name) in enumerate(stages):
        x = x0 + i * 110
        draw.rounded_rectangle((x, y, x + 82, y + 82), radius=15, fill=rgba("#C8D0B3", 220), outline=rgba("#FFFFFF", 54), width=2)
        pet = Image.open(ROOT / "Dial" / "Resources" / "Pets" / f"{name}.png").convert("RGBA")
        pet = fit(trim_alpha(pet, pad=8), width=66, resample=Image.Resampling.NEAREST)
        canvas.alpha_composite(pet, (x + (82 - pet.width) // 2, y + (82 - pet.height) // 2))
        draw.text((x + 1, y + 100), label, font=font(PIXEL, 18), fill=rgba("#DDE4E8", 215))


def draw_brand_asset():
    canvas = Image.new("RGBA", (3200, 1800), (0, 0, 0, 255))
    draw_background(canvas, seed=32, scanlines=False)
    draw_glow(canvas, (710, 650), 640, "#21C7FF", 24)
    draw_glow(canvas, (2520, 1030), 740, "#FF4DD2", 28)

    draw = ImageDraw.Draw(canvas, "RGBA")
    draw_big_lockup(canvas, (122, 108))

    device = Image.open(GENERATED_DIR / "dial-imagegen-digivice-floating-v2.png").convert("RGBA")
    device = fit(trim_alpha(device, pad=2), width=1280)
    paste_shadowed(canvas, device, (1746, 126), shadow=(0, 62), blur=72, opacity=170)

    app_icon = Image.open(ROOT / "Dial" / "Resources" / "Brand" / "dial-app-icon.png").convert("RGBA")
    app_icon = fit(trim_alpha(app_icon, pad=4), width=300)
    paste_shadowed(canvas, app_icon, (130, 600), shadow=(0, 30), blur=38, opacity=130)

    draw_lcd_room(canvas, (528, 600, 1420, 892))

    features = [
        ("NOW PLAYING", "music.note.png", "#21C7FF", True),
        ("BADGES", "sparkles.png", "#FF4DD2", True),
        ("PET ROOM", "companion", "#B8FF38", True),
        ("ARTIFACTS", "rectangle.inset.filled.png", "#FF4DD2", False),
        ("HISTORY", "clock.arrow.circlepath.png", "#DDE4E8", False),
        ("STATS", "chart.bar.fill.png", "#DDE4E8", False),
    ]
    for i, item in enumerate(features):
        x = 130 + (i % 3) * 406
        y = 1010 + (i // 3) * 112
        draw_feature_chip(canvas, (x, y), *item)

    draw.text((130, 1296), "PET COMPANION", font=font(MONO_MEDIUM, 28), fill=rgba("#B8FF38", 232))
    draw.text((130, 1340), "Grows from repeat plays, badges, and room memories.", font=font(MONO_REGULAR, 24), fill=rgba("#A9B0BA", 220))
    draw_pet_strip(canvas, (130, 1458))

    canvas.save(BRAND_OUT)
    return BRAND_OUT


def main():
    paths = [draw_theme_asset(), draw_brand_asset()]
    for path in paths:
        print(path)


if __name__ == "__main__":
    main()
