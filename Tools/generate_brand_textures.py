# -*- coding: utf-8 -*-
"""The Lattice brand, drawn from its geometry.

    python Tools/generate_brand_textures.py

Writes every brand image from one set of shapes, so the README banner, the
store icons, the sub-brand lockups and what the client loads cannot drift apart:

    docs/brand/Lattice-Logo.png, -Logo-850x397.png, -Social.png, -Icon.png
    docs/brand/lattice-ifec-*.png, lattice-nifec-*.png
    Media/Textures/Logo.tga, Media/Textures/Icon.tga

DRAWN, NOT CUT OUT. AetherUI's mark arrived as finished PNGs and this script
used to peel the plate off them by subtraction. The Lattice handoff
(design_handoff_lattice, board 4b/4c) gives the mark as geometry instead - a
140 viewBox of strands, dots and one rotated square - so it is drawn here at
whatever size each file needs, rather than shrunk from one big picture.

THE SYSTEM, from the handoff:
  * the CELL (4c) is the lockup mark: a 3x3 of the field, six strands, eight
    dots, the centre node lit. The 64 px tile is the same with heavier strands
    and no dots, because 1.5 px strands vanish at that size.
  * the JUNCTION (4b) is every glyph at 32 px and under - two strands and the
    node. That is the in-game icon.
  * I.F.E.C. and N.I.F.E.C. keep their hues (teal, copper) and get the junction
    in that hue. No new sub-marks.

EVERY SHAPE IS A DISTANCE FIELD, sampled SS times finer than the output and
averaged down premultiplied. That is the antialiasing; nothing is drawn with
Pillow's own polygon fill, whose edges are either hard or blurred.

THE CLIENT WILL NOT LOAD A PNG, and it will not load a texture whose sides are
not powers of two. The two textures come out as 32-bit uncompressed BGRA TGA on
a POT canvas, the same as everything else in that folder.
"""
import io
import os
import re
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BRAND = os.path.join(ROOT, "docs", "brand")
OUT = os.path.join(ROOT, "Media", "Textures")
FONTS = os.path.join(ROOT, "Media", "Fonts")

SS = 4

# The handoff's tokens (README, "Design tokens").
ACCENT = (0xCD, 0xBC, 0xFF)
INK = (0xF0, 0xEC, 0xFF)
TEAL = (0x5F, 0xD0, 0xC4)
COPPER = (0xE0, 0x90, 0x5A)

# The plates, sampled from the AetherUI banners they replace, so the store
# pages keep their colour while the mark on them changes.
PLATE = {
    # Centre and edge of the handoff's own card (radial #241c3e -> #0d0a1c).
    "lattice": ((0x24, 0x1C, 0x3E), (0x0D, 0x0A, 0x1C), (150, 130, 235, 64)),
    "ifec": ((17, 33, 39), (10, 22, 28), (95, 208, 196, 52)),
    "nifec": ((35, 25, 15), (22, 14, 8), (224, 144, 90, 52)),
}

# The handoff's tagline, kept by Joe (2026-10-06).
TAGLINE = "CHROME FOR AZEROTH"


def col(c):
    return np.array(c[:3], np.float32) / 255.0


