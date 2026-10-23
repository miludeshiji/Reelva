#!/usr/bin/env python3
"""
Reelva Icon Generator
=====================

Generates Windows multiresolution ICO and Android launcher PNGs (legacy
and API 26+ adaptive icon foreground) from assets/Reelva.svg using resvg.

Dependencies:
    pip install resvg-py pillow

Workflow:
    Directly renders assets/Reelva.svg via resvg with geometric precision
    to preserve mathematical circular arcs.
    Adaptive foreground insets the rendered brand mark into a transparent
    canvas with safe margins, preserving the original black background and
    cutout to blend with @color/reelva_icon_background.
"""

import io
import sys
from pathlib import Path
from PIL import Image
import resvg_py

LEGACY_SIZES = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}

ADAPTIVE_SIZES = {
    'mdpi': 108,
    'hdpi': 162,
    'xhdpi': 216,
    'xxhdpi': 324,
    'xxxhdpi': 432,
}

ICO_SIZES = [
    (16, 16),
    (24, 24),
    (32, 32),
    (48, 48),
    (64, 64),
    (128, 128),
    (256, 256),
]

ADAPTIVE_SCALE = 0.72  # Safe inset inside adaptive icon canvas


def render_svg(svg_path: Path, width: int, height: int) -> Image.Image:
    """Renders the SVG at exact pixel dimensions using resvg."""
    png_bytes = resvg_py.svg_to_bytes(
        svg_path=str(svg_path),
        width=width,
        height=height,
        shape_rendering="geometric_precision",
    )
    return Image.open(io.BytesIO(png_bytes))


def generate_adaptive_foreground(svg_path: Path, size: int, scale: float) -> Image.Image:
    """Renders artwork with safe inset and centers it on a transparent canvas."""
    target_dim = int(round(size * scale))
    scaled_img = render_svg(svg_path, target_dim, target_dim)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    offset = (size - target_dim) // 2
    canvas.paste(scaled_img, (offset, offset))
    return canvas


def main():
    repo_root = Path(__file__).resolve().parent.parent
    svg_path = repo_root / "assets" / "Reelva.svg"
    if not svg_path.exists():
        print(f"Error: source SVG not found at {svg_path}", file=sys.stderr)
        sys.exit(1)

    generated_files = []

    # 1. Windows multiresolution ICO
    windows_res_dir = repo_root / "windows" / "runner" / "resources"
    windows_res_dir.mkdir(parents=True, exist_ok=True)
    ico_dest = windows_res_dir / "app_icon.ico"

    ico_images = [
        render_svg(svg_path, width, height)
        for width, height in ICO_SIZES
    ]
    ico_base = ico_images[-1]  # 256x256 image
    ico_base.save(
        ico_dest,
        format="ICO",
        sizes=ICO_SIZES,
        append_images=ico_images[:-1],
    )
    generated_files.append((ico_dest, ico_dest.stat().st_size))

    # 2. Android legacy icons (ic_launcher.png)
    res_dir = repo_root / "android" / "app" / "src" / "main" / "res"
    for density, size in LEGACY_SIZES.items():
        density_dir = res_dir / f"mipmap-{density}"
        density_dir.mkdir(parents=True, exist_ok=True)
        dest = density_dir / "ic_launcher.png"
        img = render_svg(svg_path, size, size)
        img.save(dest, format="PNG", optimize=True)
        generated_files.append((dest, dest.stat().st_size))

    # 3. Android adaptive foreground PNGs
    for density, size in ADAPTIVE_SIZES.items():
        density_dir = res_dir / f"mipmap-{density}"
        density_dir.mkdir(parents=True, exist_ok=True)
        dest = density_dir / "ic_launcher_foreground.png"
        img = generate_adaptive_foreground(svg_path, size, ADAPTIVE_SCALE)
        img.save(dest, format="PNG", optimize=True)
        generated_files.append((dest, dest.stat().st_size))

    # Print summary
    print(f"Generated {len(generated_files)} icon files:")
    for path, file_size in generated_files:
        rel_path = path.relative_to(repo_root)
        print(f"  {rel_path}: {file_size} bytes")


if __name__ == "__main__":
    main()
