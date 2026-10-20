#!/usr/bin/env python3
"""
Import the functional chrome icons from Iconoir into Dial's PNG template set.

The app keeps `DialIcon("sf.symbol.name")` call sites for readability, but the
actual bundled art comes from Iconoir. Pixel art stays reserved for badges,
the pet, and LCD-specific artifacts.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

ICONOIR_VERSION = "7.11.0"
REPO_ROOT = Path(__file__).resolve().parents[1]
TMP_DIR = REPO_ROOT / "tmp" / "iconoir"
PACKAGE_DIR = TMP_DIR / "package"
OUT_DIR = REPO_ROOT / "Dial" / "Resources" / "Icons"
SOURCE_DIR = REPO_ROOT / "output" / "iconoir-source-svgs"

STROKE_WIDTH = "1.9"
PNG_SIZE = 256

ICON_MAP: dict[str, tuple[str, str]] = {
    "clock.arrow.circlepath": ("regular", "clock-rotate-right"),
    "chart.bar.fill": ("regular", "reports"),
    "gearshape.fill": ("regular", "settings"),
    "info.circle": ("regular", "info-circle"),
    "xmark.circle": ("regular", "xmark-circle"),
    "checkmark.circle": ("regular", "check-circle"),
    "questionmark.circle": ("regular", "help-circle"),
    "chevron.left": ("regular", "nav-arrow-left"),
    "music.note": ("regular", "music-note"),
    "menubar.rectangle": ("regular", "menu-scale"),
    "rectangle.inset.filled": ("regular", "app-window"),
    "sparkles": ("regular", "sparks"),
    "heart": ("regular", "heart"),
    "heart.fill": ("solid", "heart"),
    "heart.slash": ("custom", "heart-slash"),
    "shuffle": ("regular", "shuffle"),
    "repeat": ("regular", "repeat"),
    "repeat.1": ("regular", "repeat-once"),
    "backward.fill": ("solid", "skip-prev"),
    "play.fill": ("solid", "play"),
    "pause.fill": ("solid", "pause"),
    "forward.fill": ("solid", "skip-next"),
    "flame.fill": ("regular", "fire-flame"),
    "triangle.fill": ("regular", "triangle"),
    "speaker.slash.fill": ("regular", "sound-off"),
    "speaker.wave.1.fill": ("regular", "sound-low"),
    "speaker.wave.3.fill": ("regular", "sound-high"),
    "exclamationmark.triangle": ("regular", "warning-triangle"),
}


def main() -> int:
    require_tool("npm")
    require_tool("rsvg-convert")
    ensure_iconoir_package()
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for target, (style, name) in ICON_MAP.items():
        svg = custom_heart_slash() if style == "custom" else source_svg(style, name)
        svg = normalize_svg(svg, stroke_width=STROKE_WIDTH)
        svg_path = SOURCE_DIR / f"{target}.svg"
        png_path = OUT_DIR / f"{target}.png"
        svg_path.write_text(svg)
        render_png(svg_path, png_path)
        print(f"{target:24s} <- {style}/{name}")

    write_notice()
    return 0


def require_tool(name: str) -> None:
    if shutil.which(name) is None:
        raise SystemExit(f"missing required tool: {name}")


def ensure_iconoir_package() -> None:
    if (PACKAGE_DIR / "icons" / "regular").exists():
        return

    TMP_DIR.mkdir(parents=True, exist_ok=True)
    tarball = TMP_DIR / f"iconoir-{ICONOIR_VERSION}.tgz"
    if not tarball.exists():
        subprocess.run(
            ["npm", "pack", f"iconoir@{ICONOIR_VERSION}", "--pack-destination", str(TMP_DIR)],
            check=True,
        )
    with tarfile.open(tarball) as archive:
        archive.extractall(TMP_DIR)


def source_svg(style: str, name: str) -> str:
    path = PACKAGE_DIR / "icons" / style / f"{name}.svg"
    if not path.exists():
        raise SystemExit(f"missing Iconoir source: {style}/{name}.svg")
    return path.read_text()


def custom_heart_slash() -> str:
    heart = source_svg("regular", "heart")
    slash = '<path d="M5 19L19 5" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"/>'
    return heart.replace("</svg>", f"{slash}</svg>")


def normalize_svg(svg: str, stroke_width: str) -> str:
    svg = svg.replace("currentColor", "#000000")
    svg = re.sub(r'stroke-width="[0-9.]+"', f'stroke-width="{stroke_width}"', svg)
    # Solid icons often rely on fill="currentColor"; regular icons should keep
    # fill="none". The replacement above handles both without changing shape.
    return svg


def render_png(svg_path: Path, png_path: Path) -> None:
    subprocess.run(
        [
            "rsvg-convert",
            "-w",
            str(PNG_SIZE),
            "-h",
            str(PNG_SIZE),
            "-o",
            str(png_path),
            str(svg_path),
        ],
        check=True,
    )


def write_notice() -> None:
    notice = REPO_ROOT / "THIRD_PARTY_NOTICES.md"
    iconoir_license = (PACKAGE_DIR / "LICENSE").read_text().strip()
    notice.write_text(
        "# Third-Party Notices\n\n"
        "## Iconoir\n\n"
        "Dial uses selected Iconoir icons for functional UI chrome.\n\n"
        "- Source: https://iconoir.com/\n"
        f"- npm package: `iconoir@{ICONOIR_VERSION}`\n"
        "- License: MIT\n\n"
        "```text\n"
        f"{iconoir_license}\n"
        "```\n"
    )


if __name__ == "__main__":
    raise SystemExit(main())