class Canvas:
    """Premultiplied RGBA, SS times the output size. Coordinates are in OUTPUT
    pixels throughout; only this class knows about the supersampling."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = np.zeros((h * SS, w * SS, 4), np.float32)

    def region(self, x0, y0, x1, y1):
        """Slices for a box in output pixels, and its sample centres."""
        X0 = max(0, int(np.floor(x0 * SS)))
        Y0 = max(0, int(np.floor(y0 * SS)))
        X1 = min(self.w * SS, int(np.ceil(x1 * SS)))
        Y1 = min(self.h * SS, int(np.ceil(y1 * SS)))
        ys = (np.arange(Y0, Y1, dtype=np.float32) + 0.5) / SS
        xs = (np.arange(X0, X1, dtype=np.float32) + 0.5) / SS
        Y, X = np.meshgrid(ys, xs, indexing="ij")
        return (slice(Y0, Y1), slice(X0, X1)), X, Y

    def paint(self, sl, cover, colour, alpha=1.0):
        a = np.clip(cover, 0.0, 1.0)[..., None] * np.float32(alpha)
        src = np.concatenate([col(colour) * a, a], 2)
        dst = self.px[sl]
        self.px[sl] = src + dst * (1.0 - a)

    def output(self):
        """Box-averaged down to the output size, still premultiplied."""
        h, w = self.h, self.w
        return self.px.reshape(h, SS, w, SS, 4).mean((1, 3))


def edge(d):
    """Coverage from a distance in output pixels: one SAMPLE wide, so the box
    average on the way down is what produces the antialiased pixel."""
    return np.clip(0.5 - d * SS, 0.0, 1.0)


def box_d(X, Y, cx, cy, hw, hh, r=0.0, angle=0.0):
    """Signed distance to a rounded box, optionally rotated about its centre."""
    px, py = X - cx, Y - cy
    if angle:
        c, s = np.cos(-angle), np.sin(-angle)
        px, py = px * c - py * s, px * s + py * c
    qx = np.abs(px) - (hw - r)
    qy = np.abs(py) - (hh - r)
    out = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2)
    return out + np.minimum(np.maximum(qx, qy), 0) - r


def blur(a, sigma):
    """Gaussian, near enough: three box passes each way, via cumulative sums."""
    r = max(1, int(round(np.sqrt(12.0 * sigma * sigma / 3.0 + 1.0) / 2.0)))
    for axis in (0, 1):
        for _ in range(3):
            pad = [(0, 0), (0, 0)]
            pad[axis] = (r + 1, r)
            c = np.cumsum(np.pad(a, pad), axis=axis, dtype=np.float64)
            hi = np.take(c, range(2 * r + 1, c.shape[axis]), axis=axis)
            lo = np.take(c, range(0, c.shape[axis] - 2 * r - 1), axis=axis)
            a = ((hi - lo) / (2 * r + 1)).astype(np.float32)
    return a


def rect(cv, cx, cy, hw, hh, colour, alpha=1.0, r=0.0, angle=0.0):
    reach = max(hw, hh) * (1.5 if angle else 1.0) + 1
    sl, X, Y = cv.region(cx - reach, cy - reach, cx + reach, cy + reach)
    cv.paint(sl, edge(box_d(X, Y, cx, cy, hw, hh, r, angle)), colour, alpha)


def dot(cv, cx, cy, rad, colour, alpha=1.0):
    sl, X, Y = cv.region(cx - rad - 1, cy - rad - 1, cx + rad + 1, cy + rad + 1)
    cv.paint(sl, edge(np.hypot(X - cx, Y - cy) - rad), colour, alpha)


def node(cv, cx, cy, side, rad, colour, glow=0.0, glow_alpha=0.0):
    """The rotated square - the one shape every Lattice mark is built round.
    The glow is CSS drop-shadow(0 0 Npx), whose N is twice the sigma."""
    hw = side / 2.0
    if glow > 0:
        reach = hw * 1.5 + glow * 3
        sl, X, Y = cv.region(cx - reach, cy - reach, cx + reach, cy + reach)
        cover = edge(box_d(X, Y, cx, cy, hw, hw, rad, np.pi / 4))
        cv.paint(sl, blur(cover, glow / 2.0 * SS), colour, glow_alpha)
    rect(cv, cx, cy, hw, hw, colour, 1.0, rad, np.pi / 4)


def cell(cv, cx, cy, size, colour=ACCENT, tile=False, glow=True):
    """Board 4c. `size` is the 140 viewBox in output pixels."""
    k = size / 140.0
    ox, oy = cx - 70 * k, cy - 70 * k
    if tile:
        width, alpha, lo, hi, side, rad = 6, 0.45, 6, 134, 32, 5
    else:
        width, alpha, lo, hi, side, rad = 1.5, 0.35, 10, 130, 20, 3
    for at in (30, 70, 110):
        mid = (lo + hi) / 2.0
        rect(cv, ox + at * k, oy + mid * k, width * k / 2, (hi - lo) * k / 2, colour, alpha)
        rect(cv, ox + mid * k, oy + at * k, (hi - lo) * k / 2, width * k / 2, colour, alpha)
    if not tile:
        for gx in (30, 70, 110):
            for gy in (30, 70, 110):
                if (gx, gy) != (70, 70):
                    dot(cv, ox + gx * k, oy + gy * k, 3 * k, colour, 0.5)
    node(cv, cx, cy, side * k, rad * k, colour,
         glow=(14 * k if glow else 0), glow_alpha=0.9)


def junction(cv, cx, cy, size, colour=ACCENT, strands=True, glow=0.0, hero=False):
    """Board 4b: two strands and the node. Glyph weight by default - strands
    10 of 140, heavy enough to survive 32 px. `hero` is the board's large
    drawing, strands 2 at 45 %, for a lockup where the heavy ones look clumsy.
    Below 16 px the handoff drops the strands."""
    k = size / 140.0
    width, alpha, reach = (2, 0.45, 60) if hero else (10, 0.5, 64)
    if strands:
        rect(cv, cx, cy, width / 2.0 * k, reach * k, colour, alpha)
        rect(cv, cx, cy, reach * k, width / 2.0 * k, colour, alpha)
    node(cv, cx, cy, 40 * k, 6 * k, colour, glow=glow * k, glow_alpha=0.8)


def font(name, px):
    return ImageFont.truetype(os.path.join(FONTS, name), max(1, int(round(px * SS))))


def runs_width(runs):
    """Width in output pixels of [(text, font, tracking, colour)], trailing
    tracking left off - CSS adds it after the last letter too, but centring on
    it would push the word left by one gap."""
    w = 0.0
    for text, f, track, _ in runs:
        for ch in text:
            w += f.getlength(ch) / SS + track
    return w - (runs[-1][2] if runs else 0)


def text(cv, x, cap_mid, runs, alpha=1.0):
    """Lay runs out from x with their capitals centred on cap_mid."""
    f0 = runs[0][1]
    l, t, r, b = f0.getbbox("H")
    w = runs_width(runs)
    pad = f0.size / SS
    sl, X, _ = cv.region(x - pad, cap_mid - pad * 1.2, x + w + pad, cap_mid + pad * 1.2)
    H, W = X.shape
    oy = (cap_mid - pad * 1.2)
    ox = (x - pad)
    origin_y = (cap_mid - oy) * SS - (t + b) / 2.0
    pen = (x - ox) * SS
    for s, f, track, colour in runs:
        im = Image.new("L", (W, H), 0)
        dr = ImageDraw.Draw(im)
        for ch in s:
            dr.text((pen, origin_y), ch, font=f, fill=255)
            pen += f.getlength(ch) + track * SS
        cv.paint(sl, np.array(im, np.float32) / 255.0, colour, alpha)
    return w


def plate(cv, x0, y0, x1, y1, rad, scheme):
    """The banner card: a hairline rim round a gradient - radial for Lattice,
    as the handoff's 4b/4c cards are, corner-to-corner for the sub-brands,
    whose plates are AetherUI's and keep their look."""
    top, bottom, rim = PLATE[scheme]
    sl, X, Y = cv.region(x0, y0, x1, y1)
    if scheme == "lattice":
        rx, ry = (x1 - x0) / 2.0, (y1 - y0) / 2.0
        t = np.hypot((X - x0 - rx) / rx, (Y - y0 - ry) / ry)
        t = np.clip(t, 0, 1)[..., None]
    else:
        t = np.clip(((X - x0) / (x1 - x0) + (Y - y0) / (y1 - y0)) / 2.0, 0, 1)[..., None]
    grad = col(top) * (1 - t) + col(bottom) * t
    hw, hh = (x1 - x0) / 2.0, (y1 - y0) / 2.0
    d = box_d(X, Y, x0 + hw, y0 + hh, hw, hh, rad)
    a = edge(d)[..., None]
    cv.px[sl] = np.concatenate([grad * a, a], 2) + cv.px[sl] * (1 - a)
    ring = edge(np.abs(d + 0.5) - 0.5)
    cv.paint(sl, ring, rim[:3], rim[3] / 255.0)


