#!/usr/bin/env python3
"""
AetherUI texture generator.

Produces the whole Media/Textures set as 32-bit uncompressed TGA files that the
WoW client can load directly.

Design rules baked into every asset here:

  * Everything is NEUTRAL (white / greyscale). Colour is applied at runtime with
    Texture:SetVertexColor(), so one asset set drives every skin and the user can
    recolour freely. Never bake a hue.
  * Every texture is power-of-two on both axes.
  * Straight (non-premultiplied) alpha, with RGB "bleed" pushed outward into the
    transparent region so the client's bilinear filter cannot pull black in and
    halo the rounded corners.
  * Shapes are drawn at 4x and downsampled with LANCZOS for clean antialiasing.
  * Slice geometry is chosen so corners land on exact texel thirds/quarters,
    which keeps the Lua-side TexCoord maths trivial and artefact-free.

Run:  python3 Tools/generate_textures.py [outdir]
"""

import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SS = 4  # supersample factor

FONTS = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Media", "Fonts")


# --------------------------------------------------------------------------
# TGA output
# --------------------------------------------------------------------------

def write_tga(path, rgba):
    """Write an uncompressed 32-bit BGRA TGA with a top-left origin.

    rgba: float array (h, w, 4) in 0..1, straight alpha.
    """
    h, w = rgba.shape[:2]
    assert w & (w - 1) == 0 and h & (h - 1) == 0, f"{path}: {w}x{h} is not power-of-two"

    buf = np.clip(rgba * 255.0 + 0.5, 0, 255).astype(np.uint8)
    bgra = buf[:, :, [2, 1, 0, 3]]  # RGBA -> BGRA

    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,      # id length
        0,      # no colour map
        2,      # uncompressed true-colour
        0, 0, 0,  # colour map spec
        0, 0,   # x/y origin
        w, h,
        32,     # bits per pixel
        0x28,   # 8 alpha bits | top-left origin
    )
    with open(path, "wb") as fh:
        fh.write(header)
        fh.write(bgra.tobytes())
    return path


def bleed(rgba, iterations=12):
    """Push RGB outward into transparent texels so filtering never samples black."""
    rgb = rgba[:, :, :3].copy()
    a = rgba[:, :, 3]
    known = a > 0.004

    for _ in range(iterations):
        if known.all():
            break
        w = known.astype(np.float32)
        acc = np.zeros_like(rgb)
        cnt = np.zeros_like(a)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)):
            acc += np.roll(np.roll(rgb * w[..., None], dy, 0), dx, 1)
            cnt += np.roll(np.roll(w, dy, 0), dx, 1)
        fill = (~known) & (cnt > 0)
        rgb[fill] = (acc[fill] / cnt[fill][..., None])
        known = known | fill

    out = rgba.copy()
    out[:, :, :3] = rgb
    return out


# --------------------------------------------------------------------------
# shape helpers (all return float masks 0..1 at final resolution)
# --------------------------------------------------------------------------

def _draw(size, fn):
    w, h = size
    img = Image.new("L", (w * SS, h * SS), 0)
    fn(ImageDraw.Draw(img), SS)
    return np.asarray(img.resize((w, h), Image.LANCZOS), dtype=np.float32) / 255.0


def rrect_sdf(size, radius, inset=0.0):
    """Signed distance to a rounded rectangle, in texels. Negative inside.

    Analytic, not rasterised, and that is the point. Every shape here used to
    come from PIL's rounded_rectangle at 4x supersampling, which draws a corner
    as a pieslice butted against two rectangles. Its worst rasterisation error is
    at 45 degrees - exactly the middle of each corner arc - and the error is a
    fraction of a texel, so on a solid fill nobody could ever see it.

    On a *rim* it was plainly visible. A rim built as (outer - inner) inherits
    the error from both masks, and normalising the result by its own maximum then
    scaled the whole ring down to suit the one artefact: the 45 degree points sat
    at full brightness and everything else was dimmed relative to them. Four
    bright spots per shape, one per corner, in exactly the same place every time.

    A distance field has no corners to rasterise. The band is the same width at
    every angle because it is defined as a distance, and anti-aliasing falls out
    of the distance rather than being sampled for.
    """
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    px = xx + 0.5 - w / 2.0          # pixel centres, relative to the middle
    py = yy + 0.5 - h / 2.0

    r = max(0.0, radius - inset)
    hx = max(0.0, w / 2.0 - inset - r)
    hy = max(0.0, h / 2.0 - inset - r)

    dx, dy = np.abs(px) - hx, np.abs(py) - hy
    outside = np.sqrt(np.maximum(dx, 0.0) ** 2 + np.maximum(dy, 0.0) ** 2)
    inside = np.minimum(np.maximum(dx, dy), 0.0)
    return (outside + inside - r).astype(np.float32)


# Every shape is inset by this much, and the reason is the whole of "it looks
# like there is no feathering at all" - because there was none.
#
# A capsule of radius 128 drawn in a 256-tall texture reaches the topmost texel
# row with alpha 1.0. Its anti-aliasing ramp would have to live *outside* the
# texture, and there is no outside: the edge is a hard cut, and the client
# faithfully reproduces a hard cut at whatever size it draws it. Two texels of
# margin gives the ramp somewhere to be.
#
# The cost is that a shape occupies 252 of 256 texels instead of all of them, so
# the drawn result is about 1.5% smaller than its frame. At the sizes here that
# is well under a pixel of margin, and invisible next to what it buys.
MARGIN = 2.0

# Width of the anti-aliasing ramp, in texels.
#
# The textbook value is 1.0 - alpha = clip(0.5 - d) - and it is not enough here.
# A one-texel ramp only produces an intermediate value when the shape's edge
# happens to fall near a texel centre; land it on a boundary instead and you get
# 1.0 next to 0.0 and no gradient at all, which is a hard edge wearing a
# feathered edge's clothing. These shapes are authored at 2x and minified, so a
# ~2 texel ramp arrives as one clean pixel of anti-aliasing whatever phase the
# edge happens to land on.
# 3.0 rather than 1.8, and the extra is for the *small* pills. The unit capsule
# is minified about 2x from this authoring size, so 1.8 texels arrived as a clean
# pixel there - but an aura pill is barely half the capsule's height and minifies
# 4.3x, where the same ramp is 0.4 of a pixel and the edge goes hard again. One
# texture cannot be 1:1 for elements that differ by more than 2x in size and a
# TGA carries no mipmaps, so the ramp is widened to suit the smallest thing that
# uses it. The capsule pays about a pixel of extra softness for it.
AA = 3.0


def _cover(d):
    """Coverage from a signed distance: 1 inside, 0 outside, ramped across AA."""
    return np.clip(0.5 - d / AA, 0.0, 1.0)


def rrect_mask(size, radius, inset=0.0, margin=None):
    """Filled rounded rectangle with analytic anti-aliasing.

    `margin` overrides MARGIN for the rare shape that cannot afford it - see
    bar_mask, where two texels of a sixteen-texel height was an eighth of the
    bar.
    """
    m = MARGIN if margin is None else margin
    return _cover(rrect_sdf(size, radius, inset + m))


def ellipse_sdf(size, inset=0.0):
    """Signed distance to an ellipse inscribed in the box. Negative inside.

    Exact for a circle, and near enough for the mild ellipses this file draws;
    the shapes that matter here - masks and rims - are all circular.
    """
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    px = (xx + 0.5 - w / 2.0) / max(1e-6, (w / 2.0 - inset))
    py = (yy + 0.5 - h / 2.0) / max(1e-6, (h / 2.0 - inset))
    d = np.sqrt(px * px + py * py) - 1.0
    return (d * min(w, h) / 2.0).astype(np.float32)


def ellipse_mask(size, inset=0.0):
    return _cover(ellipse_sdf(size, inset + MARGIN))


def rim_from_sdf(d, width, peak=1.0):
    """A rim band from a distance field: brightest just inside the edge.

    Two linear ramps meeting at `peak` texels in - up from nothing `width`
    further inside, and down to nothing AA/2 *outside* the shape's boundary.
    That last part matters: the first version tapered to zero exactly at the
    boundary, so the outermost lit texel had no anti-aliasing beyond it and the
    rim came out with a hard outer edge no matter how soft its inner one was.
    """
    inner = np.clip(1.0 + (d + peak) / width, 0.0, 1.0)
    outer = np.clip((AA / 2.0 - d) / (peak + AA / 2.0), 0.0, 1.0)
    return np.minimum(inner, outer)


