#!/usr/bin/env python3
"""
Render the generated textures the way Core\\Glass.lua composites them in game.

This is a check on the art, not on the Lua: it reproduces the same slice
fractions, the same layer order and the same palette tokens, so if the corner
geometry or the tinting is wrong it shows up here rather than in a loading
screen. It also doubles as the reference image for what the skin is meant to
look like.

Run:  python3 Tools/preview.py
Out:  Tools/preview.png
"""

import os
import struct

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEX = os.path.join(ROOT, "Media", "Textures")
FONTS = os.path.join(ROOT, "Media", "Fonts")


# --------------------------------------------------------------------------
# TGA input (mirrors Tools/generate_textures.py's writer)
# --------------------------------------------------------------------------

def load_tga(name):
    data = open(os.path.join(TEX, name + ".tga"), "rb").read()
    idlen, cmap, imtype = data[0], data[1], data[2]
    w, h = struct.unpack_from("<HH", data, 12)
    depth, desc = data[16], data[17]
    assert imtype == 2 and depth == 32, f"{name}: unexpected TGA type"
    px = np.frombuffer(data, dtype=np.uint8, offset=18 + idlen).reshape(h, w, 4)
    rgba = px[:, :, [2, 1, 0, 3]]            # BGRA -> RGBA
    if not (desc & 0x20):                    # bottom-left origin
        rgba = rgba[::-1]
    return Image.fromarray(rgba, "RGBA")


# --------------------------------------------------------------------------
# slicing, matching Core\Glass.lua
# --------------------------------------------------------------------------

def _piece(img, u0, u1, v0, v1, w, h):
    W, H = img.size
    box = (int(round(u0 * W)), int(round(v0 * H)), int(round(u1 * W)), int(round(v1 * H)))
    return img.crop(box).resize((max(1, int(round(w))), max(1, int(round(h)))), Image.LANCZOS)