def lockup(cv, cx, cy, s, mark, words, tagline, tagline_colour):
    """Mark, then the wordmark with its tagline under it, centred as one block.
    `s` is the board's scale: 1 is the 140 px hero lockup in 4c."""
    mark_size = 140 * s
    gap = 36 * s
    wm = [(w, font("Outfit-Light.ttf", 44 * s), 6 * s, c) for w, c in words]
    tg = [(tagline, font("Outfit-Medium.ttf", 12 * s), 5 * s, tagline_colour)] if tagline else []
    width = mark_size + gap + max(runs_width(wm), runs_width(tg) if tg else 0)
    left = cx - width / 2.0
    mark(cv, left + mark_size / 2.0, cy, mark_size)
    tx = left + mark_size + gap
    cap = 44 * s * 0.70
    if tg:
        tcap = 12 * s * 0.70
        between = 15 * s
        block = cap + between + tcap
        text(cv, tx, cy - block / 2.0 + cap / 2.0, wm)
        text(cv, tx, cy + block / 2.0 - tcap / 2.0, tg, alpha=0.6)
    else:
        text(cv, tx, cy, wm)


def straight(pre):
    """Premultiplied 0..1 back to straight alpha, for a PNG or a TGA."""
    a = np.maximum(pre[..., 3:4], 1e-6)
    return np.concatenate([np.clip(pre[..., :3] / a, 0, 1), pre[..., 3:4]], 2)