def blur(mask, radius):
    if radius <= 0:
        return mask
    img = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8))
    img = img.filter(ImageFilter.GaussianBlur(radius))
    return np.asarray(img, dtype=np.float32) / 255.0


def vgrad(size, top, bottom, gamma=1.0):
    w, h = size
    t = (np.linspace(0.0, 1.0, h, dtype=np.float32) ** gamma)[:, None]
    return np.repeat(top + (bottom - top) * t, w, axis=1)


def rgba(rgb_scalar, alpha):
    h, w = alpha.shape
    out = np.zeros((h, w, 4), dtype=np.float32)
    out[:, :, :3] = rgb_scalar
    out[:, :, 3] = np.clip(alpha, 0.0, 1.0)
    return out


def rgba_lum(lum, alpha):
    h, w = alpha.shape
    out = np.zeros((h, w, 4), dtype=np.float32)
    out[:, :, 0] = out[:, :, 1] = out[:, :, 2] = np.clip(lum, 0.0, 1.0)
    out[:, :, 3] = np.clip(alpha, 0.0, 1.0)
    return out


def rng(seed):
    return np.random.default_rng(seed)


# --------------------------------------------------------------------------
# assets
# --------------------------------------------------------------------------

def grain(size, amp, seed):
    """Fine multiplicative variation, meant for a fill's ALPHA channel.

    It has to be alpha, not RGB. These textures are white and get tinted dark at
    runtime, so RGB variation is multiplied away to nothing - on Midnight glass
    (tint 0.047, 0.55 alpha) a 3% RGB wobble lands around 0.001 of final output.
    Varying alpha instead lets marginally more or less of the world through per
    texel, which is what actually reads as a frosted surface.

    Zero-mean by construction: a grain that shifts the average alpha would make
    the surface brighter or darker rather than textured.
    """
    w, h = size
    r = np.random.default_rng(seed)
    n = np.clip(r.normal(0.5, 0.15, (h, w)).astype(np.float32), 0, 1)
    n = blur(n, 0.55)
    n = n - n.mean()
    peak = float(np.abs(n).max())
    if peak > 0:
        n = n / peak
    return 1.0 + n * amp


# Authoring resolution, for the record: the target is a 4K display, where one UI
# unit is 2.8 physical pixels. The tallest pill in the UI is the unit capsule at
# 64 units * 0.71 scale = 128 physical pixels, which is exactly the 128-tall pill
# texture - 1:1, no filtering at all on the element you look at most. The smaller
# pills minify from there, which is why the rims are feathered rather than
# hairlines: it is the one direction that cannot be made lossless without
# mipmaps, and a TGA has none.
#
# Grain amplitude in a *sliced* fill has a ceiling nothing can raise.
#
# A nine-slice stretches its centre and does not stretch its corners, so the same
# noise field comes out at one scale in the middle and another at the edges. Any
# amplitude high enough to see is therefore also high enough to show a seam where
# the two meet - which is the darker notch that used to sit exactly where a pill's
# cap joins its body. Low enough not to seam is low enough to be honest about:
# this is a whisper, and the frost is really being sold by the rim and the
# falloff.
GRAIN = 0.022


def glass_panel():
    """9-slice frosted panel fill. 256x256, corner radius 64 -> exact texel quarters.

    Authored at 2x the size it is drawn at, which is the opposite of the earlier
    reasoning and the right way round. At 1:1 the only anti-aliasing on a curve
    is the one texel the generator puts there, and one texel of AA at 1:1 is
    visible stair-stepping. Minified 2x, bilinear averages a 2x2 footprint per
    pixel - four samples on the curve instead of one - and the edge comes out
    genuinely smooth. Sharpness was never the problem; the curves were.

    Alpha carries the shape plus a top-light falloff; RGB carries a faint sheen so
    the surface is not perfectly flat when tinted.
    """
    size = (256, 256)
    shape = rrect_mask(size, 64)
    # light catches the top of the glass and drains toward the bottom
    grad = vgrad(size, 1.0, 0.80, gamma=0.85)
    # a whisper of extra brightness in the top 20%
    sheen = np.clip(vgrad(size, 0.22, 0.0, gamma=2.4), 0, 1)
    return rgba_lum(0.86 + sheen * 0.14, shape * grad * grain(size, GRAIN, 0x51CE))


def _rim(size, radius, width=2.6, feather=None):
    # Insets by MARGIN too, via rrect_sdf below, so the rim's outer edge lands on
    # the fill's outer edge exactly rather than a couple of texels outside it.
    """A rim that survives being drawn smaller than it was authored.

    The first version of this was one texel wide, which looks perfect at 1:1 and
    falls apart anywhere else - minified, bilinear filtering lands on the rim
    texel in some columns and misses it in the ones next door, which is white
    speckling along the edges that no amount of tinting hides. A few texels wide
    degrades instead: it becomes a thinner, softer line rather than a dashed one.

    The second version got the width right and the *evenness* wrong; see
    rrect_sdf for the four bright corner spots that came of building it out of
    rasterised masks and then normalising by the peak.
    """
    return rim_from_sdf(rrect_sdf(size, radius, MARGIN), width)


def glass_panel_edge():
    """Rim for the panel, tinted independently of the fill."""
    size = (256, 256)
    # rim is brightest along the top arc, dimmer at the bottom (light from above)
    return rgba_lum(1.0, _rim(size, 64, width=3.6) * vgrad(size, 1.0, 0.55, gamma=0.9))


def glass_pill():
    """3-slice horizontal capsule. 512x256: caps occupy x 0..128 and 384..512.

    2x the size it is drawn at on a 4K display - see glass_panel for why that is
    the right way round for a curve.
    """
    size = (512, 256)
    shape = rrect_mask(size, 128)
    grad = vgrad(size, 1.0, 0.80, gamma=0.85)
    sheen = np.clip(vgrad(size, 0.22, 0.0, gamma=2.4), 0, 1)
    return rgba_lum(0.86 + sheen * 0.14, shape * grad * grain(size, GRAIN, 0xB177))


def glass_pill_edge():
    size = (512, 256)
    # 3.6 texels at this size is 1.8 at the old one - a genuinely finer hairline
    # than before, which is what it wanted. Still feathered, so the small pills
    # get a soft thin line rather than a dashed one.
    return rgba_lum(1.0, _rim(size, 128, width=3.6)
                    * vgrad(size, 1.0, 0.55, gamma=0.9))


def glass_shadow():
    """9-slice ambient shadow for panels. 256x256, corner slice 0.375 (96 texels).

    Like the pill shadow, this is authored for a single fixed relationship rather
    than a free "spread" distance: it is drawn with a corner piece of 2*corner and
    an outward offset of corner/2. At that ratio the hole's radius renders at
    exactly the panel's own corner radius, whatever that radius is.

    That matters more than it sounds. The previous version used a nearly square
    hole (radius 6 of 48), which rendered as a 2px round on a 14px panel corner.
    The 12px between the two had no panel AND no shadow, so each corner showed a
    transparent square notch cut out of the shadow.

    The size went 128 -> 256 to buy headroom: all curvature *plus* the blur's
    spill has to finish before texel 96, or the edge slices stop being uniform
    along the axis they stretch on and every wide panel gets a seam.
    Here 24 + 48 + ~20 = 92, with 4 texels to spare.
    """
    size = (256, 256)
    core = rrect_mask(size, 72, inset=24)      # inset 24, radius 48
    soft = blur(core, 8.0)
    # Hollow, exactly like CSS box-shadow being clipped to outside the border box.
    # The subtracted shape is 2px tighter so the falloff tucks under the panel
    # edge rather than leaving a hairline.
    inner = rrect_mask(size, 72, inset=26)
    soft = np.clip(soft - inner, 0, 1)
    soft = np.clip(soft * 1.35, 0, 1) ** 1.15
    return rgba_lum(0.0, soft * 0.9)


