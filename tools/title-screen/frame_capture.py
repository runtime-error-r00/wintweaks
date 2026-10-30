"""Create WinUtil's framed Dark title-screen image.

WinUtil captures include a narrow near-black DWM shadow around the actual WPF
window. This module detects that shadow, crops it away, and draws the
title-screen border inside the remaining window image.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


BORDER_COLOR = (180, 180, 180, 255)
BORDER_WIDTH = 2
# DWM shadow pixels are nearly black. WinUtil's actual Dark theme remains above
# this threshold at the window edges used by the bounds scan.
BRIGHTNESS_THRESHOLD = 20
LARGE_SHADOW_MARGIN = 30


def _contains_content(pixel) -> bool:
    """Return whether a pixel is brighter than the near-black DWM shadow."""
    return any(channel > BRIGHTNESS_THRESHOLD for channel in pixel[:3])


def _find_content_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    """Return the non-shadow bounds detected from a Dark theme capture.

    Every edge coordinate is checked because Windows 11 shadows can be narrower
    than ten pixels. Sampling at a fixed interval could skip the first content
    pixel and trim real UI from the final image.
    """
    width, height = image.size
    pixels = image.load()

    left = next(
        (
            x
            for x in range(width)
            if any(_contains_content(pixels[x, y]) for y in range(height))
        ),
        0,
    )
    right = next(
        (
            x
            for x in range(width - 1, -1, -1)
            if any(_contains_content(pixels[x, y]) for y in range(height))
        ),
        width - 1,
    )
    top = next(
        (
            y
            for y in range(height)
            if any(_contains_content(pixels[x, y]) for x in range(width))
        ),
        0,
    )
    bottom = next(
        (
            y
            for y in range(height - 1, -1, -1)
            if any(_contains_content(pixels[x, y]) for x in range(width))
        ),
        height - 1,
    )

    right_margin = width - right - 1
    bottom_margin = height - bottom - 1
    margins = (left, top, right_margin, bottom_margin)
    if any(margin > LARGE_SHADOW_MARGIN for margin in margins):
        print(
            "Warning: unusually large shadow margins detected "
            f"(left={left}, top={top}, right={right_margin}, "
            f"bottom={bottom_margin}). Input image may already be cropped or "
            "framed."
        )

    return left, top, right + 1, bottom + 1


def _apply_frame(image: Image.Image) -> Image.Image:
    """Return a copy with the title-screen border drawn inside its bounds."""
    framed = image.copy()
    width, height = framed.size
    draw = ImageDraw.Draw(framed)
    for inset in range(BORDER_WIDTH):
        draw.rectangle(
            [inset, inset, width - 1 - inset, height - 1 - inset],
            outline=BORDER_COLOR,
        )
    return framed


def frame_capture(
    dark_path: str | Path,
    output_path: str | Path,
) -> Path:
    """Crop the DWM shadow from a Dark capture and write the framed image."""
    dark_path = Path(dark_path)
    output_path = Path(output_path)

    with Image.open(dark_path) as dark_source:
        dark_image = dark_source.convert("RGBA")

    crop_box = _find_content_bounds(dark_image)
    print(f"Content crop box (stripping DWM shadow): {crop_box}")

    framed = _apply_frame(dark_image.crop(crop_box))
    framed.save(output_path, "PNG")

    print(f"Generated title screen: {output_path} ({framed.width}x{framed.height})")
    return output_path


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create WinUtil's framed Dark title-screen image."
    )
    parser.add_argument("dark", type=Path, help="Raw Dark theme PNG")
    parser.add_argument("output", type=Path, help="Destination PNG")
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    frame_capture(args.dark, args.output)


if __name__ == "__main__":
    main()