def save_png(name, pre, opaque=False):
    rgba = straight(pre)
    buf = np.clip(rgba * 255.0 + 0.5, 0, 255).astype(np.uint8)
    im = Image.fromarray(buf, "RGBA")
    if opaque:
        im = im.convert("RGB")
    path = os.path.join(BRAND, name)
    im.save(path, optimize=True)
    print("  %-34s %dx%d" % (name, im.size[0], im.size[1]))


def write_tga(path, rgba):
    """An uncompressed 32-bit BGRA TGA, top-left origin. Same as the generator."""
    h, w = rgba.shape[:2]
    assert w & (w - 1) == 0 and h & (h - 1) == 0, "%s: %dx%d is not power-of-two" % (path, w, h)
    buf = np.clip(rgba * 255.0 + 0.5, 0, 255).astype(np.uint8)
    bgra = buf[:, :, [2, 1, 0, 3]]
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28,
    )
    with open(path, "wb") as fh:
        fh.write(header)
        fh.write(bgra.tobytes())
    return path


def bleed(rgba, iterations=8):
    """Push RGB outward into transparent texels so filtering never samples black."""
    rgb = rgba[..., :3].copy()
    a = rgba[..., 3].copy()
    known = a > 0.004
    for _ in range(iterations):
        if known.all():
            break
        acc = np.zeros_like(rgb)
        cnt = np.zeros(rgb.shape[:2])
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            s = np.roll(np.roll(rgb, dy, 0), dx, 1)
            k = np.roll(np.roll(known, dy, 0), dx, 1)
            acc += s * k[..., None]
            cnt += k
        fill = (~known) & (cnt > 0)
        rgb[fill] = acc[fill] / cnt[fill][:, None]
        known = known | fill
    out = rgba.copy()
    out[..., :3] = rgb
    return out


def band(rgba):
    """The rows of a canvas that actually carry ink, as fractions of its height."""
    rows = np.where((rgba[..., 3] > 0.01).any(1))[0]
    h = rgba.shape[0]
    return rows[0] / h, (rows[-1] + 1) / h