def glass_pill_shadow():
    """3-slice ambient shadow shaped for a capsule rather than a box.

    Drawn at (w + h/2, h + h/2) - spread h/4 on every side - so in this texture's
    128-texel height the pill's own edge is a circle of radius 128/3 = 42.7 about
    the cap centre, and the shadow should reach 21.3 texels past it.

    Both shapes here are **true capsules**, concentric with the pill. That sounds
    obvious and it is the entire fix: they used to be rounded rectangles of
    radius 34 in a 128-tall space, which is noticeably squarer than a capsule. A
    squarer hole extends *further* at 45 degrees than the circle it is standing
    in for, so around each corner the pill's edge fell 2.2 texels inside the
    hole - and in that band no shadow was drawn at all. Against bright ground
    that is four pale patches, one at each corner of every pill in the UI, which
    is exactly how it was reported.

    The old comment claimed the extra squareness "sits underneath the pill where
    nothing can see them". It sat outside it, at the corners, which is the one
    place it could be seen. Erring the other way is the safe direction: the hole
    is a little *smaller* than the pill, so its edge hides under the glass.
    """
    size = (512, 256)
    # In this texture's 256-texel height the pill's own edge is a circle of
    # radius 256/3 = 85.3 about the cap centre.
    #
    # The core sits just about on that edge and the blur carries it outward from
    # there. Making the core much larger - which one pass at this did - turns the
    # falloff into a solid ring of black standing off the frame.
    core = rrect_mask(size, 128, inset=40)   # capsule, radius 88 ~ the pill's 85.3
    soft = blur(core, 10.0)                  # spill reaches ~98, inside the 128 cap
    hole = rrect_mask(size, 128, inset=48)   # capsule, radius 80 - under the pill
    soft = np.clip(soft - hole, 0, 1) ** 1.35
    # Enough to lift the frame off the ground and no more. It is multiplied again
    # by the palette's shadow colour and by glass.shadow, so this is not the
    # number you see - it lands near 0.10 on screen.
    return rgba_lum(0.0, soft * 0.52)


def noise_tile():
    """Seamless fine grain.

    No longer used by the glass surfaces - that grain is baked into the fills, so
    it covers the rounded caps as well as the centre and cannot leave a seam.
    Kept because it is registered with LibSharedMedia for other addons.
    """
    n = 128
    r = rng(0xA37E)
    field = r.normal(0.5, 0.16, (n, n)).astype(np.float32)
    # wrap-safe blur: tile 3x3, blur, take the centre
    big = np.tile(field, (3, 3))
    big = blur(big, 0.6)
    field = big[n:2 * n, n:2 * n]
    field = (field - field.min()) / max(1e-6, (field.max() - field.min()))
    return rgba_lum(field, np.full((n, n), 1.0, dtype=np.float32))


def frost_tile():
    """Seamless scatter field for Zen mode's full-screen pane.

    Not a finer version of Noise. Three things are deliberately different, and
    each one is a mistake the first pass made:

    ALPHA, NOT RGB. `noise_tile` carries its field in RGB, which is fine for a
    LibSharedMedia background but useless here: the pane is tinted at runtime,
    and on a dark skin the tint multiplies RGB variation away to nothing. Same
    rule as `grain()` further up - variation that has to survive tinting lives
    in alpha.

    BIG. Noise is per-texel grain; tiled across a 4K screen it is finer than the
    eye can resolve and reads as nothing at all. Frosted glass scatters light in
    patches you can see - centimetres, not pixels - so this is authored to be
    tiled about three times across a screen, not twenty.

    MULTI-OCTAVE. One blurred random field is mush. Summing a few at halving
    scales gives large soft patches with smaller structure inside them, which is
    what actually reads as a surface rather than as a gradient.

    Wrap-safe throughout: every octave is blurred as a 3x3 tiling and cropped
    back to the centre, so the seams cannot show no matter how far it is tiled.
    """
    n = 512
    r = rng(0x5C0F)
    field = np.zeros((n, n), dtype=np.float32)

    def octave(grid):
        """One layer of value noise: a small random grid, interpolated up.

        NOT a blurred full-resolution field, which is what this was first and
        why it had to be thrown away. `blur()` goes through PIL's GaussianBlur,
        and PIL implements that as three successive BOX blurs - an approximation
        that is invisible at the two-texel radii the rest of this file uses and
        blatant at forty-eight, where it stamped hard-edged rectangles and
        vertical streaks across the whole tile.

        Interpolating a small grid has no such artefact, is what value noise
        actually is, and is faster. Wrap-safety comes from tiling the grid 3x3
        before the interpolation and cropping back to the centre, so the
        interpolant is periodic rather than merely looking like it.
        """
        g = r.random((grid, grid)).astype(np.float32)
        big = np.tile(g, (3, 3))
        up = Image.fromarray(big, mode="F").resize((3 * n, 3 * n), Image.BICUBIC)
        return np.asarray(up, dtype=np.float32)[n:2 * n, n:2 * n]

    # (grid size, weight). Grid 4 across a 512 tile is a patch ~128 texels wide;
    # tiled three times across a screen that lands near a tenth of the screen,
    # which is the scale frosted glass actually scatters at. Weights fall with
    # the feature size so the sum is not dominated by the noisiest octave.
    for grid, weight in ((4, 1.00), (8, 0.55), (16, 0.30), (32, 0.16)):
        o = octave(grid)
        o = o - o.mean()
        peak = max(1e-6, float(np.abs(o).max()))
        field += (o / peak) * weight

    field = (field - field.min()) / max(1e-6, (field.max() - field.min()))

    # A soft S-curve. Straight normalised noise has almost no area at either
    # end, so the pane comes out an even grey with no visible patches; this
    # pushes the field toward its extremes without hard-clipping either.
    field = field * field * (3.0 - 2.0 * field)

    # Biased low so the DEFAULT state of the pane is mostly clear glass with
    # scatter through it, rather than mostly scatter. The Lua side multiplies
    # this by the user's own strength on top.
    field = np.clip(field * 0.85 + 0.05, 0.0, 1.0)

    return rgba_lum(1.0, field)


def slot_mask():
    """Alpha mask for icon corners. Rounded square, 64px, radius 18."""
    return rgba_lum(1.0, rrect_mask((64, 64), 18))


def slot_shade():
    """Inner shadow inside the slot: transparent centre, dark toward the rim."""
    size = (64, 64)
    shape = rrect_mask(size, 18)
    inner = rrect_mask(size, 18, inset=9)
    shade = np.clip(shape - blur(inner, 5.0), 0, 1)
    return rgba_lum(0.0, shade * 0.55 * shape)


def slot_gloss():
    """Top-down specular sweep clipped to the slot shape."""
    size = (64, 64)
    shape = rrect_mask(size, 18)
    ramp = np.clip(vgrad(size, 1.0, 0.0, gamma=1.0) * 2.2 - 1.2, 0, 1)
    return rgba_lum(1.0, shape * ramp * 0.30)


def slot_edge():
    size = (64, 64)
    ring = np.clip(rrect_mask(size, 18) - rrect_mask(size, 18, inset=1.0), 0, 1)
    return rgba_lum(1.0, ring)


def slot_glow():
    """Active-ability glow: crisp 2px ring plus outward bloom.

    128x128 with the slot occupying the centre 64x64, so it is drawn at 2x the
    button size and stays centred.
    """
    size = (128, 128)
    core = rrect_mask(size, 50, inset=32)          # the 64px slot, centred
    inner = rrect_mask(size, 50, inset=34)
    ring = np.clip(core - inner, 0, 1)
    bloom = blur(core, 9.0)
    bloom = np.clip(bloom - core * 0.55, 0, 1) ** 1.15
    return rgba_lum(1.0, np.clip(ring * 0.95 + bloom * 0.55, 0, 1))


def circle_mask():
    """256, not 64.

    This is a *mask*, so it is magnified rather than minified - the minimap is
    380 physical pixels across on a 4K display and this is the shape cut out of
    it. At 64 its one texel of anti-aliasing was being stretched six times, which
    is the stair-stepped fringe around the map.
    """
    return rgba_lum(1.0, ellipse_mask((256, 256)))


