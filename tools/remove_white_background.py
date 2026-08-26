#!/usr/bin/env python3
"""Remove a white background from a raster image while preserving the artwork."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def remove_white_background(source: Path, destination: Path) -> None:
    image = Image.open(source).convert("RGBA")
    pixels = []

    # The source uses a pure white canvas. Remove the bright antialiased edge
    # as well, while keeping the gray silhouettes and black title opaque.
    soft_threshold = 205
    hard_threshold = 230
    for red, green, blue, alpha in image.getdata():
        whiteness = min(red, green, blue)
        if whiteness >= hard_threshold:
            pixels.append((0, 0, 0, 0))
        elif whiteness > soft_threshold:
            edge_alpha = round(
                alpha * (hard_threshold - whiteness)
                / float(hard_threshold - soft_threshold)
            )
            pixels.append((red, green, blue, edge_alpha))
        else:
            pixels.append((red, green, blue, alpha))

    image.putdata(pixels)
    destination.parent.mkdir(parents=True, exist_ok=True)
    image.save(destination, format="PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    remove_white_background(args.source, args.destination)


if __name__ == "__main__":
    main()