def agrees(name, rgba):
    """Media.lua quotes each lockup's ink band. Check it still tells the truth.

    A texture that has moved inside its canvas is not an error anywhere: the
    card just draws the mark a little high with a little air under it, and
    nobody notices for a version. So the contract is checked HERE, where the
    band is known, rather than trusted. `name` is the Lua prefix: logo, lockup.
    """
    top, bottom = band(rgba)
    h, w = rgba.shape[:2]
    path = os.path.join(ROOT, "Core", "Media.lua")
    src = io.open(path, encoding="utf-8").read()
    m = re.search(r"Media\.%sCoord\s*=\s*{([^}]*)}" % name, src)
    if not m:
        sys.exit("Core/Media.lua has no Media.%sCoord to check against" % name)
    want = [eval(x.strip(), {"__builtins__": {}}) for x in m.group(1).split(",")]
    got = [0, 1, round(top, 6), round(bottom, 6)]
    near = all(abs(a - b) < 0.004 for a, b in zip(want, got))

    # And the aspect that hangs off it, which is the number callers actually
    # size with - so it is the one that would go wrong quietly.
    ma = re.search(r"Media\.%sAspect\s*=\s*([0-9]+)\s*/\s*([0-9]+)" % name, src)
    if not ma:
        sys.exit("Core/Media.lua has no Media.%sAspect to check against" % name)
    ink = float(w) / ((bottom - top) * h)
    if abs(int(ma.group(1)) / int(ma.group(2)) - ink) > 0.02 or not near:
        sys.exit("Core/Media.lua says %sCoord = {%s}, %sAspect = %s / %s\n"
                 "the art measures        {0, 1, %d / %d, %d / %d}, %d / %d\n"
                 "Change the Lua to match, then run this again."
                 % (name, m.group(1).strip(), name, ma.group(1), ma.group(2),
                    round(top * h), h, round(bottom * h), h,
                    w, round((bottom - top) * h)))
    print("  %-6s ink rows %d..%d of %d" % (name, round(top * h), round(bottom * h), h))


# ---------------------------------------------------------------------------
# the files
# ---------------------------------------------------------------------------

def lattice_mark(cv, cx, cy, size):
    cell(cv, cx, cy, size)


def sub_mark(hue):
    def draw(cv, cx, cy, size):
        junction(cv, cx, cy, size, hue, glow=16, hero=True)
    return draw


def banner(w, h, scheme, mark, words, tagline, tagline_colour, rad, s, inset=0):
    cv = Canvas(w, h)
    if inset:
        # The social card: a flat ground with the plate set into it, as the
        # AetherUI one was, so the rim reads when a site crops the corners.
        sl, X, _ = cv.region(0, 0, w, h)
        ground = col(PLATE[scheme][0]) * 0.9
        cv.px[sl] = np.concatenate([np.broadcast_to(ground, X.shape + (3,)),
                                    np.ones(X.shape + (1,), np.float32)], 2)
    plate(cv, inset, inset, w - inset, h - inset, rad, scheme)
    lockup(cv, w / 2.0, h / 2.0, s, mark, words, tagline, tagline_colour)
    return cv.output()


def tile_icon(size, scheme, draw):
    """A square store icon: the mark on a rounded tile, as the 64 px tile on
    board 4c (radius 14 of 64, a 1 px rim at 30 %)."""
    cv = Canvas(size, size)
    plate(cv, 0, 0, size, size, size * 14 / 64.0, scheme)
    draw(cv, size / 2.0, size / 2.0, size * 44 / 64.0)
    return cv.output()


def logo_texture():
    """The lockup the onboarding card shows, without its plate or tagline.

    No plate, because the card is whichever of the four palettes is loaded and
    a navy plate would read as a sticker of Midnight. No tagline, because at the
    size this is drawn it is four illegible pixels tall.

    Drawn at 512 wide directly - a 512 x 256 canvas holding the lockup at the
    largest scale that fits with a margin - so nothing is resampled at all.
    """
    w, h = 512, 256
    words = [("LATTICE", INK)]
    probe = runs_width([(t, font("Outfit-Light.ttf", 44), 6, c) for t, c in words])
    s = (w - 24) / (140 + 36 + probe)
    cv = Canvas(w, h)
    lockup(cv, w / 2.0, h / 2.0, s, lattice_mark, words, None, None)
    return straight(cv.output())