def chip_disc():
    """A filled circle for a 26-32px chip.

    64, not 256. The client does not mipmap UI textures, so a 256px disc drawn
    at 30 is sampled 2x2 out of an image eight times too big - its
    anti-aliasing ramp compresses to well under a texel and the edge comes back
    crunchy. Circle-Mask stays 256 because it is MAGNIFIED onto the minimap;
    this is the same shape for the opposite job.
    """
    return rgba_lum(1.0, ellipse_mask((64, 64)))


def chip_rim():
    """The matching rim, ~4 texels of 64 rather than 5 of 256.

    A rim's width has to be a fraction of the RADIUS, not a fixed count of
    texels, or it vanishes the moment the art is drawn smaller than it was
    authored. At 64 with a 4-texel band, a 30px chip still lands on nearly two
    real pixels of rim; the 256 version landed on half of one.
    """
    return rgba_lum(1.0, rim_from_sdf(ellipse_sdf((64, 64), MARGIN), 4.0, peak=1.25))


def ring():
    """Circular rim for the level orb, the portrait and the aura icons.

    256 and feathered, for exactly the reason the pill's rim is. A hard two-texel
    annulus at 64 looked fine while it was drawn near 1:1 and rough the moment it
    was not - which is what happened to the level orb when everything else moved
    up a size and it did not.
    """
    size = (256, 256)
    return rgba_lum(1.0, rim_from_sdf(ellipse_sdf(size, MARGIN), 5.0, peak=1.4))


def orb_face():
    """The level orb: a filled disc with a diagonal sheen and its own rim.

    One texture rather than a disc plus a separate ring, and the rim is a
    brighter VALUE of the same greyscale - so a single vertex colour still
    expresses both. That is the thing minimap_border() could not do, because its
    two tones were different hues rather than two points on one ramp.

    The sheen runs dark at the bottom-right to light at the top-left, which is
    where the concept puts it.

    128, not 256. The orb is 46px, so 256 would be minified five times and the
    client does not mipmap UI textures - the same argument chip_disc() makes.
    """
    n = 128
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)

    # 1 at the top-left corner, 0 at the bottom-right. Row 0 is the top.
    t = 1.0 - (xx + yy) / (2.0 * (n - 1))

    inside = ellipse_mask((n, n))
    # 5.0 texels of 128 is about 1.8 real pixels on a 46px orb. 3.5 was too
    # skinny once the ring stopped lapping proud of it.
    rim = rim_from_sdf(ellipse_sdf((n, n), MARGIN), 5.0, peak=1.2)

    face = (0.55 + 0.30 * t) * inside
    return rgba_lum(np.maximum(face, rim), np.maximum(inside, rim))


def orb_ring():
    """The level orb's fine outer highlight, authored for a 46px draw.

    128, not 256. Ring() is authored for the minimap and the portrait, and at
    46px it is minified 5.6 times - its AA ramp compresses to about half a real
    pixel and the edge comes back jagged. That is the whole of "the orb's edge
    looks rougher than the tooltip badge's": Chip-Rim is 64 drawn at 26, a 2.5x
    minification, so its ramp arrives as a clean pixel and a bit.

    At 128 drawn at 46 this is 2.8x, which puts the ramp at about 1.1px - the
    same ballpark as the badge.
    """
    n = 128
    return rgba_lum(1.0, rim_from_sdf(ellipse_sdf((n, n), MARGIN), 2.5, peak=1.0))


def minimap_border():
    """The map's whole edge treatment in one texture: a dark band around the
    inside, and a light hairline sitting on the very edge.

    It was two textures - a rim and an inner vignette - and that was the mistake.
    Two textures on one frame is a draw order, a second colour to set and a
    second config value to gate, and on this element I got the order wrong twice
    and the gate wrong once. One texture has none of those.

    The colours are baked into RGB and it is drawn untinted, because a single
    vertex colour cannot express two tones. That breaks this file's usual rule of
    neutral greyscale tinted at runtime - and the justification is that the
    concept's minimap border is neutral grey rather than skin-coloured, so there
    was never anything here that wanted tinting.
    """
    n = 512
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) / 2.0
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2)
    # The circle reaches the very edge of the texture, and the module draws it a
    # few pixels proud of the map. That overlap is the point: a mask's edge is
    # the client's to anti-alias and it does a poor job of it, so the border has
    # to lap *over* the map rather than stop short and leave the mask's own
    # stair-stepping showing outside it.
    R = n / 2.0 - MARGIN

    # Dark band: solid at the edge, easing away inward. Thick enough to read as
    # a border rather than a shadow - the concept's is about a seventh of the
    # radius, which at this size is 36 texels.
    band = np.clip((r - (R - 0.155 * R)) / (0.105 * R), 0.0, 1.0) ** 0.75
    # Bright hairline, a couple of texels in from the outer edge.
    rim = np.clip(1.0 - np.abs(r - (R - 2.2)) / 2.4, 0.0, 1.0)

    aa = _cover(r - R)                           # analytic anti-aliasing
    a = np.clip(band * 0.85 + rim * 0.85, 0.0, 1.0) * aa

    # Where the hairline dominates the coverage, the texel is light; where the
    # band does, it is dark.
    w = np.clip(rim * 0.85 / np.maximum(a, 1e-6), 0.0, 1.0)
    lum = 0.09 + w * 0.80

    out = np.zeros((n, n, 4), dtype=np.float32)
    out[:, :, 0] = out[:, :, 1] = out[:, :, 2] = lum
    out[:, :, 3] = a
    return out


def ring_glow():
    size = (128, 128)
    core = ellipse_mask(size, inset=32)
    bloom = blur(core, 10.0)
    bloom = np.clip(bloom - core * 0.7, 0, 1) ** 1.2
    return rgba_lum(1.0, bloom * 0.85)


def bar_smooth():
    """Status bar fill: near-flat with a soft top light and a hint of bottom shade."""
    size = (128, 32)
    lum = vgrad(size, 1.0, 0.72, gamma=0.7)
    a = vgrad(size, 1.0, 0.92, gamma=1.0)
    return rgba_lum(lum, a)


def bar_flat():
    return rgba_lum(1.0, np.ones((8, 8), dtype=np.float32))


def bar_mask():
    """Alpha mask giving status bars rounded ends.

    512x32 capsule, radius 16 - the same proportions as the 256x16 this started
    as, at twice the size and with a margin sized for it.

    Two corrections, one in each direction:

    * MARGIN is 0.5 here, not 2. Every other shape is inset by two texels so its
      anti-aliasing has somewhere to live; two out of a sixteen-texel height is
      an eighth of the bar, which shrank every bar by 12% and took the caps
      sub-pixel - the cast bar's ends came out square while the shorter health
      and power bars got away with it.
    * **The mask's aspect ratio has to match the bar's.** This is the one that
      actually made the ends pointy, and it had nothing to do with sampling. A
      cap keeps its shape only if radius/textureWidth * barWidth == barHeight/2,
      and since radius is textureHeight/2 that reduces to
      textureHeight/textureWidth == barHeight/barWidth. The mask was 16:1 while
      a health bar is 28.6:1, so every cap was drawn nearly twice as wide as it
      was tall - and a semicircle stretched to twice its width is a long shallow
      taper, which is precisely what "pointy" looks like. 1024x32 is 32:1, which
      lands a 200x7 bar's cap within 5% of a true semicircle.

    The cast bar is longer again at 43:1, so its caps stay a little elongated.
    One mask cannot be exact for two different aspect ratios, and being slightly
    too round is the failure worth having.

    Applied to the *background* extent so the fill keeps a square leading edge,
    which is what you want on a depleting bar - a rounded head reads as "nearly
    empty".
    """
    return rgba_lum(1.0, rrect_mask((1024, 32), 16, margin=0.5))


def bar_glow():
    """Additive bloom laid over a bar fill (cast bar, xp bar)."""
    size = (128, 32)
    a = vgrad(size, 0.55, 0.0, gamma=1.6) + vgrad(size, 0.0, 0.25, gamma=1.6)
    return rgba_lum(1.0, np.clip(a, 0, 1))


def glow_soft():
    """Radial falloff, used additively for combat pulses and cast auras."""
    n = 128
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) / 2.0
    d = np.sqrt((x - c) ** 2 + (y - c) ** 2) / c
    a = np.clip(1.0 - d, 0, 1) ** 2.1
    return rgba_lum(1.0, a)