def nine_slice(img, w, h, corner, frac=0.25):
    """corner = rendered size of each corner piece, in pixels."""
    w, h = int(round(w)), int(round(h))
    c = int(round(corner))
    c = max(1, min(c, w // 2, h // 2))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    a, b = frac, 1 - frac
    mw, mh = w - 2 * c, h - 2 * c

    out.paste(_piece(img, 0, a, 0, a, c, c), (0, 0))
    out.paste(_piece(img, b, 1, 0, a, c, c), (w - c, 0))
    out.paste(_piece(img, 0, a, b, 1, c, c), (0, h - c))
    out.paste(_piece(img, b, 1, b, 1, c, c), (w - c, h - c))
    if mw > 0:
        out.paste(_piece(img, a, b, 0, a, mw, c), (c, 0))
        out.paste(_piece(img, a, b, b, 1, mw, c), (c, h - c))
    if mh > 0:
        out.paste(_piece(img, 0, a, a, b, c, mh), (0, c))
        out.paste(_piece(img, b, 1, a, b, c, mh), (w - c, c))
    if mw > 0 and mh > 0:
        out.paste(_piece(img, a, b, a, b, mw, mh), (c, c))
    return out


def three_slice(img, w, h, frac=0.25):
    """Pill: caps are always half the height wide, exactly as Glass.lua enforces."""
    w, h = int(round(w)), int(round(h))
    cap = max(1, min(h // 2, w // 2))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    a, b = frac, 1 - frac
    out.paste(_piece(img, 0, a, 0, 1, cap, h), (0, 0))
    out.paste(_piece(img, b, 1, 0, 1, cap, h), (w - cap, 0))
    mid = w - 2 * cap
    if mid > 0:
        out.paste(_piece(img, a, b, 0, 1, mid, h), (cap, 0))
    return out


def tint(img, color):
    """Texture:SetVertexColor - multiply RGB and alpha by the given colour."""
    r, g, b = color[0], color[1], color[2]
    a = color[3] if len(color) > 3 else 1.0
    arr = np.asarray(img).astype(np.float32) / 255.0
    arr[:, :, 0] *= r
    arr[:, :, 1] *= g
    arr[:, :, 2] *= b
    arr[:, :, 3] *= a
    return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA")


def over(dst, src, x, y, add=False):
    x, y = int(round(x)), int(round(y))
    if not add:
        dst.alpha_composite(src, (x, y))
        return dst
    # additive blend, for glows
    region = dst.crop((x, y, x + src.width, y + src.height))
    d = np.asarray(region).astype(np.float32)
    s = np.asarray(src).astype(np.float32)
    sa = (s[:, :, 3:4] / 255.0)
    d[:, :, :3] = np.clip(d[:, :, :3] + s[:, :, :3] * sa, 0, 255)
    dst.paste(Image.fromarray(d.astype(np.uint8), "RGBA"), (x, y))
    return dst


# --------------------------------------------------------------------------
# palette (kept in step with Core\Palette.lua)
# --------------------------------------------------------------------------

def C(r, g, b, a=1.0):
    return (r / 255.0, g / 255.0, b / 255.0, a)


SKINS = {
    "Midnight": dict(
        glass=C(12, 10, 28, 0.55), glassStrong=C(12, 10, 28, 0.68),
        edge=C(150, 130, 235, 0.32), shadow=C(0, 0, 0, 0.50),
        noise=C(255, 255, 255, 0.05),
        text=C(236, 230, 255), textDim=C(220, 210, 255, 0.55),
        health=(C(159, 232, 180), C(95, 198, 134)),
        power=(C(138, 180, 255), C(106, 144, 232)),
        hostileBar=(C(255, 154, 118), C(240, 110, 90)),
        targetGlass=C(24, 10, 20, 0.55), targetEdge=C(255, 138, 138, 0.35),
        targetText=C(255, 217, 196),
        cast=(C(142, 200, 255), C(212, 236, 255)), castEdge=C(150, 200, 255, 0.45),
        castGlow=C(140, 200, 255, 0.55),
        accent=C(185, 154, 245), xp=(C(138, 106, 224), C(185, 154, 245)),
        classOrb=(C(78, 139, 167), C(36, 66, 87)),      # Mage 69CCF0 through OrbColor
        mobOrb=(C(161, 124, 84), C(77, 59, 47)),        # hostile orange through OrbColor
    ),
    "Daylight": dict(
        glass=C(252, 248, 240, 0.17), glassStrong=C(252, 248, 240, 0.24),
        edge=C(255, 255, 255, 0.36), shadow=C(30, 15, 0, 0.35),
        noise=C(255, 255, 255, 0.05),
        text=C(255, 255, 255), textDim=C(255, 255, 255, 0.62),
        health=(C(159, 232, 180), C(111, 214, 150)),
        power=(C(168, 204, 245), C(127, 176, 236)),
        hostileBar=(C(255, 154, 118), C(240, 110, 90)),
        targetGlass=C(252, 248, 240, 0.17), targetEdge=C(255, 255, 255, 0.36),
        targetText=C(255, 255, 255),
        cast=(C(142, 200, 255), C(212, 236, 255)), castEdge=C(180, 220, 255, 0.50),
        castGlow=C(160, 210, 255, 0.45),
        accent=C(255, 235, 190, 0.95), xp=(C(185, 138, 224), C(217, 184, 240)),
        classOrb=(C(78, 139, 167), C(36, 66, 87)),
        mobOrb=(C(161, 124, 84), C(77, 59, 47)),
    ),
}


def font(weight, size):
    return ImageFont.truetype(os.path.join(FONTS, f"Outfit-{weight}.ttf"), size)


def rgb255(c, alpha=None):
    a = alpha if alpha is not None else (c[3] if len(c) > 3 else 1.0)
    return (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), int(a * 255))


# --------------------------------------------------------------------------
# element painters
# --------------------------------------------------------------------------

T = {}


def load_all():
    for n in ("Glass-Panel", "Glass-Panel-Edge", "Glass-Pill", "Glass-Pill-Edge",
              "Glass-Shadow", "Glass-Pill-Shadow", "Noise", "Slot-Mask", "Slot-Shade", "Slot-Gloss",
              "Slot-Edge", "Slot-Glow", "Circle-Mask", "Ring", "Ring-Glow",
              "Bar-Smooth", "Bar-Flat", "Bar-Glow", "Bar-Mask", "Glow-Soft",
              "Vignette", "Divider"):
        T[n] = load_tga(n)


def draw_pill(canvas, x, y, w, h, skin, fill_key="glass", edge_key="edge", shadow=None):
    # 1. ambient shadow: capsule-shaped 3-slice, always drawn at spread = h/4,
    #    which is the single ratio Glass-Pill-Shadow is authored for.
    s = h / 4
    sh = three_slice(T["Glass-Pill-Shadow"], w + 2 * s, h + 2 * s)
    over(canvas, tint(sh, skin["shadow"]), x - s, y - s)

    # 2. fill (grain is baked into its alpha, so it covers the caps too)
    over(canvas, tint(three_slice(T["Glass-Pill"], w, h), skin[fill_key]), x, y)

    # 4. rim
    over(canvas, tint(three_slice(T["Glass-Pill-Edge"], w, h), skin[edge_key]), x, y)


def draw_bar(canvas, x, y, w, h, pct, colors, skin, reverse=False):
    mask = T["Bar-Mask"].resize((w, h), Image.LANCZOS).split()[3]

    bg = tint(T["Bar-Flat"].resize((w, h)), (1, 1, 1, 0.14))
    bg.putalpha(Image.fromarray(
        (np.asarray(bg.split()[3]).astype(np.float32) * np.asarray(mask) / 255).astype(np.uint8)))
    over(canvas, bg, x, y)

    fw = max(1, int(w * pct))
    fill = T["Bar-Smooth"].resize((w, h), Image.LANCZOS)
    arr = np.asarray(fill).astype(np.float32) / 255.0
    # horizontal two-stop gradient, as SetGradient("HORIZONTAL", ...) gives
    t = np.linspace(0, 1, w, dtype=np.float32)[None, :, None]
    c1 = np.array(colors[0][:3], dtype=np.float32)[None, None, :]
    c2 = np.array(colors[1][:3], dtype=np.float32)[None, None, :]
    arr[:, :, :3] *= (c1 + (c2 - c1) * t)
    fill = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), "RGBA")
    fill.putalpha(Image.fromarray(
        (np.asarray(fill.split()[3]).astype(np.float32) * np.asarray(mask) / 255).astype(np.uint8)))

    if reverse:
        over(canvas, fill.crop((w - fw, 0, w, h)), x + w - fw, y)
    else:
        over(canvas, fill.crop((0, 0, fw, h)), x, y)


def draw_aura_pill(canvas, x, y, h, icon_size, icon_rgb, label, timetext, skin,
                   fill=None, edge=None, ring=None, width=None):
    """One aura pill: glass capsule, circular icon, name, fixed-width time.

    `width` forces a fixed column, which is what the in-capsule debuff tray uses:
    there the pills sit on a grid, so a long aura name clips instead of pushing
    its column wider than the other two.
    """
    d = ImageDraw.Draw(canvas)
    big = h >= 24
    pad, gap, tail, twidth = (4, 7, 8, 26) if big else (3, 5, 4, 18)
    fname = font("Medium" if big else "Light", 12 if big else 10)
    ftime = font("Light", 10)
    tw = d.textlength(timetext, font=ftime) if timetext else 0
    nw = d.textlength(label, font=fname)
    w = width or int(pad + icon_size + gap + nw + (gap + twidth if timetext else 0) + pad + tail)

    if width:
        avail = width - pad * 2 - icon_size - gap - tail - ((gap + twidth) if timetext else 0)
        while label and d.textlength(label + "...", font=fname) > avail:
            label = label[:-1]
        if label and d.textlength(label, font=fname) > avail:
            label += "..."

    draw_pill(canvas, x, y, w, h, skin, fill or "glass", edge or "edge")

    ix, iy = x + pad, y + (h - icon_size) // 2
    ic = Image.new("RGBA", (icon_size, icon_size), rgb255(icon_rgb, 1.0))
    ic.putalpha(T["Circle-Mask"].resize((icon_size, icon_size), Image.LANCZOS).split()[3])
    over(canvas, ic, ix, iy)
    over(canvas, tint(T["Ring"].resize((icon_size, icon_size), Image.LANCZOS),
                      (ring or skin["accent"])[:3] + (0.55,)), ix, iy)

    ty = y + (h - (12 if big else 10)) // 2 - 1
    d.text((ix + icon_size + gap, ty), label, font=fname, fill=rgb255(skin["text"]))
    if timetext:
        d.text((x + w - pad - tail - tw, ty + 1), timetext, font=ftime,
               fill=rgb255(skin["textDim"]))
    return w


def draw_orb(canvas, cx, cy, size, colors, ring_color, label, skin):
    disc = Image.new("RGBA", (size, size))
    arr = np.zeros((size, size, 4), dtype=np.float32)
    t = np.linspace(0, 1, size, dtype=np.float32)[:, None, None]
    c1 = np.array(colors[0][:3], dtype=np.float32)[None, None, :]
    c2 = np.array(colors[1][:3], dtype=np.float32)[None, None, :]
    arr[:, :, :3] = c1 + (c2 - c1) * t
    arr[:, :, 3] = 1.0
    disc = Image.fromarray((arr * 255).astype(np.uint8), "RGBA")
    disc.putalpha(T["Circle-Mask"].resize((size, size), Image.LANCZOS).split()[3])

    x, y = int(cx - size / 2), int(cy - size / 2)
    over(canvas, disc, x, y)
    over(canvas, tint(T["Ring"].resize((size, size), Image.LANCZOS), ring_color), x, y)

    d = ImageDraw.Draw(canvas)
    f = font("Bold", max(9, int(size * 0.26)))
    tw = d.textlength(label, font=f)
    # stand-in for the OUTLINE font flag
    d.text((cx - tw / 2, cy - size * 0.17), label, font=f, fill=(255, 255, 255, 255),
           stroke_width=1, stroke_fill=(0, 0, 0, 200))


def cooldown_sweep(size, fraction):
    """The conic-gradient sweep from the concept, clipped to the slot shape.

    Matches what Cooldown:SetSwipeTexture(Slot-Mask) does in game: the swipe is
    drawn through the slot's own alpha mask, so it never squares off the corners.
    """
    ss = 4
    wedge = Image.new("L", (size * ss, size * ss), 0)
    d = ImageDraw.Draw(wedge)
    start = -90
    end = start + 360 * fraction
    d.pieslice([-size * ss, -size * ss, size * ss * 2, size * ss * 2], start, end, fill=255)
    wedge = wedge.resize((size, size), Image.LANCZOS)

    slot = np.asarray(T["Slot-Mask"].resize((size, size), Image.LANCZOS).split()[3], dtype=np.float32)
    a = (np.asarray(wedge, dtype=np.float32) * slot / 255.0) * 0.72
    out = np.zeros((size, size, 4), dtype=np.uint8)
    out[:, :, 0], out[:, :, 1], out[:, :, 2] = 5, 3, 15
    out[:, :, 3] = np.clip(a, 0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def draw_slot(canvas, x, y, size, icon_rgb, skin, circle=False, glow=False,
              key=None, cd=None, count=None, desat=False, empty=False,
              edge_color=None):
    m = (T["Circle-Mask"] if circle else T["Slot-Mask"]).resize((size, size), Image.LANCZOS)

    if not empty:
        rgb = icon_rgb
        if desat:
            g = 0.30 * rgb[0] + 0.59 * rgb[1] + 0.11 * rgb[2]
            rgb = (g * 0.4, g * 0.4, g * 0.4)
        icon = Image.new("RGBA", (size, size), rgb255(rgb, 1.0))
        icon.putalpha(m.split()[3])
        over(canvas, icon, x, y)
        if not circle:
            over(canvas, tint(T["Slot-Shade"].resize((size, size), Image.LANCZOS), (0, 0, 0, 1)), x, y)
            over(canvas, T["Slot-Gloss"].resize((size, size), Image.LANCZOS), x, y, add=True)

    if cd:
        over(canvas, cooldown_sweep(size, cd), x, y)

    edge = T["Ring"] if circle else T["Slot-Edge"]
    ec = edge_color or skin["castEdge"]
    if empty:
        ec = (ec[0], ec[1], ec[2], (ec[3] if len(ec) > 3 else 1) * 0.4)
    over(canvas, tint(edge.resize((size, size), Image.LANCZOS), ec), x, y)

    if glow:
        g = tint(T["Slot-Glow"].resize((size * 2, size * 2), Image.LANCZOS), skin["cast"][0])
        over(canvas, g, x - size / 2, y - size / 2, add=True)

    d = ImageDraw.Draw(canvas)
    if key:
        f = font("SemiBold", max(8, int(size * 0.17)))
        tw = d.textlength(key, font=f)
        d.text((x + size - 4 - tw, y + 3), key, font=f, fill=(255, 255, 255, 235))
    if count:
        f = font("Bold", max(9, int(size * 0.19)))
        tw = d.textlength(str(count), font=f)
        d.text((x + size - 4 - tw, y + size - 4 - size * 0.22), str(count), font=f,
               fill=(255, 255, 255, 235))
    if cd:
        f = font("Bold", max(10, int(size * 0.24)))
        label = "12"
        tw = d.textlength(label, font=f)
        d.text((x + size / 2 - tw / 2, y + size / 2 - size * 0.15), label, font=f,
               fill=(255, 255, 255, 245))


# --------------------------------------------------------------------------
# the scene
# --------------------------------------------------------------------------

def backdrop(w, h, warm=True):
    """Stand-in for the game world: warm savanna tones with terrain-ish noise.

    Only needs to be busy and mid-tone: the point is to judge how the glass reads
    over something with detail behind it.
    """
    rng = np.random.default_rng(7)
    y = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    if warm:
        sky = np.array([0.42, 0.55, 0.72]); ground = np.array([0.55, 0.44, 0.26])
    else:
        sky = np.array([0.18, 0.20, 0.30]); ground = np.array([0.24, 0.19, 0.14])
    horizon = np.clip((y - 0.34) * 6, 0, 1)
    base = sky[None, None, :] * (1 - horizon[:, :, None]) + ground[None, None, :] * horizon[:, :, None]
    base = np.repeat(base, w, axis=1)

    for scale, amp in ((4, 0.10), (16, 0.06), (64, 0.03)):
        n = rng.normal(0, 1, (max(2, h // scale), max(2, w // scale))).astype(np.float32)
        n = np.asarray(Image.fromarray(((n - n.min()) / (np.ptp(n) + 1e-6) * 255).astype(np.uint8))
                       .resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0
        base += (n[:, :, None] - 0.5) * amp

    img = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8)).convert("RGBA")
    over(img, tint(T["Vignette"].resize((w, h), Image.LANCZOS), (0, 0, 0, 0.75)), 0, 0)
    return img


def scene(skin_name, width=1060):
    skin = SKINS[skin_name]
    H = 620
    canvas = backdrop(width, H, warm=(skin_name == "Daylight"))
    d = ImageDraw.Draw(canvas)

    d.text((28, 22), skin_name, font=font("SemiBold", 22), fill=rgb255(skin["text"]))
    d.text((28, 52), "buffs · capsules with debuff trays · cast bars · quest tracker · action dock",
           font=font("Light", 13), fill=rgb255(skin["textDim"]))

    CW, CH, GAP = 345, 64, 18
    cx = width // 2
    py = 288

    # Debuff tray geometry, mirroring Modules/UnitFrames.lua and the auras config.
    TRAY_INSET, TRAY_GAP, TRAY_PAD = 12, 2, 9
    DB_H, DB_ICON, DB_GAP, DB_PER = 18, 12, 4, 3
    TRAY_W = CW - 2 * TRAY_INSET
    DB_COL = (TRAY_W - (DB_PER - 1) * DB_GAP) // DB_PER

    def tray_rows(n):
        return (min(n, DB_PER * 2) + DB_PER - 1) // DB_PER

    def glass_height(n):
        if n <= 0:
            return CH
        rows = tray_rows(n)
        return CH + TRAY_GAP + rows * DB_H + (rows - 1) * DB_GAP + TRAY_PAD

    def draw_tray(x, n, debuffs):
        """Rows of fixed-width pills under the bars, centred in the capsule."""
        rows = tray_rows(n)
        for r in range(rows):
            chunk = debuffs[r * DB_PER:(r + 1) * DB_PER]
            roww = len(chunk) * DB_COL + (len(chunk) - 1) * DB_GAP
            bx = x + CW // 2 - roww // 2
            by = py + CH + TRAY_GAP + r * (DB_H + DB_GAP)
            for hue, lbl, tt in chunk:
                skin["_dbFill"] = (hue[0] * 0.35, hue[1] * 0.35, hue[2] * 0.35, 0.5)
                skin["_dbEdge"] = hue + (0.45,)
                draw_aura_pill(canvas, bx, by, DB_H, DB_ICON, hue, lbl, tt, skin,
                               fill="_dbFill", edge="_dbEdge", ring=hue,
                               width=DB_COL)
                bx += DB_COL + DB_GAP

    FROST = (0.55, 0.78, 1.00)
    CURSE = (0.70, 0.50, 1.00)
    POISON = (0.55, 0.85, 0.45)
    PHYS = (0.85, 0.45, 0.42)
    player_debuffs = [(PHYS, "Rend", "9s"), (CURSE, "Curse of Agony", "22s")]
    target_debuffs = [(FROST, "Chilled", "4s"), (POISON, "Serpent Sting", "12s"),
                      (PHYS, "Sunder Armor x3", "28s"), (CURSE, "Curse of Weakness", "1m")]

    # ---- buffs (concept: a row of pills above the cluster) ---------------
    # Two per row, stacking upward from the player capsule. A single wide row
    # drifts into the gap between the frames and reads as the target's.
    buffs = [((0.45, 0.72, 0.90), "Frost Armor", "30m"),
             ((0.62, 0.48, 0.85), "Arcane Intellect", "30m"),
             ((0.40, 0.66, 0.88), "Ice Barrier x3", "58s"),
             ((0.80, 0.45, 0.70), "Health", "60m")]
    dd = ImageDraw.Draw(canvas)
    f2 = font("Medium", 12)
    widths = [int(4 + 20 + 7 + dd.textlength(l, font=f2) + 7 + 26 + 4 + 8)
              for _, l, _ in buffs]

    px_left = cx - GAP // 2 - CW          # the player capsule's left edge
    pcx = px_left + CW // 2               # centred on the player capsule
    for r in range(0, len(buffs), 2):
        chunk, cw = buffs[r:r + 2], widths[r:r + 2]
        total = sum(cw) + 8 * (len(cw) - 1)
        bx = pcx - total // 2
        # row 0 nearest the frame, later rows stacked above it
        by = py - 36 - (r // 2 + 1) * 36
        for (hue, lbl, tt), w in zip(chunk, cw):
            draw_aura_pill(canvas, bx, by, 28, 20, hue, lbl, tt, skin)
            bx += w + 8

    # ---- cast bars -------------------------------------------------------
    # One per capsule, hung off the *glass* so a grown capsule pushes it down.
    def draw_cast(x, n, spell, elapsed, total, pct):
        cast_h = 44
        cast_x = x
        cast_y = py + glass_height(n) + 8
        draw_pill(canvas, cast_x, cast_y, CW, cast_h, skin, "glassStrong", "castEdge")
        draw_slot(canvas, cast_x + 7, cast_y + 7, 30, (0.42, 0.66, 0.85), skin, circle=True)
        d.text((cast_x + 49, cast_y + 14), spell, font=font("SemiBold", 13),
               fill=rgb255(skin["text"]))
        bar_x = cast_x + 49 + 110
        bar_w = CW - (bar_x - cast_x) - 78
        draw_bar(canvas, bar_x, cast_y + 19, bar_w, 7, pct, skin["cast"], skin)
        glow = tint(T["Bar-Glow"].resize((max(1, int(bar_w * pct)), 7), Image.LANCZOS),
                    skin["castGlow"])
        over(canvas, glow, bar_x, cast_y + 19, add=True)
        d.text((cast_x + CW - 74, cast_y + 15), "%s / %ss" % (elapsed, total),
               font=font("Medium", 11), fill=rgb255(skin["textDim"]))

    # ---- player ----------------------------------------------------------
    px = cx - GAP // 2 - CW
    draw_pill(canvas, px, py, CW, glass_height(len(player_debuffs)), skin)
    draw_orb(canvas, px + 10 + 23, py + CH / 2, 46, skin["classOrb"], skin["edge"], "15", skin)
    bx = px + 10 + 46 + 13
    d.text((bx, py + 11), "Palabras", font=font("SemiBold", 14), fill=rgb255(skin["text"]))
    nw = d.textlength("Palabras", font=font("SemiBold", 14))
    d.text((bx + nw + 8, py + 14), "Undead Mage", font=font("Light", 11), fill=rgb255(skin["textDim"]))
    draw_bar(canvas, bx, py + 32, 200, 7, 0.56, skin["health"], skin)
    draw_bar(canvas, bx, py + 43, 200, 5, 0.48, skin["power"], skin)
    rx = bx + 200 + 12 + 40      # block right + gap + readout width
    for txt, fnt, col, dy in (("208", font("SemiBold", 11), skin["health"][1], 20),
                              ("371", font("Regular", 10), skin["power"][1], 34)):
        tw = d.textlength(txt, font=fnt)
        d.text((rx - tw, py + dy), txt, font=fnt, fill=rgb255(col))

    # ---- target (mirrored) ----------------------------------------------
    tx = cx + GAP // 2
    draw_pill(canvas, tx, py, CW, glass_height(len(target_debuffs)), skin,
              "targetGlass", "targetEdge")
    draw_orb(canvas, tx + CW - 10 - 23, py + CH / 2, 46, skin["mobOrb"], skin["targetEdge"], "16", skin)
    tb_right = tx + CW - 10 - 46 - 13
    name = "Savannah Prowler"
    fw = font("SemiBold", 14)
    nw = d.textlength(name, font=fw)
    d.text((tb_right - nw, py + 11), name, font=fw, fill=rgb255(skin["targetText"]))
    sub = "Beast · Lv 16"
    sw = d.textlength(sub, font=font("Light", 11))
    d.text((tb_right - nw - 8 - sw, py + 14), sub, font=font("Light", 11), fill=rgb255(skin["textDim"]))
    draw_bar(canvas, tb_right - 200, py + 32, 200, 7, 0.64, skin["hostileBar"], skin, reverse=True)
    d.text((tx + 24, py + 20), "64%", font=font("SemiBold", 11), fill=rgb255(skin["targetText"]))

    # ---- debuff trays ----------------------------------------------------
    # School-tinted, on a fixed grid of three columns inside each capsule.
    draw_tray(px, len(player_debuffs), player_debuffs)
    draw_tray(tx, len(target_debuffs), target_debuffs)

    draw_cast(px, len(player_debuffs), "Frostbolt", "1.4", "2.5", 0.56)
    draw_cast(tx, len(target_debuffs), "Rejuvenation", "0.8", "1.5", 0.53)

    # ---- action dock -----------------------------------------------------
    # Concept 2a geometry exactly: 62px slots, 9px gaps, 10px padding.
    SLOT, GAP, PAD = 62, 9, 10
    N = 12
    dock_w = N * SLOT + (N - 1) * GAP + PAD * 2
    dock_h = SLOT + PAD * 2
    dx, dy = cx - dock_w // 2, py + 176

    dc = 14
    over(canvas, tint(nine_slice(T["Glass-Shadow"], dock_w + dc, dock_h + dc, dc * 2, 0.375),
                      skin["shadow"]), dx - dc / 2, dy - dc / 2)
    over(canvas, tint(nine_slice(T["Glass-Panel"], dock_w, dock_h, 14), skin["glass"]), dx, dy)
    over(canvas, tint(nine_slice(T["Glass-Panel-Edge"], dock_w, dock_h, 14), skin["edge"]), dx, dy)

    hues = [(0.42, 0.66, 0.85), (0.80, 0.42, 0.25), (0.86, 0.55, 0.22), (0.55, 0.45, 0.85),
            (0.40, 0.62, 0.80), (0.72, 0.55, 0.85), (0.50, 0.68, 0.60), (0.35, 0.58, 0.78),
            (0.78, 0.62, 0.30), (0.55, 0.72, 0.45), (0.0, 0.0, 0.0), (0.65, 0.40, 0.55)]
    for i in range(N):
        sx = dx + PAD + i * (SLOT + GAP)
        sy = dy + PAD
        draw_slot(canvas, sx, sy, SLOT, hues[i], skin,
                  key=str(i + 1) if i < 9 else ("-" if i == 9 else ("=" if i == 10 else "SM4")),
                  glow=(i == 0),                       # current action
                  cd=(0.62 if i == 2 else None),       # real cooldown, with countdown
                  desat=(i == 5),                      # unusable
                  count=(20 if i == 7 else None),      # stack
                  empty=(i == 10),                     # nothing on the slot
                  edge_color=(skin["hostileBar"][0] + (0.9,)) if i == 3 else
                             ((skin["health"][0] + (0.85,)) if i == 6 else None))

    d.text((dx, dy + dock_h + 10),
           "1 current · 3 on cooldown · 4 out of range · 6 unusable · 7 equipped · 11 empty",
           font=font("Light", 11), fill=rgb255(skin["textDim"]))

    # ---- xp hairline -----------------------------------------------------
    xp_h = 4
    xp_y = H - xp_h
    over(canvas, tint(T["Bar-Flat"].resize((width, xp_h)), (1, 1, 1, 0.10)), 0, xp_y)
    draw_bar(canvas, 0, xp_y, int(width * 0.86), xp_h, 1.0, skin["xp"], skin)
    glow2 = tint(T["Bar-Glow"].resize((int(width * 0.86), xp_h), Image.LANCZOS), skin["xp"][1])
    over(canvas, glow2, 0, xp_y, add=True)
    lbl = "86%  ·  Level 15"
    fl = font("Light", 10)
    d.text((width - 14 - d.textlength(lbl, font=fl), xp_y - 16), lbl, font=fl,
           fill=rgb255(skin["textDim"]))

    # ---- slot strip ------------------------------------------------------
    d.text((28, 96), "slot chrome · masked icon, inner shade, gloss, 1px rim, active glow",
           font=font("Light", 11), fill=rgb255(skin["textDim"]))
    hues = [(0.35, 0.55, 0.80), (0.80, 0.42, 0.25), (0.75, 0.65, 0.30),
            (0.45, 0.70, 0.55), (0.60, 0.40, 0.75)]
    for i, hue in enumerate(hues):
        draw_slot(canvas, 28 + i * 52, 118, 44, hue, skin, glow=(i == 0))

    # ---- quest tracker ---------------------------------------------------
    # Real geometry from Modules/QuestTracker.lua: pad 18/14, 22px heading,
    # 16px title, 14px objective lines, a 3px bar 5px under them, 10px between
    # quests. The panel sizes itself to whatever is tracked.
    PAD_X, PAD_TOP, PAD_BOT = 18, 14, 14
    HEADER_H, ROW_GAP, TITLE_H, LINE_H, BAR_H, BAR_GAP = 22, 10, 16, 14, 3, 5

    quests = [
        ("Chen's Empty Keg", ["Empty Keg: 0/1"], 0.0, False),
        ("Harpy Raiders", ["Witchwing Harpy slain: 10/10"], 1.0, True),
        ("Prowlers of the Barrens",
         ["Savannah Prowler slain: 3/8", "Savannah Huntress slain: 1/4"], 4 / 12, False),
        ("Lost in Battle", [], None, False),
    ]

    def row_h(lines, pct):
        h = TITLE_H + len(lines) * LINE_H
        return h + (BAR_GAP + BAR_H if pct is not None else 0)

    panel_w = 268
    body_h = sum(row_h(l, p) for _, l, p, _ in quests) + ROW_GAP * (len(quests) - 1)
    panel_h = PAD_TOP + HEADER_H + 6 + body_h + PAD_BOT
    panel_x, panel_y = width - panel_w - 32, 96

    pc = 12
    over(canvas, tint(nine_slice(T["Glass-Shadow"], panel_w + pc, panel_h + pc, pc * 2, 0.375),
                      skin["shadow"]), panel_x - pc / 2, panel_y - pc / 2)
    over(canvas, tint(nine_slice(T["Glass-Panel"], panel_w, panel_h, 12), skin["glass"]),
         panel_x, panel_y)
    over(canvas, tint(nine_slice(T["Glass-Panel-Edge"], panel_w, panel_h, 12), skin["edge"]),
         panel_x, panel_y)

    hx, hy = panel_x + PAD_X, panel_y + PAD_TOP
    inner_w = panel_w - PAD_X * 2
    # No letter-spacing in the WoW font engine, so the spaces are in the string.
    d.text((hx, hy + 4), "Q U E S T S", font=font("SemiBold", 11), fill=rgb255(skin["text"]))
    cnt = "4 / 20"
    fc = font("Light", 10)
    d.text((hx + inner_w - d.textlength(cnt, font=fc), hy + 6), cnt, font=fc,
           fill=rgb255(skin["textDim"]))

    yy = hy + HEADER_H + 6
    for title, lines, pct, done in quests:
        ft = font("Medium", 12)
        d.text((hx, yy), title, font=ft,
               fill=rgb255(skin["health"][0] if done else skin["text"]))
        oy = yy + TITLE_H
        for ln in lines:
            d.text((hx + 10, oy), ln, font=font("Light", 11),
                   fill=rgb255(skin["textDim"], 0.38 if done else None))
            oy += LINE_H
        if pct is not None:
            draw_bar(canvas, hx, oy + BAR_GAP, inner_w, BAR_H, max(0.02, pct),
                     skin["health"] if done else skin["xp"], skin)
            oy += BAR_GAP + BAR_H
        yy = oy + ROW_GAP

    return canvas


def main():
    load_all()
    a = scene("Midnight")
    b = scene("Daylight")
    out = Image.new("RGBA", (a.width, a.height + b.height + 8), (10, 10, 12, 255))
    out.paste(a, (0, 0))
    out.paste(b, (0, a.height + 8))
    path = os.path.join(ROOT, "Tools", "preview.png")
    out.convert("RGB").save(path)
    print("wrote", path, out.size)


if __name__ == "__main__":
    main()
