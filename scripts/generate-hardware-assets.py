#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
BLUEPRINT_PATH = ROOT / "MarketingAssets" / "frame-system" / "hardware-blueprint.json"
PREVIEW_DIR = ROOT / "MarketingAssets" / "frame-system"
OUT = ROOT / "Dial" / "Resources" / "Hardware"
RENDER_SOURCE_PATH = PREVIEW_DIR / "smoke-shell-render-source.png"
OUTER_RENDER_SOURCE_PATH = PREVIEW_DIR / "smoke-shell-outer-render-alpha-v2.png"


def load_blueprint() -> dict:
    with BLUEPRINT_PATH.open("r", encoding="utf-8") as file:
        return json.load(file)


BP = load_blueprint()
SCALE = int(BP["scale"])
OUT.mkdir(parents=True, exist_ok=True)
PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

SHELL_TINTS = {
    "slime": {
        "chassis": (82, 128, 45, 34),
        "aperture": (120, 255, 68, 16),
        "reflection": (190, 255, 150, 18),
    },
    "aqua": {
        "chassis": (26, 137, 210, 42),
        "aperture": (58, 190, 255, 18),
        "reflection": (130, 214, 255, 20),
    },
    "ember": {
        "chassis": (180, 38, 145, 30),
        "aperture": (255, 96, 214, 13),
        "reflection": (255, 178, 232, 15),
    },
}


def px(value: float) -> int:
    return int(round(value * SCALE))


def size_px() -> tuple[int, int]:
    canvas = BP["canvas"]
    return px(canvas["width"]), px(canvas["height"])


def box_px(rect: dict) -> tuple[int, int, int, int]:
    return (
        px(rect["x"]),
        px(rect["y"]),
        px(rect["x"] + rect["width"]),
        px(rect["y"] + rect["height"]),
    )


def radius_px(rect: dict) -> int:
    return px(rect["radius"])


def rounded_mask(size: tuple[int, int], rect: dict, grow: float = 0, radius_delta: float = 0) -> Image.Image:
    x0, y0, x1, y1 = box_px(rect)
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        [x0 - px(grow), y0 - px(grow), x1 + px(grow), y1 + px(grow)],
        radius=max(1, radius_px(rect) + px(radius_delta)),
        fill=255,
    )
    return mask


def antialiased_rounded_mask(
    size: tuple[int, int],
    rect: dict,
    grow: float = 0,
    radius_delta: float = 0,
    supersample: int = 4,
) -> Image.Image:
    x0, y0, x1, y1 = box_px(rect)
    high_size = (size[0] * supersample, size[1] * supersample)
    mask = Image.new("L", high_size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        [
            (x0 - px(grow)) * supersample,
            (y0 - px(grow)) * supersample,
            (x1 + px(grow)) * supersample,
            (y1 + px(grow)) * supersample,
        ],
        radius=max(1, radius_px(rect) + px(radius_delta)) * supersample,
        fill=255,
    )
    return mask.resize(size, Image.Resampling.LANCZOS)


def trim_to_shell_alpha(img: Image.Image, shell_mask: Image.Image | None = None) -> None:
    """Guarantee no rendered pixels escape the hardware silhouette."""
    if shell_mask is None:
        shell_mask = rounded_mask(img.size, BP["shell"])
    alpha = ImageChops.multiply(img.getchannel("A"), shell_mask)
    alpha = alpha.point(lambda value: 0 if value <= 2 else value)
    img.putalpha(alpha)


def visible_hardware_mask(size: tuple[int, int], render: Image.Image | None) -> Image.Image:
    """Mask to the real shell silhouette, while keeping live UI sockets filled.

    The render source has the correct plastic outline but transparent cutouts
    for LCD/control wells. The old generator used one big rounded rectangle as
    the chassis mask, which left fake black pixels outside the actual shell.
    """
    if render is None:
        return rounded_mask(size, BP["shell"])

    mask = render.getchannel("A")
    for rect in (BP["rail"], BP["hudLcd"], BP["hudTransport"], BP["hudNoTransportLcd"], BP["fullLcd"]):
        mask = ImageChops.lighter(mask, antialiased_rounded_mask(size, rect, grow=0.9, radius_delta=0.9))
    return mask.point(lambda value: 0 if value <= 2 else value)


def vertical_gradient(size: tuple[int, int], stops: list[tuple[float, tuple[int, int, int, int]]]) -> Image.Image:
    w, h = size
    stops = sorted(stops, key=lambda stop: stop[0])
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    pixels = img.load()
    for y in range(h):
        t = y / max(1, h - 1)
        left = stops[0]
        right = stops[-1]
        for index in range(len(stops) - 1):
            if stops[index][0] <= t <= stops[index + 1][0]:
                left = stops[index]
                right = stops[index + 1]
                break
        span = max(0.0001, right[0] - left[0])
        local = max(0, min(1, (t - left[0]) / span))
        color = tuple(int(round(left[1][channel] + (right[1][channel] - left[1][channel]) * local)) for channel in range(4))
        for x in range(w):
            pixels[x, y] = color
    return img