def vignette():
    """Full-screen corner darkening, matching the radial-gradient in the concepts."""
    n = 256
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) / 2.0
    # elliptical, focused slightly above centre like the mockups
    d = np.sqrt(((x - c) / c) ** 2 + ((y - c * 0.86) / c) ** 2)
    a = np.clip((d - 0.45) / 0.75, 0, 1) ** 1.6
    return rgba_lum(0.0, a)


def chevron():
    """A small V, for "there is something folded away under here".

    Drawn from the distance to two line segments rather than as a glyph: the
    bundled font is a text face and has no geometric shapes in it, and borrowing
    one from the game's own art would not match anything else here.
    """
    w, h = 128, 64
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    px, py = xx + 0.5, yy + 0.5

    def seg(ax, ay, bx, by):
        vx, vy = bx - ax, by - ay
        t = np.clip(((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy), 0, 1)
        return np.sqrt((px - ax - t * vx) ** 2 + (py - ay - t * vy) ** 2)

    d = np.minimum(seg(24, 18, 64, 44), seg(64, 44, 104, 18))
    return rgba_lum(1.0, _cover(d - 5.0))



def send_glyph():
    """The paper plane on the edit box: a triangle with a notch cut out of its
    back.

    Built from half-plane distances rather than a polygon fill for the same
    reason the chevron is built from segments - it is a shape, the bundled font
    is a text face, and PIL's polygon rasteriser is exactly what the SDF work
    earlier in this file replaced. A convex polygon's signed distance is the max
    of its edges' half-plane distances; the notch is a second triangle
    subtracted, which is max(d, -d_notch).
    """
    w, h = 128, 128
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    px, py = xx + 0.5, yy + 0.5

    def halfplane(ax, ay, bx, by):
        """Signed distance to the line ab, positive on its left."""
        vx, vy = bx - ax, by - ay
        n = np.hypot(vx, vy)
        return ((px - ax) * vy - (py - ay) * vx) / max(n, 1e-6)

    def tri(a, b, c):
        return np.maximum(np.maximum(
            halfplane(a[0], a[1], b[0], b[1]),
            halfplane(b[0], b[1], c[0], c[1])),
            halfplane(c[0], c[1], a[0], a[1]))

    body = tri((14, 14), (114, 64), (14, 114))
    notch = tri((14, 14), (58, 64), (14, 114))
    return rgba_lum(1.0, _cover(np.maximum(body, -notch)))


# The order here IS the row order Core/Media.lua indexes by. Change one and you
# must change the other; the harness checks that they still agree.
#
# Three letters, the same rule the composer's own capsule uses: first three
# characters of the channel, uppercased. A word long enough to read as a word
# competes with the name beside it, and at chat-line size the difference between
# "GENERAL" and "GEN" is legibility, not information - you are identifying a
# channel you already know, not reading it.
BADGES = ["SAY", "YEL", "PAR", "RAI", "GUI", "OFF", "WHI",
          "TO", "EMO", "GEN", "TRA", "LFG", "DEF"]

# The tile is 128 wide because that is the power of two the atlas needs; the
# pill only uses BADGE_PILL of it. Three characters in a pill as tall as this
# one wants an aspect near 2.3, and stretching it to the full tile would give
# 3.4 - a letterbox with three letters rattling around inside it.
BADGE_W, BADGE_H, BADGE_ROW, BADGE_PILL = 128, 512, 38, 88


def chat_badges():
    """Every channel pill in one atlas, one row each.

    Three things decide the shape of this asset.

    *One file, not thirteen.* An inline `|T...|t` takes texel coordinates
    natively, so an atlas costs exactly the same at the call site as a file per
    badge and saves twelve textures - which matters more than usual here,
    because a new .tga is not picked up until the client is restarted.

    *Uniform width.* Every pill is the same width whatever the code inside it,
    so the names after them line up down the left of the log. Sizing each pill
    to its own label is the obvious thing and it looks worse: thirteen ragged
    left edges.

    *RGB is filled everywhere, alpha carries the shape.* The rest of this file
    leans on `bleed()` to push colour outward into transparent texels so the
    bilinear filter cannot pull black into an edge. Bleeding an atlas would drag
    each row's ink into its neighbours, so instead the luminance field is
    written across the whole tile and only alpha is cut - which gets the same
    guarantee without any pixel needing to know what is above it.

    Two tones, because one vertex colour has to produce both the pill and the
    word: the pill sits at 0.55 luminance and 0.55 alpha, the glyphs at 1.0 of
    each. Tinted at runtime that reads as a translucent slab of the channel's
    colour with the word bright on top of it.
    """
    W, H, RH, PW = BADGE_W, BADGE_H, BADGE_ROW, BADGE_PILL
    assert len(BADGES) * RH <= H, "badge atlas overflows"
    assert PW <= W, "pill wider than the tile"

    pill = Image.new("L", (W * SS, H * SS), 0)
    text = Image.new("L", (W * SS, H * SS), 0)
    dp, dt = ImageDraw.Draw(pill), ImageDraw.Draw(text)

    font = ImageFont.truetype(os.path.join(FONTS, "Outfit-SemiBold.ttf"), 20 * SS)
    track = 1.4 * SS   # letter spacing: these are labels, not words to read

    for i, word in enumerate(BADGES):
        top, bottom = (i * RH + 3) * SS, (i * RH + 35) * SS
        dp.rounded_rectangle([1 * SS, top, (PW - 1) * SS, bottom],
                             radius=16 * SS, fill=255)

        widths = [dt.textlength(ch, font=font) for ch in word]
        total = sum(widths) + track * (len(word) - 1)
        x = (PW * SS - total) / 2.0
        mid = (i * RH + 19) * SS
        for ch, cw in zip(word, widths):
            dt.text((x, mid), ch, font=font, fill=255, anchor="lm")
            x += cw + track

    pm = np.asarray(pill.resize((W, H), Image.LANCZOS), dtype=np.float32) / 255.0
    tm = np.asarray(text.resize((W, H), Image.LANCZOS), dtype=np.float32) / 255.0
    tm = np.minimum(tm, pm)          # a glyph can never spill outside its pill

    out = np.zeros((H, W, 4), dtype=np.float32)
    out[:, :, :3] = (0.55 + 0.45 * tm)[..., None]
    out[:, :, 3] = np.maximum(pm * 0.55, tm)
    return out


def divider():
    """Soft 1px hairline that fades at both ends."""
    size = (128, 8)
    a = np.zeros(size[::-1], dtype=np.float32)
    a[3:5, :] = 1.0
    fade = np.clip(np.minimum(
        np.linspace(0, 1, size[0]) * 4.0,
        np.linspace(1, 0, size[0]) * 4.0), 0, 1)
    return rgba_lum(1.0, a * fade[None, :])


# --------------------------------------------------------------------------
# Toolbox icons
#
# One atlas, sixteen 128px cells in a 4x4 grid. Line art, drawn from distance
# fields exactly as the chevron and the send glyph are, and for the same reason
# they are: Outfit is a text face with no geometric shapes in it, and the client
# has no vector layer. A unicode gear rendered as the three bytes of its own
# UTF-8 drawn as latin, which is what "]lk" on the rail was.
#
# An atlas rather than sixteen files because a new .tga needs a client RESTART
# and not a reload - so the fewer of them there are, the fewer times anybody has
# to quit the game - and because an inline texture takes texel coordinates
# natively, which makes the call site no more expensive than a separate file.
#
# Stroke is uniform: every glyph is the set of points within STROKE/2 of some
# skeleton, so they carry the same weight beside each other. That is the whole
# trick to line art looking like one family rather than sixteen drawings.
# --------------------------------------------------------------------------

# DRAWN at 128 and STORED at 64. The glyphs are drawn at 26px on the rail and
# 20px in the menu row, so a 128 cell is minified five or six times and its
# stroke falls under a pixel - which is the speckling the rims elsewhere in this
# file already record. Stored at 64 it is minified two or three times, which is
# the ratio the panel corners use and the one that comes out clean.
#
# Drawing at 128 first is not waste: it is the 2x supersample the curves want,
# and LANCZOS down to 64 is what puts four samples on every arc.
ICON_DRAW = 128
ICON_CELL = 64
ICON_COLS = 8
ICON_ROWS = 8
ICON_STROKE = 8.5          # in DRAW space, so ~4 stored texels

# The order IS the index Core/Media.lua reads. Change one and change the other;
# the harness checks they still agree.
ICON_ORDER = [
    # the micro menu, in the order Blizzard's own Vanilla overrides declare them
    "character", "spellbook", "talents", "quests",
    "social", "guild", "map", "menu",
    # ...then help, the settings tiles, and the rail's gear
    "help", "zen", "damage", "keybinds",
    "combat", "gear", "pin", "pinned",
    # and the What's-new card's own mark
    "whatsnew",
    # mail, empty and full
    "mail", "mailfull",
    # the frame lock
    "lock",
    # getting off a taxi at the next stop
    "exit",
    # the in-flight console: three channels, a transport, a drag handle
    "music", "podcast", "gossip",
    "play", "pause", "prev", "next",
    "grip", "tick",
    # ...and the drawer you pick from
    "library",
    # the entertainment console, as a settings tile
    "ifec",
    # actual size, for a magazine page bigger than the window it is in
    "zoom",
    # shutting a window, as art rather than as a character
    "close",
]


def _icon_field(cell):
    """Coordinate grids for one cell, in cell-local pixels."""
    yy, xx = np.mgrid[0:cell, 0:cell].astype(np.float32)
    return xx + 0.5, yy + 0.5


def _icon_ops(px, py):
    """Distance primitives. Each returns distance to a SKELETON, unstroked."""

    def seg(ax, ay, bx, by):
        vx, vy = bx - ax, by - ay
        dd = vx * vx + vy * vy
        t = np.clip(((px - ax) * vx + (py - ay) * vy) / max(dd, 1e-6), 0, 1)
        return np.sqrt((px - ax - t * vx) ** 2 + (py - ay - t * vy) ** 2)

    def circ(cx, cy, r):
        """The OUTLINE of a circle, not the disc."""
        return np.abs(np.hypot(px - cx, py - cy) - r)

    def disc(cx, cy, r):
        return np.hypot(px - cx, py - cy) - r

    def arc(cx, cy, r, a0, a1):
        """A circle outline kept only between two angles, in degrees, measured
        anticlockwise from east. Built by masking the outline rather than by
        walking segments, so the curvature stays exact."""
        ang = np.degrees(np.arctan2(-(py - cy), px - cx)) % 360.0
        a0, a1 = a0 % 360.0, a1 % 360.0
        inside = (ang >= a0) & (ang <= a1) if a0 <= a1 else (ang >= a0) | (ang <= a1)
        # Outside the sweep, fall back to the distance to the nearer endpoint so
        # the stroke ends in a round cap rather than a hard cut.
        ex0 = (cx + r * np.cos(np.radians(a0)), cy - r * np.sin(np.radians(a0)))
        ex1 = (cx + r * np.cos(np.radians(a1)), cy - r * np.sin(np.radians(a1)))
        caps = np.minimum(np.hypot(px - ex0[0], py - ex0[1]),
                          np.hypot(px - ex1[0], py - ex1[1]))
        return np.where(inside, np.abs(np.hypot(px - cx, py - cy) - r), caps)

    def rect(x0, y0, x1, y1):
        """The outline of a rectangle."""
        return np.minimum(np.minimum(seg(x0, y0, x1, y0), seg(x1, y0, x1, y1)),
                          np.minimum(seg(x1, y1, x0, y1), seg(x0, y1, x0, y0)))

    def box(x0, y0, x1, y1):
        """A FILLED rectangle, signed: negative inside. `rect` is the outline of
        the same shape, and the two together are how one silhouette gets an
        empty state and a full one - the pin/pinned pair, done with corners."""
        cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        hx, hy = (x1 - x0) / 2.0, (y1 - y0) / 2.0
        dx, dy = np.abs(px - cx) - hx, np.abs(py - cy) - hy
        return (np.hypot(np.maximum(dx, 0), np.maximum(dy, 0))
                + np.minimum(np.maximum(dx, dy), 0))

    return seg, circ, disc, arc, rect, box


def _glyph(name, cell):
    px, py = _icon_field(cell)
    seg, circ, disc, arc, rect, box = _icon_ops(px, py)
    INF = np.full_like(px, 1e6)

    def U(*ds):
        out = ds[0]
        for d in ds[1:]:
            out = np.minimum(out, d)
        return out

    if name == "character":
        # A head and a pair of shoulders. The shoulders are an arc rather than a
        # curve fitted from segments, so they stay a true circle at any size.
        return U(circ(64, 44, 19), arc(64, 100, 32, 20, 160))

    if name == "spellbook":
        # A book: covers and a spine.
        return U(rect(26, 26, 102, 102), seg(64, 26, 64, 102))

    if name == "talents":
        # A four-point star. Two crossing strokes with the diagonals shorter, so
        # it reads as a sparkle rather than as an asterisk.
        return U(seg(64, 20, 64, 108), seg(20, 64, 108, 64),
                 seg(38, 38, 90, 90), seg(90, 38, 38, 90))

    if name == "quests":
        # A sheet with lines on it.
        return U(rect(30, 22, 98, 106),
                 seg(46, 48, 82, 48), seg(46, 66, 82, 66), seg(46, 84, 68, 84))

    if name == "social":
        # Two figures, the second smaller and behind.
        return U(circ(50, 46, 16), arc(50, 98, 27, 25, 155),
                 circ(88, 52, 12), arc(88, 98, 21, 20, 90))

    if name == "guild":
        # A shield: shoulders, sides, and a point.
        return U(seg(64, 22, 26, 40), seg(26, 40, 26, 68), seg(26, 68, 64, 108),
                 seg(64, 108, 102, 68), seg(102, 68, 102, 40), seg(102, 40, 64, 22))

    if name == "map":
        # A folded map: three panels, the folds alternating.
        return U(seg(24, 34, 24, 96), seg(24, 96, 64, 82), seg(64, 82, 104, 96),
                 seg(104, 96, 104, 34), seg(104, 34, 64, 48), seg(64, 48, 24, 34),
                 seg(64, 48, 64, 82))

    if name == "menu":
        # Three bars. The game menu, and the one glyph everybody already knows.
        return U(seg(28, 42, 100, 42), seg(28, 64, 100, 64), seg(28, 86, 100, 86))

    if name == "help":
        # A ring, a hook and a dot - a question mark built as a shape, since
        # there is no font glyph to borrow.
        #
        # The hook sweeps ANTICLOCKWISE from 340 through 90 to 200, which is the
        # top and left of the circle. The first attempt asked for 200 to 20,
        # which sweeps the other way round through the bottom and drew the mark
        # upside down - a Y with a dot under it.
        return U(circ(64, 64, 42),
                 arc(64, 50, 13, 340, 200),
                 seg(76, 55, 64, 70),
                 disc(64, 84, 3.0))

    if name == "zen":
        # Three breaths, each shorter than the last, curling at the end. The
        # concept's zen mark is wind rather than a person sitting.
        return U(seg(26, 44, 82, 44), arc(82, 52, 8, 270, 90),
                 seg(26, 64, 94, 64), arc(94, 72, 8, 270, 90),
                 seg(26, 84, 70, 84), arc(70, 92, 8, 270, 90))

    if name == "damage":
        # A hash: floating combat text is numbers.
        return U(seg(44, 26, 34, 102), seg(84, 26, 74, 102),
                 seg(26, 48, 100, 48), seg(24, 76, 98, 76))

    if name == "keybinds":
        # A key cap: a rounded square with a lozenge inside it.
        return U(rect(24, 36, 104, 92), rect(44, 54, 84, 74))

    if name == "combat":
        # Two crossed blades. Diagonals with a guard across each.
        return U(seg(30, 100, 92, 34), seg(84, 26, 100, 42), seg(78, 44, 90, 56),
                 seg(98, 100, 36, 34), seg(44, 26, 28, 42), seg(50, 44, 38, 56))

    if name == "gear":
        # A ring with eight teeth and a hub. Teeth are radial stubs rather than
        # a toothed outline: at 26px on the rail the difference is invisible and
        # the stub version cannot alias into a blur.
        d = U(circ(64, 64, 30), circ(64, 64, 11))
        for k in range(8):
            a = np.radians(k * 45.0)
            ca, sa = np.cos(a), np.sin(a)
            d = np.minimum(d, seg(64 + 30 * ca, 64 - 30 * sa,
                                  64 + 44 * ca, 64 - 44 * sa))
        return d

    if name == "pin":
        # An outline pin, for a row that is not pinned.
        return U(circ(64, 48, 22), seg(64, 70, 64, 106))

    if name == "pinned":
        # The same pin, filled. Drawn as a disc so the two read as one control
        # in two states rather than as two different marks.
        return U(disc(64, 48, 22) - ICON_STROKE / 2, seg(64, 70, 64, 106))

    if name == "whatsnew":
        # A BELL. The first attempt was a four-point star with a smaller one
        # beside it, which is talents wearing a plus - two marks in the same
        # panel saying the same thing, and the one place a reader looks to find
        # out what changed reading as "sparkle" twice.
        #
        # A bell is unambiguous, and it is the shape every other piece of
        # software uses for "there is something new here".
        dome = arc(64, 62, 26, 0, 180)
        sides = U(seg(38, 62, 38, 84), seg(90, 62, 90, 84))
        lip = seg(28, 84, 100, 84)
        clapper = arc(64, 92, 8, 200, 340)
        crown = seg(64, 30, 64, 36)
        return U(dome, sides, lip, clapper, crown)

    # ---- the in-flight console -------------------------------------------
    #
    # Three channels and a transport. The channel marks go INSIDE the shapes
    # the design gives each one - circle for music, square for gossip, diamond
    # for podcast - so the shape carries the identity and the glyph only has to
    # be recognisable at 16px inside it.

    if name == "music":
        # A waveform: five bars, tallest in the middle. Not a note - a quaver at
        # this size is a blob with a stick, and every music player on earth
        # draws bars.
        return U(seg(34, 74, 34, 54), seg(49, 84, 49, 44), seg(64, 92, 64, 36),
                 seg(79, 84, 79, 44), seg(94, 74, 94, 54))

    if name == "podcast":
        # A microphone: capsule, cradle, stem, foot.
        return U(rect(52, 24, 76, 68),
                 arc(64, 62, 26, 200, 340),
                 seg(64, 88, 64, 102),
                 seg(46, 102, 82, 102))

    if name == "gossip":
        # A folded paper: masthead rule and two lines of type. The rule is what
        # says newspaper rather than document.
        return U(rect(22, 30, 106, 98),
                 seg(22, 52, 106, 52),
                 seg(38, 68, 90, 68),
                 seg(38, 82, 74, 82))

    if name == "play":
        return U(seg(48, 32, 48, 96), seg(48, 32, 98, 64), seg(48, 96, 98, 64))

    if name == "pause":
        return U(seg(50, 34, 50, 94), seg(78, 34, 78, 94))

    if name == "prev":
        # Bar on the leading edge, triangle pointing into it.
        return U(seg(34, 36, 34, 92),
                 seg(94, 36, 52, 64), seg(94, 92, 52, 64), seg(94, 36, 94, 92))

    if name == "next":
        return U(seg(94, 36, 94, 92),
                 seg(34, 36, 76, 64), seg(34, 92, 76, 64), seg(34, 36, 34, 92))

    if name == "grip":
        # Two columns of three. The universal "drag me", and the only glyph here
        # that is dots rather than strokes.
        return U(disc(50, 40, 2.0), disc(78, 40, 2.0),
                 disc(50, 64, 2.0), disc(78, 64, 2.0),
                 disc(50, 88, 2.0), disc(78, 88, 2.0))

    if name == "library":
        # Adding to the programme: a short list with a plus beside it.
        #
        # NOT a book. Three leaning spines are a lovely shape at 64 texels and
        # mush at the twelve pixels this is drawn at, which is the lesson the
        # rim notes in this file already record. And not the chevron, which
        # means "this opens" everywhere else in the interface.
        #
        # The last rule stops short so the plus has clear air around it: at this
        # size a stroke and a glyph that touch read as one blob.
        return U(seg(24, 36, 92, 36),
                 seg(24, 60, 92, 60),
                 seg(24, 84, 58, 84),
                 seg(84, 68, 84, 100), seg(68, 84, 100, 84))

    if name == "ifec":
        # Headphones: a band over two cups. The console's own mark is the dial,
        # and a dial at twelve pixels is a circle - of which this sheet has
        # several. What this tile switches is the thing you LISTEN to.
        return U(arc(64, 70, 34, 20, 160),
                 seg(32, 70, 32, 92), seg(96, 70, 96, 92))

    if name == "zoom":
        # A magnifier. NOT a plus or a pair of arrows: this toggles between
        # fitting the page and showing it at actual size, and both of those
        # read as "make the window bigger" on any other glyph.
        return U(circ(56, 54, 26), seg(75, 74, 100, 100))

    if name == "close":
        # A cross, DRAWN rather than typed. The multiplication sign is what the
        # older windows here use for this, and it is a font's business whether
        # it has one - Outfit does not carry it in every weight, and the weight
        # this landed in rendered the notdef box and then the digits of the
        # escape. Line art has no such opinion.
        return U(seg(36, 36, 92, 92), seg(92, 36, 36, 92))

    if name == "tick":
        # Finished. Shorter leading stroke than a drawn tick would have, because
        # at 11px the long diagonal is what reads and the short one is noise.
        return U(seg(32, 66, 54, 88), seg(54, 88, 98, 36))

    if name == "exit":
        # Getting off at the next stop: an arrow coming DOWN onto a ground line.
        #
        # NOT a chevron. The chevron already means "this opens" everywhere else
        # in the interface - the toolbox rail, every dropdown - and borrowing it
        # here would tell a player the button opens something. The stem and the
        # bar under it are what make this a different silhouette at 11px, so the
        # bar is deliberately wider than the head.
        return U(seg(64, 26, 64, 78),
                 seg(46, 60, 64, 78), seg(82, 60, 64, 78),
                 seg(30, 98, 98, 98))

    if name == "lock":
        # A padlock: a body and a shackle. ONE glyph for both states, because
        # the tile carries on and off in its chip the way every other settings
        # tile does - a second drawing would be a second thing saying the same
        # thing, and they can disagree.
        #
        # The shackle is an arc rather than a squared-off staple: at 17px in the
        # chip a staple's two corners land on the same texel and it reads as a
        # blob with a bite out of it.
        return U(rect(34, 62, 94, 108),
                 arc(64, 62, 20, 0, 180),
                 seg(44, 62, 44, 54), seg(84, 62, 84, 54))

    # An envelope, twice: an outline for "no mail" and a solid one for "mail".
    # Same silhouette, same corners, so the two read as one control in two
    # states rather than as two drawings - which is the pin/pinned rule, and the
    # reason the flap is in exactly the same place in both.
    #
    # FILLS THE CELL, like the gear it sits next to on the rail. The first
    # version was 84x50 in a 128 cell while the gear is an 88 circle, so it
    # carried about half the ink of its neighbour and read as both smaller and
    # thinner - the stroke was identical, there was just less of it. An icon
    # family is matched on how much of the cell it uses, not only on stroke.
    #
    # Still wider than tall, at 3:2, because a square envelope reads as a note
    # or a card. At 18px on the rail the proportion is most of what says
    # "envelope" before the flap is legible at all.
    MAIL = (16, 32, 112, 96)

    if name == "mail":
        x0, y0, x1, y1 = MAIL
        # The flap creases from the top corners down to a point below centre,
        # which is where a real one folds - level with the top edge it reads as
        # a triangle sitting on a box.
        return U(rect(x0, y0, x1, y1),
                 seg(x0, y0, (x0 + x1) / 2, y0 + 34),
                 seg(x1, y0, (x0 + x1) / 2, y0 + 34))

    if name == "mailfull":
        x0, y0, x1, y1 = MAIL
        body = box(x0, y0, x1, y1) + ICON_STROKE / 2

        # The flap is CARVED OUT rather than drawn on: a stroke of the same
        # colour on a solid fill is invisible, and negative space is the only
        # thing that survives on a filled shape. max() with a negated distance
        # is subtraction - everything within CARVE of the crease is taken back
        # out of the body.
        #
        # CARVE is a whole stroke and a half, not the half-stroke that draws a
        # line. A cut has to survive being minified to a 64px cell and then
        # drawn at 26, and at half a stroke it came out under a stored texel:
        # the icon read as a plain white rectangle at the only size it is ever
        # seen. This is the same reason the gear's teeth are stubs.
        CARVE = ICON_STROKE * 1.5
        crease = np.minimum(seg(x0, y0, (x0 + x1) / 2, y0 + 36),
                            seg(x1, y0, (x0 + x1) / 2, y0 + 36))
        return np.maximum(body, CARVE - crease)

    return INF


def toolbox_icons():
    cell, cols, draw = ICON_CELL, ICON_COLS, ICON_DRAW

    # The sheet is a FIXED 8x8. Sizing it to the number of icons gives 512x192
    # at seventeen of them, and the client wants power-of-two on both axes - so
    # the grid is constant and the spare cells are empty. Sixty-four slots in a
    # megabyte, and adding an icon never moves an existing one.
    rows = ICON_ROWS
    assert len(ICON_ORDER) <= cols * rows, "icon sheet is full"
    w, h = cell * cols, cell * rows

    out = np.zeros((h, w, 4), dtype=np.float32)
    for i, name in enumerate(ICON_ORDER):
        r, c = divmod(i, cols)
        d = _glyph(name, draw)
        a = _cover(d - ICON_STROKE / 2)

        # Down to the stored cell with LANCZOS, which is what puts four samples
        # on every arc rather than the one the rasteriser would give at 64.
        img = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), mode="L")
        img = img.resize((cell, cell), Image.LANCZOS)
        a = np.asarray(img, dtype=np.float32) / 255.0

        out[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell] = rgba_lum(1.0, a)

    return out


