"""Draws the iMC Horizon app icon with code: an isometric grass block over a horizon.
Three 1024x1024 variants for iOS (any / dark / tinted). No transparency, no baked rounded corners:
iOS applies its own mask."""
from PIL import Image, ImageDraw, ImageFilter
import math

S = 1024
SS = 2  # supersample for clean edges
W = S * SS

def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def gradient(top, bottom, size):
    im = Image.new("RGB", (size, size))
    d = ImageDraw.Draw(im)
    for y in range(size):
        d.line([(0, y), (size, y)], fill=lerp(top, bottom, y / (size - 1)))
    return im

def iso_block(d, cx, cy, r, top, left, right, edge=None, grid=None):
    """Isometric cube centred on (cx, cy); r = distance from centre to top vertex."""
    h = r * math.sqrt(3) / 2
    T = (cx, cy - r); TR = (cx + h, cy - r / 2); BR = (cx + h, cy + r / 2)
    B = (cx, cy + r); BL = (cx - h, cy + r / 2); TL = (cx - h, cy - r / 2)
    C = (cx, cy)
    d.polygon([T, TR, C, TL], fill=top)
    d.polygon([TL, C, B, BL], fill=left)
    d.polygon([C, TR, BR, B], fill=right)
    if edge:
        for a, b in ((T, TR), (TR, BR), (BR, B), (B, BL), (BL, TL), (TL, T), (TL, C), (TR, C), (C, B)):
            d.line([a, b], fill=edge, width=max(2, int(W * 0.004)))
    return dict(T=T, TR=TR, BR=BR, B=B, BL=BL, TL=TL, C=C)

def draw(mode):
    if mode == "light":
        sky_top, sky_bot = (255, 176, 96), (255, 226, 170)
        hill1, hill2 = (86, 150, 74), (58, 118, 62)
        top, left, right = (112, 190, 84), (140, 96, 62), (108, 72, 46)
        dirt_dots, edge, glow = (92, 62, 40), (40, 52, 36), (255, 244, 214)
        sun = (255, 248, 220)
    elif mode == "dark":
        sky_top, sky_bot = (8, 12, 34), (30, 52, 92)
        hill1, hill2 = (22, 52, 56), (14, 36, 44)
        top, left, right = (70, 170, 120), (92, 70, 56), (66, 50, 42)
        dirt_dots, edge, glow = (52, 40, 34), (6, 12, 20), (60, 200, 190)
        sun = (170, 215, 235)
    else:  # tinted: a greyscale design, iOS colours it
        sky_top, sky_bot = (30, 30, 30), (110, 110, 110)
        hill1, hill2 = (70, 70, 70), (45, 45, 45)
        top, left, right = (235, 235, 235), (160, 160, 160), (120, 120, 120)
        dirt_dots, edge, glow = (100, 100, 100), (20, 20, 20), (255, 255, 255)
        sun = (255, 255, 255)

    im = gradient(sky_top, sky_bot, W)
    d = ImageDraw.Draw(im, "RGBA")

    horizon_y = int(W * 0.66)
    # sun / moon glow behind the block
    gl = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gl)
    gcx, gcy = W // 2, int(W * 0.46)
    for i in range(14):
        rad = int(W * (0.40 - i * 0.022))
        a = int(10 + i * 7)
        gd.ellipse([gcx - rad, gcy - rad, gcx + rad, gcy + rad], fill=glow + (a if mode != "tinted" else a // 2,))
    gl = gl.filter(ImageFilter.GaussianBlur(W * 0.02))
    im = Image.alpha_composite(im.convert("RGBA"), gl)
    d = ImageDraw.Draw(im, "RGBA")
    # blocky hills (stepped silhouettes made of whole blocks)
    cell = W // 16
    def hills(base, colour, seed, amp):
        heights = []
        v = seed
        for i in range(18):
            v = (v * 37 + 11) % 7
            heights.append(base - (v % amp) * cell // 2)
        for i, hy in enumerate(heights):
            d.rectangle([i * cell - cell // 2, hy, (i + 1) * cell - cell // 2, W], fill=colour)
    hills(horizon_y - cell // 2, hill1, 3, 4)
    hills(horizon_y + cell, hill2, 5, 3)
    # the horizon line
    d.rectangle([0, horizon_y + cell // 3, W, horizon_y + cell // 3 + int(W * 0.006)], fill=glow + (150,))

    # soft shadow under the block
    sh = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([W * 0.30, W * 0.745, W * 0.70, W * 0.82], fill=(0, 0, 0, 110))
    sh = sh.filter(ImageFilter.GaussianBlur(W * 0.018))
    im = Image.alpha_composite(im, sh)
    d = ImageDraw.Draw(im, "RGBA")

    # the block, with a grass overhang and a pixel pattern on the dirt faces
    cx, cy, r = W // 2, int(W * 0.50), int(W * 0.285)
    p = iso_block(d, cx, cy, r, top, left, right, edge=edge)
    # grass fringe running down the two side faces
    fringe = 0.17
    def lerp_pt(a, b, t): return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
    for side_top_a, side_top_b, down in ((p["TL"], p["C"], (0, 1)), (p["C"], p["TR"], (0, 1))):
        n = 6
        for i in range(n):
            t0, t1 = i / n, (i + 1) / n
            a = lerp_pt(side_top_a, side_top_b, t0); b = lerp_pt(side_top_a, side_top_b, t1)
            depth = r * (fringe if (i % 2 == 0) else fringe * 0.55)
            d.polygon([a, b, (b[0], b[1] + depth), (a[0], a[1] + depth)], fill=top)
    # dirt specks on the side faces
    import random
    rnd = random.Random(7)
    for face in ((p["TL"], p["C"], p["B"], p["BL"]), (p["C"], p["TR"], p["BR"], p["B"])):
        for _ in range(16):
            u, v = rnd.random() * 0.9 + 0.05, rnd.random() * 0.6 + 0.35
            top_pt = lerp_pt(face[0], face[1], u); bot_pt = lerp_pt(face[3], face[2], u)
            x, y = lerp_pt(top_pt, bot_pt, v)
            s = W * 0.012
            d.rectangle([x - s, y - s, x + s, y + s], fill=dirt_dots + (200,))
    # light speckle on the grass top
    for _ in range(14):
        u, v = rnd.random(), rnd.random()
        a = lerp_pt(p["TL"], p["T"], u); b = lerp_pt(p["C"], p["TR"], u)
        x, y = lerp_pt(a, b, v)
        s = W * 0.010
        lighter = tuple(min(255, c + 28) for c in top)
        d.rectangle([x - s, y - s, x + s, y + s], fill=lighter + (160,))
    # redraw the outline on top of the fringe
    iso_outline = [p["T"], p["TR"], p["BR"], p["B"], p["BL"], p["TL"], p["T"]]
    d.line(iso_outline, fill=edge + (255,), width=max(3, int(W * 0.005)), joint="curve")

    # a rim highlight on the block's top edge
    d.line([p["TL"], p["T"], p["TR"]], fill=glow + (200,), width=max(2, int(W * 0.004)))

    out = im.convert("RGB").resize((S, S), Image.LANCZOS)
    return out

if __name__ == "__main__":
    for m in ("light", "dark", "tinted"):
        draw(m).save(f"icon_{m}.png")
        print("wrote", f"icon_{m}.png")