def radial_alpha(size: tuple[int, int], center: tuple[float, float], radius: float, alpha: int) -> Image.Image:
    w, h = size
    cx, cy = px(center[0]), px(center[1])
    max_radius = px(radius)
    mask = Image.new("L", size, 0)
    pixels = mask.load()
    for y in range(h):
        for x in range(w):
            dx = x - cx
            dy = y - cy
            distance = (dx * dx + dy * dy) ** 0.5
            if distance < max_radius:
                falloff = 1 - (distance / max_radius)
                pixels[x, y] = max(pixels[x, y], int(alpha * falloff * falloff))
    return mask


def paste_solid(img: Image.Image, mask: Image.Image, color: tuple[int, int, int, int], blur: float = 0) -> None:
    layer = Image.new("RGBA", img.size, color)
    alpha = mask.filter(ImageFilter.GaussianBlur(px(blur))) if blur else mask
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), alpha))
    img.alpha_composite(layer)


def paste_gradient(img: Image.Image, mask: Image.Image, gradient: Image.Image, blur: float = 0) -> None:
    alpha = mask.filter(ImageFilter.GaussianBlur(px(blur))) if blur else mask
    layer = gradient.copy()
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), alpha))
    img.alpha_composite(layer)


def tint_copy(source: Image.Image, color: tuple[int, int, int, int]) -> Image.Image:
    img = source.copy()
    alpha = img.getchannel("A")
    paste_solid(img, alpha, color)
    return img


def stroke_round(
    img: Image.Image,
    rect: dict,
    color: tuple[int, int, int, int],
    width: float = 1,
    grow: float = 0,
    radius_delta: float = 0,
    blur: float = 0,
) -> None:
    x0, y0, x1, y1 = box_px(rect)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(
        [x0 - px(grow), y0 - px(grow), x1 + px(grow), y1 + px(grow)],
        radius=max(1, radius_px(rect) + px(radius_delta)),
        outline=color,
        width=max(1, px(width)),
    )
    if blur:
        layer = layer.filter(ImageFilter.GaussianBlur(px(blur)))
    img.alpha_composite(layer)


def fill_round(img: Image.Image, rect: dict, color: tuple[int, int, int, int], grow: float = 0, blur: float = 0) -> None:
    mask = rounded_mask(img.size, rect, grow=grow)
    paste_solid(img, mask, color, blur=blur)


def fill_round_gradient(img: Image.Image, rect: dict, stops: list[tuple[float, tuple[int, int, int, int]]], grow: float = 0, blur: float = 0) -> None:
    mask = rounded_mask(img.size, rect, grow=grow)
    paste_gradient(img, mask, vertical_gradient(img.size, stops), blur=blur)


def ring_mask(size: tuple[int, int], outer_rect: dict, inner_rect: dict | None = None, grow: float = 0) -> Image.Image:
    outer = rounded_mask(size, outer_rect, grow=grow, radius_delta=grow)
    if inner_rect is None:
        inner = rounded_mask(size, outer_rect, grow=-grow, radius_delta=-grow)
    else:
        inner = rounded_mask(size, inner_rect)
    return ImageChops.subtract(outer, inner)