# The flight dial. 44px outer, 35px inner disc, so the ring it draws is a
# 4.5px band - see the design's header capsule.
DIAL_CELL = 64          # authored size; 1.5x minification at 44px, like Chip-Disc
DIAL_STEPS = 64         # frames in the arc sheet
DIAL_COLS = 8           # laid out 8x8, so the sheet is a power of two

# Clear texels around the ring, on top of MARGIN. The cells of a sheet touch, so
# a ring drawn to the edge of its cell is one bilinear sample away from being
# read as part of the frame next door.
DIAL_PAD = 2.0

# The ring occupies this much of its cell, which is what the module scales by to
# land the drawn ring on the design's 44px.
DIAL_RING = (DIAL_CELL - 2.0 * (MARGIN + DIAL_PAD)) / DIAL_CELL

# 4.5px of band on a 44px ring.
DIAL_BAND = 4.5 * (DIAL_CELL * DIAL_RING) / 44.0


def _annulus(n, scale, band, pad):
    """A ring: the disc, less the smaller disc inside it.

    `band` and `pad` are in FINAL texels and scaled up here - drawing at SS and
    passing MARGIN straight through would leave a half-texel margin rather than
    two, which put the ring hard against the edge of its cell.

    Hard-edged, like _sweep: the downsample is what anti-aliases it.
    """
    inset = (MARGIN + pad) * scale
    outer = (ellipse_sdf((n, n), inset) < 0.0).astype(np.float32)
    inner = (ellipse_sdf((n, n), inset + band * scale) < 0.0).astype(np.float32)
    return np.clip(outer - inner, 0.0, 1.0)


