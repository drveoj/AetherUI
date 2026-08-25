# -*- coding: utf-8 -*-
"""The brand marks, as textures the client can actually load.

Everything in Media/Textures is DRAWN by generate_textures.py from line
segments and gradients. These two are not: they are artwork, and artwork
arrives as a PNG. So they get their own script - the conversion is a different
job from the drawing, and folding it into the generator would mean that file
suddenly depending on files outside the addon.

    docs/brand/AetherUI-Logo.png  ->  Media/Textures/Logo.tga
    docs/brand/AetherUI-Icon.png  ->  Media/Textures/Icon.tga

THE CLIENT WILL NOT LOAD A PNG, and it will not load a texture whose sides are
not powers of two. Both come out as 32-bit uncompressed BGRA TGA on a POT
canvas, the same as everything else in that folder.

THE PLATE COMES OFF THE LOGO. The PNG is a banner: the mark and the wordmark on
a dark rounded rectangle, and the rectangle is most of the file. That is right
for a README and wrong on a glass card - the plate is one specific navy and the
card is whichever of the four palettes is loaded, so it would read as a sticker
of the Midnight skin pasted onto Dusk.

It comes off by subtraction rather than by keying. The plate is a smooth linear
gradient (about #17132c to #0f0c21 corner to corner), and the artwork is light
sitting on top of it, so fitting a plane to the dark pixels and taking it away
leaves exactly what was added - which IS the mark, with its glow, at the alpha
the glow deserves. A threshold would have left a hard halo where the ring's
bloom fades into the plate.

The one thing subtraction cannot recover is the dark disc behind the A: it is
barely brighter than the plate, so it comes back at almost no alpha and the A
ends up standing in the ring on whatever is behind it. That is the right answer
anyway on a frosted panel, and it is why the disc is not painted back in.

AND IT IS CROPPED, which the README banner deliberately is not. The negative
space is the point of the banner and pointless here: a texture is drawn at
whatever size the caller asks for, so shipping 60% empty pixels only means the
mark is drawn small inside its own frame and every caller has to compensate.
The tagline goes too - at any size this is drawn in game it is four illegible
pixels tall, and the card underneath it says the same thing in words.
"""
import io
import os
import re
import struct
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "docs", "brand")
OUT = os.path.join(ROOT, "Media", "Textures")


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


def unplate(im):
    """The logo banner minus its background plate, as straight-alpha RGBA 0..1.

    Fits a plane per channel to the plate (every pixel dark enough to be it),
    subtracts, and reads the leftover light as the alpha it was composited at.
    """
    a = np.array(im.convert("RGBA")).astype(float)
    h, w = a.shape[:2]
    rgb, al = a[..., :3], a[..., 3] / 255.0
    yy, xx = np.mgrid[0:h, 0:w]

    # The plate is everything not bright enough to be artwork. 55 sits well
    # above the plate's own 44 and well below the dimmest part of the glow.
    sel = (rgb.max(2) < 55) & (al > 0.99)
    basis = np.stack([np.ones(int(sel.sum())), yy[sel], xx[sel]], 1)
    plane = np.zeros_like(rgb)
    for c in range(3):
        coef, *_ = np.linalg.lstsq(basis, rgb[..., c][sel], rcond=None)
        plane[..., c] = coef[0] + coef[1] * yy + coef[2] * xx

    res = np.clip(rgb - plane, 0.0, 255.0)
    alpha = np.clip(res.max(2) / 255.0, 0.0, 1.0) * al
    # The wordmark is #eeebfe rather than white, so the brightest thing in the
    # file only ever added 93% of a channel and comes back 93% opaque - solid
    # type you can see the world through. Normalised to the peak it is type.
    alpha = np.clip(alpha / max(float(alpha.max()), 1e-6), 0.0, 1.0)

    # Un-premultiply: the residual IS colour times coverage, and a texture
    # wants the two apart or every soft edge draws darker than it should.
    out = np.zeros((h, w, 4))
    lit = alpha > 0.0
    out[..., :3][lit] = np.clip(res[lit] / alpha[lit][:, None] / 255.0, 0.0, 1.0)
    out[..., 3] = alpha
    return out


def trim(rgba, floor=0.06, margin=4, border=12):
    """Crop to the artwork, keeping a little air so filtering has somewhere to go."""
    a = rgba[..., 3].copy()
    # The plate's rounded corners are antialiased against nothing, so its outer
    # dozen pixels survive subtraction as a hairline frame - a full sixth of an
    # alpha at row eight. Ignore the border; the artwork is nowhere near it.
    a[:border, :] = 0
    a[-border:, :] = 0
    a[:, :border] = 0
    a[:, -border:] = 0
    rows = np.where((a > floor).any(1))[0]
    cols = np.where((a > floor).any(0))[0]
    y0 = max(0, rows[0] - margin)
    y1 = min(rgba.shape[0], rows[-1] + 1 + margin)
    x0 = max(0, cols[0] - margin)
    x1 = min(rgba.shape[1], cols[-1] + 1 + margin)
    return rgba[y0:y1, x0:x1]