def bevel_ring(img: Image.Image, outer_rect: dict, inner_rect: dict, light: int = 58, shadow: int = 118) -> None:
    ring = ring_mask(img.size, outer_rect, inner_rect)
    paste_gradient(
        img,
        ring,
        vertical_gradient(
            img.size,
            [
                (0.00, (255, 255, 255, light)),
                (0.42, (255, 255, 255, max(10, light // 3))),
                (0.62, (0, 0, 0, max(28, shadow // 2))),
                (1.00, (0, 0, 0, shadow)),
            ],
        ),
    )
    # Keep the outer silhouette soft. A bright continuous contour reads like
    # app-window chrome once the shell is composited over a transparent panel.
    stroke_round(img, outer_rect, (255, 255, 255, max(4, light // 5)), width=0.35)
    stroke_round(img, inner_rect, (0, 0, 0, shadow), width=1.2, blur=0.15)


def rect_from_box(x: float, y: float, width: float, height: float, radius: float) -> dict:
    return {"x": x, "y": y, "width": width, "height": height, "radius": radius}


def inflated_rect(rect: dict, dx: float, dy: float, radius_delta: float = 0) -> dict:
    return {
        "x": rect["x"] - dx,
        "y": rect["y"] - dy,
        "width": rect["width"] + dx * 2,
        "height": rect["height"] + dy * 2,
        "radius": max(1, rect["radius"] + radius_delta),
    }


def socket_underlap_rect(rect: dict, bottom: float, horizontal: float = 0, radius_delta: float = 0) -> dict:
    return {
        "x": rect["x"] - horizontal,
        "y": rect["y"],
        "width": rect["width"] + horizontal * 2,
        "height": rect["height"] + bottom,
        "radius": max(1, rect["radius"] + radius_delta),
    }


def glow_line(img: Image.Image, points: list[tuple[int, int]], color: tuple[int, int, int, int], width: int = 1, blur: float = 0) -> None:
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).line(points, fill=color, width=width)
    if blur:
        layer = layer.filter(ImageFilter.GaussianBlur(px(blur)))
    img.alpha_composite(layer)


def fit_render_source() -> Image.Image | None:
    if not RENDER_SOURCE_PATH.exists():
        return None

    source = Image.open(RENDER_SOURCE_PATH).convert("RGBA")
    rgb = source.convert("RGB")
    red, green, blue = rgb.split()
    bright = ImageChops.lighter(ImageChops.lighter(red, green), blue)
    bbox = bright.point(lambda value: 255 if value > 7 else 0).getbbox()
    if bbox is None:
        return None

    pad = 18
    x0, y0, x1, y1 = bbox
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(source.width, x1 + pad)
    y1 = min(source.height, y1 + pad)
    crop = source.crop((x0, y0, x1, y1))

    side = max(crop.width, crop.height)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.alpha_composite(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
    return square.resize(size_px(), Image.Resampling.LANCZOS)


def fit_alpha_source(path: Path, pad: int = 6) -> Image.Image | None:
    if not path.exists():
        return None

    source = Image.open(path).convert("RGBA")
    bbox = source.getchannel("A").point(lambda value: 255 if value > 8 else 0).getbbox()
    if bbox is None:
        return None

    x0, y0, x1, y1 = bbox
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(source.width, x1 + pad)
    y1 = min(source.height, y1 + pad)
    crop = source.crop((x0, y0, x1, y1))

    side = max(crop.width, crop.height)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.alpha_composite(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
    return square.resize(size_px(), Image.Resampling.LANCZOS)


def build_outer_shell_render_layer() -> Image.Image | None:
    render = fit_alpha_source(OUTER_RENDER_SOURCE_PATH)
    if render is None:
        return None

    size = size_px()
    shell_mask = rounded_mask(size, BP["shell"], grow=-0.75, radius_delta=-0.75)

    # Keep the generated hardware under the live UI. Earlier versions cut the
    # render out behind the LCD and transport wells, which left SwiftUI drawing
    # giant procedural black plates. The render should own those sockets.
    render_strength = Image.new("L", size, int(255 * 0.90))
    alpha = ImageChops.multiply(render.getchannel("A"), shell_mask)
    alpha = ImageChops.multiply(alpha, render_strength)
    render.putalpha(alpha)
    return render


def clean_outer_silhouette(img: Image.Image) -> None:
    shell = BP["shell"]
    # Discipline only the contour. Keep this as a soft darkened silhouette,
    # not a visible stroke; a continuous bright edge makes the render look
    # like a fake app-window outline instead of smoked plastic.
    edge_band = ImageChops.subtract(
        rounded_mask(img.size, shell, grow=0.25, radius_delta=0.25),
        rounded_mask(img.size, shell, grow=-2.8, radius_delta=-2.8))
    paste_solid(img, edge_band, (0, 0, 0, 118), blur=0.22)
    stroke_round(img, shell, (0, 0, 0, 138), width=1.2, grow=0.15, radius_delta=0.15, blur=0.45)


def mute_bright_top_contour(img: Image.Image) -> None:
    """Suppress render highlights that trace the top silhouette.

    The imagegen shell source has a bright, nearly continuous top rim. In the
    app it reads less like transparent plastic and more like a fake rounded
    window border. Target only bright pixels in the crown band so interior
    screws, ribs, and smoky material stay intact.
    """
    size = img.size
    w, h = size
    rgb = img.convert("RGB")
    red, green, blue = rgb.split()
    bright = ImageChops.lighter(ImageChops.lighter(red, green), blue)
    bright_mask = bright.point(lambda value: 255 if value > 58 else 0)

    crown = Image.new("L", size, 0)
    pixels = crown.load()
    crown_height = px(34)
    for y in range(min(h, crown_height)):
        t = 1 - (y / max(1, crown_height - 1))
        alpha = int(190 * (t ** 1.25))
        for x in range(w):
            pixels[x, y] = alpha

    shell_mask = rounded_mask(size, BP["shell"], grow=-0.3, radius_delta=-0.3)
    mute = ImageChops.multiply(ImageChops.multiply(bright_mask, crown), shell_mask)
    paste_solid(img, mute, (0, 0, 0, 154), blur=0.55)


def build_render_source_underlay() -> Image.Image | None:
    img = fit_render_source()
    if img is None:
        return None

    size = size_px()
    shell_mask = rounded_mask(size, BP["shell"])
    img.putalpha(ImageChops.multiply(img.getchannel("A"), shell_mask))

    # The render gives us real smoked-plastic material. The blueprint still
    # owns the apertures, so wipe generated socket drift before the procedural
    # lips are composited above live SwiftUI.
    fill_round_gradient(
        img,
        inflated_rect(BP["rail"], 8, 5, 3),
        [(0.00, (5, 6, 7, 218)), (1.00, (0, 0, 0, 224))],
        blur=0.35,
    )
    fill_round_gradient(
        img,
        inflated_rect(BP["hudLcd"], 4, 5, 3),
        [(0.00, (11, 13, 15, 150)), (0.36, (0, 0, 0, 166)), (1.00, (0, 0, 0, 150))],
        blur=0.35,
    )
    fill_round_gradient(
        img,
        inflated_rect(BP["hudTransport"], 4, 6, 3),
        [(0.00, (13, 15, 17, 194)), (0.50, (2, 4, 6, 210)), (1.00, (0, 0, 0, 224))],
        blur=0.25,
    )

    # Reassert exact shell pocket darkness without erasing the render's outer
    # corner hardware and side molded rails.
    fill_round_gradient(img, BP["rail"], [(0.00, (7, 8, 9, 226)), (1.00, (0, 0, 0, 214))])
    fill_round_gradient(img, BP["hudLcd"], [(0.00, (12, 14, 16, 142)), (1.00, (0, 0, 0, 138))], grow=1)
    fill_round_gradient(img, BP["hudTransport"], [(0.00, (13, 15, 17, 224)), (0.55, (3, 5, 7, 232)), (1.00, (0, 0, 0, 238))], grow=1)

    w, _ = size
    shelf_y = BP["hudTransport"]["y"] - 4
    glow_line(img, [(px(58), px(shelf_y)), (w - px(58), px(shelf_y))], (255, 255, 255, 26), width=1)
    glow_line(img, [(px(58), px(shelf_y + 2)), (w - px(58), px(shelf_y + 2))], (0, 0, 0, 84), width=1, blur=0.12)
    return img


def build_underlay() -> Image.Image:
    size = size_px()
    w, h = size
    shell = BP["shell"]
    content = BP["content"]
    rail = BP["rail"]
    lcd = BP["hudLcd"]
    transport = BP["hudTransport"]
    outer_render = build_outer_shell_render_layer()
    shell_mask = (
        outer_render.getchannel("A").point(lambda value: 0 if value <= 2 else value)
        if outer_render is not None
        else rounded_mask(size, shell)
    )
    final_mask = visible_hardware_mask(size, outer_render)

    img = Image.new("RGBA", size, (0, 0, 0, 0))

    shell_gradient = vertical_gradient(
        size,
        [
            (0.00, (16, 18, 20, 246)),
            (0.16, (8, 10, 12, 250)),
            (0.52, (2, 4, 6, 252)),
            (0.82, (8, 10, 12, 249)),
            (1.00, (1, 3, 5, 252)),
        ],
    )
    paste_gradient(img, shell_mask, shell_gradient)

    top_smoke = radial_alpha(size, (80, 28), 120, 72)
    bottom_smoke = radial_alpha(size, (300, 424), 190, 34)
    paste_solid(img, ImageChops.multiply(top_smoke, shell_mask), (255, 255, 255, 76))
    paste_solid(img, ImageChops.multiply(bottom_smoke, shell_mask), (255, 255, 255, 38))

    noise = Image.effect_noise(size, 11).convert("L")
    noise_alpha = ImageChops.multiply(shell_mask, noise.point(lambda value: max(0, min(18, value // 12))))
    paste_solid(img, noise_alpha, (255, 255, 255, 28))

    # The content tray is a recessed slab below SwiftUI content. Keep it dark
    # and straight so the overlaid UI reads as fitted into the object.
    fill_round_gradient(
        img,
        content,
        [
            (0.00, (9, 11, 13, 92)),
            (0.34, (0, 0, 0, 120)),
            (0.72, (0, 0, 0, 92)),
            (1.00, (10, 12, 14, 76)),
        ],
        blur=1.4,
    )
    # These fills sit below the generated plastic render, not above it. That
    # keeps wallpaper from bleeding through the live UI sockets while the
    # molded render still owns the visible lip/edge detail.
    fill_round_gradient(
        img,
        socket_underlap_rect(rail, bottom=10, horizontal=0.2),
        [(0.00, (7, 8, 9, 252)), (1.00, (0, 0, 0, 250))],
        blur=0.06)
    fill_round_gradient(
        img,
        socket_underlap_rect(lcd, bottom=16, horizontal=0.4),
        [(0.00, (12, 14, 16, 248)), (0.55, (0, 0, 0, 252)), (1.00, (0, 0, 0, 250))],
        grow=0.55,
        blur=0.18)
    fill_round_gradient(
        img,
        socket_underlap_rect(transport, bottom=13, horizontal=0.3),
        [(0.00, (13, 15, 17, 250)), (0.55, (3, 5, 7, 252)), (1.00, (0, 0, 0, 252))],
        grow=0.55,
        blur=0.12)

    if outer_render is not None:
        img.alpha_composite(outer_render)
        clean_outer_silhouette(img)
        mute_bright_top_contour(img)

    bevel_ring(img, shell, content, light=32, shadow=118)

    # Side molded rails and latch blocks. These sit outside the live UI sockets.
    # Skip them when the outer render is present so we do not double-print
    # fasteners or side latch geometry over the bitmap source.
    d = ImageDraw.Draw(img)
    if outer_render is None:
        for x in (px(10), w - px(24)):
            d.rounded_rectangle([x, px(74), x + px(14), h - px(70)], radius=px(7), fill=(0, 0, 0, 78), outline=(255, 255, 255, 24), width=1)
            for y in (88, 136, 190, 246, 306):
                d.rounded_rectangle([x + px(2), px(y), x + px(12), px(y + 30)], radius=px(5), fill=(11, 13, 15, 132), outline=(255, 255, 255, 34), width=1)
                d.line([(x + px(4), px(y + 3)), (x + px(10), px(y + 3))], fill=(255, 255, 255, 28), width=1)

        for x, y in ((27, 43), (413, 43), (27, 392), (413, 392)):
            cx, cy = px(x), px(y)
            d.ellipse([cx - px(4.5), cy - px(4.5), cx + px(4.5), cy + px(4.5)], fill=(0, 0, 0, 190), outline=(255, 255, 255, 24), width=1)
            d.line([(cx - px(2.4), cy + px(2.4)), (cx + px(2.4), cy - px(2.4))], fill=(255, 255, 255, 28), width=1)

    # Controlled plastic glints, mostly top-left like the app icon.
    gloss = Image.new("L", size, 0)
    gd = ImageDraw.Draw(gloss)
    gd.ellipse([px(-42), px(-18), px(130), px(98)], fill=96)
    gd.ellipse([px(18), px(12), px(78), px(74)], fill=92)
    # Broken crown glints preserve molded plastic without tracing a window-like
    # top silhouette across the whole app.
    for x0, x1, alpha in ((70, 138, 20), (198, 286, 15), (528, 636, 16)):
        gd.rounded_rectangle([px(x0), px(12), px(x1), px(18)], radius=px(2.5), fill=alpha)
    gd.rounded_rectangle([px(72), h - px(23), w - px(70), h - px(15)], radius=px(4), fill=18)
    gloss = ImageChops.multiply(gloss.filter(ImageFilter.GaussianBlur(px(6))), shell_mask)
    paste_solid(img, gloss, (255, 255, 255, 70))

    trim_to_shell_alpha(img, final_mask)
    return img


def aperture_lip(img: Image.Image, rect: dict, strength: float = 1.0, transport: bool = False) -> None:
    x0, y0, x1, y1 = box_px(rect)
    radius = radius_px(rect)
    shadow = int(150 * strength)
    edge = int(68 * strength)
    hi = int(84 * strength)

    stroke_round(img, rect, (0, 0, 0, shadow), width=2.8, grow=3, radius_delta=3, blur=0.8)
    stroke_round(img, rect, (255, 255, 255, edge), width=0.5, grow=1.5, radius_delta=1.5)
    stroke_round(img, rect, (0, 0, 0, int(146 * strength)), width=1.4, blur=0.1)
    stroke_round(img, rect, (255, 255, 255, hi), width=0.45, grow=-0.45, radius_delta=-0.45)
    stroke_round(img, rect, (0, 0, 0, int(88 * strength)), width=0.65, grow=-2.2, radius_delta=-2.2, blur=0.1)

    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.line([(x0 + px(12), y0 + px(4)), (x1 - px(12), y0 + px(4))], fill=(255, 255, 255, int(52 * strength)), width=1)
    d.line([(x0 + px(12), y0 + px(7)), (x1 - px(12), y0 + px(7))], fill=(0, 0, 0, int(58 * strength)), width=1)
    d.line([(x0 + px(11), y1 - px(5)), (x1 - px(11), y1 - px(5))], fill=(0, 0, 0, int(46 * strength)), width=1)
    if transport:
        d.line([(x0 + px(14), y1 - px(3)), (x1 - px(14), y1 - px(3))], fill=(255, 255, 255, int(30 * strength)), width=1)
        d.line([(x0 + px(12), y1 - px(1)), (x1 - px(12), y1 - px(1))], fill=(0, 0, 0, int(110 * strength)), width=1)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(px(0.08))))


def build_overlay(mode: str) -> Image.Image:
    # Aperture lips used to live here. Once the shell render owned the visible
    # hardware, the remaining outer rounded stroke became a fake floating app
    # outline. Return an empty layer so the bitmap render, not procedural
    # window chrome, defines the edge.
    return Image.new("RGBA", size_px(), (0, 0, 0, 0))


def fill_well_material(img: Image.Image, rect: dict, strength: float = 1.0, transport: bool = False) -> None:
    mask = rounded_mask(img.size, rect, grow=-1, radius_delta=-1)

    paste_gradient(
        img,
        mask,
        vertical_gradient(
            img.size,
            [
                (0.00, (34, 36, 38, int(58 * strength))),
                (0.18, (10, 11, 12, int(38 * strength))),
                (0.68, (0, 0, 0, int(18 * strength))),
                (1.00, (255, 255, 255, int(9 * strength))),
            ],
        ),
        blur=0.12,
    )

    x0, y0, x1, y1 = box_px(rect)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # Fine molded-plastic ribs. These should read as material when the panel
    # fill is slightly translucent, not as a visible stripe pattern.
    spacing = px(9 if transport else 10)
    start_y = y0 + px(9)
    end_y = y1 - px(8)
    y = start_y
    while y < end_y:
        d.line(
            [(x0 + px(12), y), (x1 - px(12), y)],
            fill=(255, 255, 255, int(9 * strength)),
            width=1)
        y += spacing

    # Subtle internal ribs and molded stops near the long edges. Kept away
    # from the live UI center so text and spectrum stay clean.
    for x in (x0 + px(20), x1 - px(20)):
        d.line(
            [(x, y0 + px(14)), (x, min(y1 - px(14), y0 + px(62)))],
            fill=(255, 255, 255, int(13 * strength)),
            width=1)
        d.line(
            [(x, max(y0 + px(14), y1 - px(62))), (x, y1 - px(14))],
            fill=(0, 0, 0, int(36 * strength)),
            width=1)

    if transport:
        d.line(
            [(x0 + px(42), y0 + px(12)), (x1 - px(42), y0 + px(12))],
            fill=(255, 255, 255, int(20 * strength)),
            width=1)
        d.line(
            [(x0 + px(42), y1 - px(9)), (x1 - px(42), y1 - px(9))],
            fill=(0, 0, 0, int(70 * strength)),
            width=1)

    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(px(0.06))))


def build_wells(mode: str) -> Image.Image:
    img = Image.new("RGBA", size_px(), (0, 0, 0, 0))

    if mode == "hud":
        fill_well_material(img, BP["hudLcd"], 1.0)
        fill_well_material(img, BP["hudTransport"], 1.0, transport=True)
    elif mode == "hud-no-transport":
        fill_well_material(img, BP["hudNoTransportLcd"], 1.0)
    elif mode == "full":
        fill_well_material(img, BP["fullLcd"], 0.92)

    return img


def build_reflections() -> Image.Image:
    size = size_px()
    w, h = size
    shell_mask = rounded_mask(size, BP["shell"])
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    gloss = Image.new("L", size, 0)
    d = ImageDraw.Draw(gloss)
    # Reflections should look embedded in the smoked plastic. Avoid strokes
    # that trace the outer contour; those read as a fake app-window outline.
    d.arc([px(18), px(16), px(94), px(92)], 196, 274, fill=68, width=px(0.9))
    for x0, x1, alpha in ((112, 170, 26), (246, 332, 22), (524, 610, 20)):
        d.line([(px(x0), px(18)), (px(x1), px(18))], fill=alpha, width=1)
    d.line([(px(15), px(76)), (px(15), h - px(78))], fill=28, width=1)
    d.line([(px(26), px(66)), (px(26), h - px(88))], fill=18, width=1)
    d.line([(px(74), px(318)), (w - px(72), px(318))], fill=22, width=1)
    gloss = ImageChops.multiply(gloss.filter(ImageFilter.GaussianBlur(px(0.18))), shell_mask)
    paste_solid(img, gloss, (255, 255, 255, 112))
    return img


def capsule_mask(size: tuple[int, int], inset: int = 0) -> Image.Image:
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([inset, inset, size[0] - 1 - inset, size[1] - 1 - inset], radius=(size[1] - inset * 2) // 2, fill=255)
    return mask


def save_capsule_asset(name: str, points: tuple[float, float], kind: str) -> None:
    size = (px(points[0]), px(points[1]))
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    outer = capsule_mask(size, 1)
    inner = capsule_mask(size, 6)
    paste_solid(img, outer, (0, 0, 0, 132), blur=0.55)
    paste_solid(img, outer, (255, 255, 255, 24 if kind == "button" else 16))
    paste_gradient(
        img,
        inner,
        vertical_gradient(
            size,
            [
                (0.00, (26, 28, 30, 132)),
                (0.38, (7, 9, 11, 158)),
                (1.00, (0, 0, 0, 188)),
            ],
        ),
        blur=0.18,
    )
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([5, 4, size[0] - 6, 7], radius=2, fill=(255, 255, 255, 13 if kind == "button" else 8))
    d.rounded_rectangle([size[0] * 0.28, size[1] - 9, size[0] * 0.72, size[1] - 6], radius=2, fill=(255, 255, 255, 6))
    img.save(OUT / f"{name}.png")


def build_faceplate() -> None:
    size = (px(340), px(73))
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.line([(px(8), px(7)), (w - px(8), px(7))], fill=(255, 255, 255, 34), width=1)
    d.line([(px(12), h - px(8)), (w - px(12), h - px(8))], fill=(0, 0, 0, 108), width=1)
    d.line([(px(20), px(13)), (w - px(20), px(13))], fill=(255, 255, 255, 13), width=1)
    for x, y in ((18, 16), (322, 16), (18, 61), (322, 61)):
        cx, cy = px(x), px(y)
        d.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=(0, 0, 0, 90), outline=(255, 255, 255, 34), width=1)
    img.save(OUT / "transport-faceplate.png")


def save_shell_variants(base_assets: dict[str, Image.Image]) -> None:
    for skin, colors in SHELL_TINTS.items():
        chassis = tint_copy(base_assets["chassis"], colors["chassis"])
        reflections = tint_copy(base_assets["reflections"], colors["reflection"])
        chassis.save(OUT / f"shell-{skin}-chassis.png")
        reflections.save(OUT / f"shell-{skin}-reflections.png")
        preview_apertures = None
        preview_wells = None
        for mode_name in ("wells-hud", "wells-hud-no-transport", "wells-full"):
            wells = tint_copy(base_assets[mode_name], colors["aperture"])
            wells.save(OUT / f"shell-{skin}-{mode_name}.png")
            if mode_name == "wells-hud":
                preview_wells = wells
        for mode_name in ("apertures-hud", "apertures-hud-no-transport", "apertures-full"):
            apertures = tint_copy(base_assets[mode_name], colors["aperture"])
            apertures.save(OUT / f"shell-{skin}-{mode_name}.png")
            if mode_name == "apertures-hud":
                preview_apertures = apertures
        if preview_apertures is not None and preview_wells is not None:
            composite = chassis.copy()
            composite.alpha_composite(preview_wells)
            composite.alpha_composite(fake_ui())
            composite.alpha_composite(preview_apertures)
            composite.alpha_composite(reflections)
            composite.save(PREVIEW_DIR / f"hardware-static-composite-{skin}.png")


def build_guide() -> Image.Image:
    size = size_px()
    img = Image.new("RGBA", size, (8, 10, 12, 255))
    d = ImageDraw.Draw(img)
    colors = {
        "shell": (90, 190, 255, 255),
        "content": (255, 255, 255, 175),
        "rail": (0, 210, 255, 255),
        "hudLcd": (255, 60, 194, 255),
        "hudTransport": (165, 255, 35, 255),
    }
    for key in ("shell", "content", "rail", "hudLcd", "hudTransport"):
        rect = BP[key]
        d.rounded_rectangle(box_px(rect), radius=radius_px(rect), outline=colors[key], width=2)
        d.text((box_px(rect)[0] + 6, box_px(rect)[1] + 5), key, fill=colors[key])
    d.line([(size[0] // 2, 0), (size[0] // 2, size[1])], fill=(255, 255, 255, 100), width=1)
    d.line([(0, size[1] // 2), (size[0], size[1] // 2)], fill=(255, 255, 255, 100), width=1)
    return img


def fake_ui() -> Image.Image:
    size = size_px()
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rail = BP["rail"]
    lcd = BP["hudLcd"]
    transport = BP["hudTransport"]
    rail_x0, rail_y0, rail_x1, rail_y1 = box_px(rail)
    d.rounded_rectangle(box_px(rail), radius=radius_px(rail), fill=(0, 0, 0, 180))
    d.text((rail_x0 + px(16), rail_y0 + px(12)), "NOW PLAYING", fill=(235, 235, 230, 230))
    for x in (rail_x1 - px(94), rail_x1 - px(62), rail_x1 - px(30)):
        d.ellipse([x, rail_y0 + px(12), x + px(7), rail_y0 + px(19)], outline=(235, 235, 230, 190), width=1)

    d.rounded_rectangle(box_px(lcd), radius=radius_px(lcd), fill=(12, 14, 15, 235), outline=(255, 255, 255, 35), width=1)
    d.rounded_rectangle([px(42), px(84), px(102), px(144)], radius=px(8), fill=(200, 205, 184, 220))
    d.text((px(118), px(88)), "TRACK TITLE", fill=(245, 245, 240, 230))
    d.text((px(118), px(108)), "Artist / Album", fill=(170, 174, 178, 220))
    d.rounded_rectangle([px(42), px(166), px(398), px(212)], radius=px(8), outline=(255, 255, 255, 38), width=1)
    for i in range(46):
        height = 6 + (i * 7) % 38
        d.rectangle([px(42 + i * 7), px(292 - height), px(46 + i * 7), px(292)], fill=(220, 220, 214, 210))

    d.rounded_rectangle(box_px(transport), radius=radius_px(transport), fill=(7, 9, 11, 232), outline=(255, 255, 255, 32), width=1)
    d.line([(px(72), px(346)), (px(368), px(346))], fill=(230, 230, 226, 190), width=px(2))
    for x, w in ((76, 38), (150, 44), (216, 58), (296, 44), (358, 38)):
        d.rounded_rectangle([px(x), px(366), px(x + w), px(396)], radius=px(15), fill=(16, 18, 20, 245), outline=(255, 255, 255, 42), width=1)
    return img


def main() -> None:
    # Imagegen render sources are useful reference material, but they should
    # not define live socket geometry. Keep the app assets blueprint-driven so
    # Stats/Pet/Playback keep the same proven apertures and control wells.
    underlay = build_underlay()
    underlay.save(OUT / "shell-smoke-chassis.png")
    outer_render = build_outer_shell_render_layer()
    if outer_render is not None:
        outer_render.save(PREVIEW_DIR / "smoke-shell-outer-render-fitted-v2.png")
    reflections = build_reflections()
    reflections.save(OUT / "shell-smoke-reflections.png")
    wells_hud = build_wells("hud")
    wells_hud.save(OUT / "shell-smoke-wells-hud.png")
    wells_hud_no_transport = build_wells("hud-no-transport")
    wells_hud_no_transport.save(OUT / "shell-smoke-wells-hud-no-transport.png")
    wells_full = build_wells("full")
    wells_full.save(OUT / "shell-smoke-wells-full.png")
    apertures_hud = build_overlay("hud")
    apertures_hud.save(OUT / "shell-smoke-apertures-hud.png")
    apertures_hud_no_transport = build_overlay("hud-no-transport")
    apertures_hud_no_transport.save(OUT / "shell-smoke-apertures-hud-no-transport.png")
    apertures_full = build_overlay("full")
    apertures_full.save(OUT / "shell-smoke-apertures-full.png")
    save_shell_variants({
        "chassis": underlay,
        "reflections": reflections,
        "wells-hud": wells_hud,
        "wells-hud-no-transport": wells_hud_no_transport,
        "wells-full": wells_full,
        "apertures-hud": apertures_hud,
        "apertures-hud-no-transport": apertures_hud_no_transport,
        "apertures-full": apertures_full,
    })

    save_capsule_asset("transport-well-utility", (38, 28), "well")
    save_capsule_asset("transport-well-button", (44, 31), "well")
    save_capsule_asset("transport-well-play", (58, 35), "well")
    save_capsule_asset("transport-button", (41.5, 28.5), "button")
    save_capsule_asset("transport-button-play", (55.5, 32.5), "button")
    build_faceplate()

    guide = build_guide()
    guide.save(PREVIEW_DIR / "hardware-guide.png")
    composite = underlay.copy()
    composite.alpha_composite(wells_hud)
    composite.alpha_composite(fake_ui())
    composite.alpha_composite(apertures_hud)
    composite.alpha_composite(reflections)
    composite.save(PREVIEW_DIR / "hardware-static-composite.png")


if __name__ == "__main__":
    main()
