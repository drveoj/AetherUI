"""Generate the two neutral texture layers used by AetherUI's level discs.

They stay greyscale/white so Widgets.lua can tint a player by class and an NPC
by reaction at runtime.  The rim and the diagonal light pass are separate on
purpose: one tinted source cannot keep a bright rim while retaining a dark,
readable face for every class.

Run from the addon root:
    python Tools/generate_level_disc_textures.py
"""

from math import sqrt
from pathlib import Path

from PIL import Image


SIZE = 128
MID = (SIZE - 1) / 2
OUTPUT = Path(__file__).resolve().parents[1] / "Media" / "Textures"


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def smoothstep(edge0, edge1, value):
    value = clamp((value - edge0) / (edge1 - edge0))
    return value * value * (3.0 - 2.0 * value)


def rim():
    """One substantial, anti-aliased circular rim -- no second hairline."""
    image = Image.new("RGBA", (SIZE, SIZE))
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            radius = sqrt((x - MID) ** 2 + (y - MID) ** 2)
            # A 9.5-source-pixel band becomes a visibly raised ~3.5px rim at
            # the standard 46px disc. The ramps remove the outer black fringe.
            outer = 1.0 - smoothstep(62.1, 63.6, radius)
            inner = smoothstep(52.8, 54.4, radius)
            alpha = round(255 * outer * inner)
            pixels[x, y] = (255, 255, 255, alpha)
    return image


def sheen():
    """A soft diagonal light falling over the inset circular face.

    This is intentionally baked into alpha rather than relying on Texture
    gradient APIs, whose result varies across Classic Era clients at this size.
    The outer fade aligns with rim()'s inner edge, so there is no extra border.
    """
    image = Image.new("RGBA", (SIZE, SIZE))
    pixels = image.load()
    for y in range(SIZE):
        for x in range(SIZE):
            dx, dy = x - MID, y - MID
            radius = sqrt(dx * dx + dy * dy)
            mask = 1.0 - smoothstep(51.2, 54.1, radius)
            # Broad top-left to bottom-right lighting, plus a gentle central
            # ridge. It reads as a rounded button, not a glossy glass marble.
            falloff = clamp(0.46 - (dx + dy) / 176.0, 0.12, 0.78)
            ridge = 1.0 - clamp(abs(dx + dy + 10.0) / 70.0)
            alpha = round(138 * mask * (0.62 * falloff + 0.38 * ridge))
            pixels[x, y] = (255, 255, 255, alpha)
    return image


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    rim().save(OUTPUT / "LevelDisc-Rim.tga")
    sheen().save(OUTPUT / "LevelDisc-Sheen.tga")


if __name__ == "__main__":
    main()