def lockup_texture():
    """The full lockup, tagline and all, for the options window's Home page.

    A second texture rather than the logo with a tagline added, because the two
    are drawn at very different sizes. Home draws this across most of a 760-wide
    window, which on a 1440p screen is near a thousand physical pixels - so it
    is authored at 1024, where the tagline is real type. The tour card and the
    stub draw the logo at 300 and 280, where the same tagline would be a smear.
    """
    w, h = 1024, 512
    words = [("LATTICE", INK)]
    probe = runs_width([(t, font("Outfit-Light.ttf", 44), 6, c) for t, c in words])
    s = (w - 48) / (140 + 36 + probe)
    cv = Canvas(w, h)
    lockup(cv, w / 2.0, h / 2.0, s, lattice_mark, words, TAGLINE, ACCENT)
    return straight(cv.output())


def icon_texture():
    """The junction, at 64.

    64, NOT 128. This is drawn at 26 units on the Toolbox rail and 20 in the
    addon list, and UIParent is not at 1: on a 1440p screen a unit is 1.875
    physical pixels, so both land near 35 real ones and a 4K screen at the
    default scale reaches about 52. The client builds no mipmaps, so a bigger
    texture minified that far speckles. See the texture-size-and-resampling
    note in the project memory.
    """
    cv = Canvas(64, 64)
    junction(cv, 32, 32, 60)
    return straight(cv.output())


def main():
    for d in (BRAND, OUT):
        if not os.path.isdir(d):
            sys.exit("no %s" % d)

    words = [("LATTICE", INK)]
    save_png("Lattice-Logo.png",
             banner(1200, 560, "lattice", lattice_mark, words, TAGLINE, ACCENT, 24, 1.5))
    save_png("Lattice-Logo-850x397.png",
             banner(850, 397, "lattice", lattice_mark, words, TAGLINE, ACCENT, 17, 1.5 * 850 / 1200))
    save_png("Lattice-Social.png",
             banner(1280, 640, "lattice", lattice_mark, words, TAGLINE, ACCENT, 24, 1.6, inset=22),
             opaque=True)
    save_png("Lattice-Icon.png", tile_icon(400, "lattice", lambda cv, x, y, z: cell(cv, x, y, z, tile=True)))

    for scheme, hue, name, tag in (("ifec", TEAL, "I.F.E.C.", "IN-FLIGHT ENTERTAINMENT"),
                                   ("nifec", COPPER, "N.I.F.E.C.", "NOT IN-FLIGHT ENTERTAINMENT")):
        sub = [("LATTICE ", INK), (name, hue)]
        save_png("lattice-%s-lockup.png" % scheme,
                 banner(1656, 680, scheme, sub_mark(hue), sub, tag, hue, 34, 2.0))
        save_png("lattice-%s-lockup-850.png" % scheme,
                 banner(850, 350, scheme, sub_mark(hue), sub, tag, hue, 17, 2.0 * 850 / 1656))
        save_png("lattice-%s-icon.png" % scheme,
                 tile_icon(360, scheme, lambda cv, x, y, z, hue=hue: junction(cv, x, y, z, hue, glow=16)))

    logo, full = logo_texture(), lockup_texture()
    agrees("logo", logo)
    agrees("lockup", full)
    for name, rgba in (("Logo", logo), ("Lockup", full), ("Icon", icon_texture())):
        path = write_tga(os.path.join(OUT, name + ".tga"), bleed(rgba))
        print("  %-6s -> %s (%.0f KB)" % (name, os.path.relpath(path, ROOT),
                                          os.path.getsize(path) / 1024))


if __name__ == "__main__":
    main()
