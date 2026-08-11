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


def ring():
    """Circular rim for the level orb, the portrait and the aura icons.

    256 and feathered, for exactly the reason the pill's rim is. A hard two-texel
    annulus at 64 looked fine while it was drawn near 1:1 and rough the moment it
    was not - which is what happened to the level orb when everything else moved
    up a size and it did not.
    """
    size = (256, 256)
    return rgba_lum(1.0, rim_from_sdf(ellipse_sdf(size, MARGIN), 5.0, peak=1.4))


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


ASSETS = {
    "Glass-Panel": glass_panel,
    "Glass-Panel-Edge": glass_panel_edge,
    "Glass-Pill": glass_pill,
    "Glass-Pill-Edge": glass_pill_edge,
    "Glass-Shadow": glass_shadow,
    "Glass-Pill-Shadow": glass_pill_shadow,
    "Noise": noise_tile,
    "Slot-Mask": slot_mask,
    "Slot-Shade": slot_shade,
    "Slot-Gloss": slot_gloss,
    "Slot-Edge": slot_edge,
    "Slot-Glow": slot_glow,
    "Circle-Mask": circle_mask,
    "Ring": ring,
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
}

NO_BLEED = {"Noise", "Bar-Flat", "Bar-Smooth", "Bar-Glow", "Vignette",
            "Glass-Shadow", "Glass-Pill-Shadow", "Minimap-Border",
            # Its rows are neighbours. Bleeding would pull each word's ink into
            # the pill above and below it; it fills RGB itself instead.
            "Chat-Badges"}


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