def _sweep(n, turns):
    """1 where the angle from twelve o'clock, going clockwise, is within `turns`.

    Hard-edged on purpose. It is drawn at SS and taken down with LANCZOS, which
    is what puts the anti-aliasing on the two radial edges - an analytic ramp
    would have to be in angle, and an angular ramp is a different width in
    texels at the inside of the band than at the outside.
    """
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    px = xx + 0.5 - n / 2.0
    py = yy + 0.5 - n / 2.0
    ang = np.arctan2(px, -py)                    # 0 straight up, growing clockwise
    ang = np.mod(ang, 2.0 * np.pi) / (2.0 * np.pi)
    return (ang <= turns).astype(np.float32)


def _shrink(mask, n):
    img = Image.fromarray(np.clip(mask * 255.0, 0, 255).astype(np.uint8), mode="L")
    return np.asarray(img.resize((n, n), Image.LANCZOS), dtype=np.float32) / 255.0


def ifec_dial_track():
    """The dial's unfilled ring, under the arc. Same geometry as one arc cell."""
    big = _annulus(DIAL_CELL * SS, SS, DIAL_BAND, DIAL_PAD)
    return rgba_lum(1.0, _shrink(big, DIAL_CELL))


def ifec_dial_arc():
    """The filled part of the dial, as a sheet of 64 steps.

    Classic has no conic gradient and no way to fill a ring by angle, so the
    steps are baked and the module picks a cell. 64 of them on a three-minute
    flight is a step every three seconds, which is under the eye's threshold for
    something moving this slowly - and it costs one SetTexCoord rather than a
    mask stack that would have to be rebuilt every frame.

    Frame i is (i+1)/64 of a turn, so the last frame is the full ring and the
    empty state is the texture hidden rather than a wasted cell.
    """
    cols = DIAL_COLS
    rows = DIAL_STEPS // cols
    n = DIAL_CELL
    sheet = np.zeros((rows * n, cols * n), dtype=np.float32)

    band = _annulus(n * SS, SS, DIAL_BAND, DIAL_PAD)
    for i in range(DIAL_STEPS):
        cell = _shrink(band * _sweep(n * SS, (i + 1) / float(DIAL_STEPS)), n)
        r, c = divmod(i, cols)
        sheet[r * n:(r + 1) * n, c * n:(c + 1) * n] = cell

    return rgba_lum(1.0, sheet)