def fit(rgba, cw, ch):
    """Centre the art in a POT canvas, its aspect kept, the rest transparent."""
    h, w = rgba.shape[:2]
    s = min(cw / w, ch / h)
    tw, th = max(1, int(round(w * s))), max(1, int(round(h * s)))
    im = Image.fromarray(np.clip(rgba * 255 + 0.5, 0, 255).astype(np.uint8), "RGBA")
    im = im.resize((tw, th), Image.LANCZOS)
    canvas = np.zeros((ch, cw, 4))
    y, x = (ch - th) // 2, (cw - tw) // 2
    canvas[y:y + th, x:x + tw] = np.array(im).astype(float) / 255.0
    return canvas


def band(canvas):
    """The rows of a canvas that actually carry ink, as fractions of its height."""
    rows = np.where((canvas[..., 3] > 0.01).any(1))[0]
    h = canvas.shape[0]
    return rows[0] / h, (rows[-1] + 1) / h


def agrees(top, bottom):
    """Media.lua quotes the logo's ink band. Check it still tells the truth.

    A texture that has moved inside its canvas is not an error anywhere: the
    card just draws the mark a little high with a little air under it, and
    nobody notices for a version. So the contract is checked HERE, where the
    band is known, rather than trusted.
    """
    path = os.path.join(ROOT, "Core", "Media.lua")
    src = io.open(path, encoding="utf-8").read()
    m = re.search(r"Media\.logoCoord\s*=\s*{([^}]*)}", src)
    if not m:
        sys.exit("Core/Media.lua has no Media.logoCoord to check against")
    want = [eval(x.strip(), {"__builtins__": {}}) for x in m.group(1).split(",")]
    got = [0, 1, round(top, 6), round(bottom, 6)]
    near = all(abs(a - b) < 0.004 for a, b in zip(want, got))

    # And the aspect that hangs off it, which is the number callers actually
    # size with - so it is the one that would go wrong quietly.
    ma = re.search(r"Media\.logoAspect\s*=\s*([0-9]+)\s*/\s*([0-9]+)", src)
    if not ma:
        sys.exit("Core/Media.lua has no Media.logoAspect to check against")
    ink = 512.0 / ((bottom - top) * 256.0)
    if abs(int(ma.group(1)) / int(ma.group(2)) - ink) > 0.02:
        sys.exit("Core/Media.lua says logoAspect = %s / %s\n"
                 "the art measures      512 / %d"
                 % (ma.group(1), ma.group(2), round((bottom - top) * 256)))
    if not near:
        sys.exit("Core/Media.lua says logoCoord = {%s}\n"
                 "the art measures      {0, 1, %d / 256, %d / 256}\n"
                 "Change the Lua to match, then run this again."
                 % (m.group(1).strip(), round(top * 256), round(bottom * 256)))


def logo():
    im = Image.open(os.path.join(SRC, "AetherUI-Logo.png"))
    art = unplate(im)

    # Lose the tagline. It is the only thing under the wordmark and it sits
    # clear of the ring, so a rectangle takes it without touching the mark.
    h, w = art.shape[:2]
    art[int(h * 0.55):, int(w * 0.41):, 3] = 0.0

    art = trim(art)
    canvas = fit(art, 512, 256)
    top, bottom = band(canvas)
    agrees(top, bottom)
    print("  logo art %dx%d, ink rows %d..%d of 256"
          % (art.shape[1], art.shape[0], round(top * 256), round(bottom * 256)))
    return bleed(canvas)


def icon():
    im = Image.open(os.path.join(SRC, "AetherUI-Icon.png")).convert("RGBA")
    art = np.array(im).astype(float) / 255.0
    # Already cut out, already square, already all artwork - only the pixel
    # count comes down. 128 is the cell every other icon in here is drawn in.
    return bleed(fit(art, 128, 128))


def main():
    if not os.path.isdir(OUT):
        sys.exit("no %s" % OUT)
    for name, build in (("Logo", logo), ("Icon", icon)):
        path = write_tga(os.path.join(OUT, name + ".tga"), build())
        print("  %-6s -> %s (%.0f KB)" % (name, os.path.relpath(path, ROOT),
                                          os.path.getsize(path) / 1024))


if __name__ == "__main__":
    main()