ASSETS = {
    "IFEC-Dial-Track": ifec_dial_track,
    "IFEC-Dial-Arc": ifec_dial_arc,
    "Glass-Panel": glass_panel,
    "Glass-Panel-Edge": glass_panel_edge,
    "Glass-Pill": glass_pill,
    "Glass-Pill-Edge": glass_pill_edge,
    "Glass-Shadow": glass_shadow,
    "Glass-Pill-Shadow": glass_pill_shadow,
    "Noise": noise_tile,
    "Frost": frost_tile,
    "Slot-Mask": slot_mask,
    "Slot-Shade": slot_shade,
    "Slot-Gloss": slot_gloss,
    "Slot-Edge": slot_edge,
    "Slot-Glow": slot_glow,
    "Circle-Mask": circle_mask,
    "Chip-Disc": chip_disc,
    "Chip-Rim": chip_rim,
    "Ring": ring,
    "Orb-Face": orb_face,
    "Orb-Ring": orb_ring,
    "Ring-Glow": ring_glow,
    "Minimap-Border": minimap_border,
    "Bar-Smooth": bar_smooth,
    "Bar-Flat": bar_flat,
    "Bar-Mask": bar_mask,
    "Bar-Glow": bar_glow,
    "Glow-Soft": glow_soft,
    "Vignette": vignette,
    "Send": send_glyph,
    "Divider": divider,
    "Chevron": chevron,
    "Chat-Badges": chat_badges,
    "Toolbox-Icons": toolbox_icons,
}

NO_BLEED = {"Noise", "Frost", "Bar-Flat", "Bar-Smooth", "Bar-Glow", "Vignette",
            "Glass-Shadow", "Glass-Pill-Shadow", "Minimap-Border",
            # Its rows are neighbours. Bleeding would pull each word's ink into
            # the pill above and below it; it fills RGB itself instead.
            "Chat-Badges",
            # A sheet whose cells touch: the ring reaches the edge of its cell,
            # so a bleed would run one frame's arc into the next.
            "IFEC-Dial-Arc"}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Media", "Textures")
    os.makedirs(out, exist_ok=True)

    for name, fn in ASSETS.items():
        img = fn()
        if name not in NO_BLEED:
            img = bleed(img)
        path = write_tga(os.path.join(out, name + ".tga"), img)
        h, w = img.shape[:2]
        print(f"  {name:<18} {w:>4}x{h:<4} {os.path.getsize(path):>8} bytes")

    print(f"\n{len(ASSETS)} textures -> {out}")


if __name__ == "__main__":
    main()
