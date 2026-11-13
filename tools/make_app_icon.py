"""Draws the iMC Horizon app icon with code: a Minecraft dirt block with an iPhone Dynamic Island over it, the whole
idea in one picture ("Minecraft, on iOS"). The island carries a thin blue-to-red glow like a Live Activity, the two colours
of the launcher. The same mark is drawn in SwiftUI by BrandMark (platform/ios/App/Swift/Look.swift).
Three 1024x1024 variants for iOS (any / dark / tinted). No transparency and no baked rounded corners: iOS masks it.

    python3 tools/make_app_icon.py     # writes icon_light.png, icon_dark.png, icon_tinted.png here
    (copy them to platform/ios/Assets.xcassets/AppIcon.appiconset/icon-*.png)"""
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math
import random

S = 1024
SS = 2
W = S * SS

DIRT = [(134, 96, 67), (134, 96, 67), (134, 96, 67), (121, 85, 58), (121, 85, 58), (150, 108, 74),
        (110, 76, 52), (160, 118, 84), (96, 66, 44)]


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))


def vgradient(top, bottom, size=(W, W)):
    im = Image.new("RGBA", size)
    d = ImageDraw.Draw(im)
    for y in range(size[1]):
        c = lerp(top, bottom, y / max(1, size[1] - 1))
        d.line([(0, y), (size[0], y)], fill=tuple(int(v) for v in c) + (255,))
    return im


def glow(center, radius, colour, alpha):
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius], fill=colour + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.55))


def texture(seed, n=16):
    rnd = random.Random(seed)
    tex = [[rnd.choice(DIRT) for _ in range(n)] for _ in range(n)]
    # A few darker clumps, as in the game's dirt.
    for _ in range(n):
        x, y = rnd.randrange(n), rnd.randrange(n)
        tex[y][x] = (96, 66, 44)
    return tex


def draw_dirt_block(im, cx, cy, r, n=16, seed=26):
    """An isometric dirt block centred on (cx, cy), `r` from the centre to the top corner."""
    h = r * math.sqrt(3) / 2
    T = (cx, cy - r); TR = (cx + h, cy - r / 2); TL = (cx - h, cy - r / 2)
    C = (cx, cy); BL = (cx - h, cy + r / 2); BR = (cx + h, cy + r / 2); B = (cx, cy + r)
    tex = texture(seed, n)
    d = ImageDraw.Draw(im)

    def face(origin, u_end, v_end, shade):
        ux, uy = u_end[0] - origin[0], u_end[1] - origin[1]
        vx, vy = v_end[0] - origin[0], v_end[1] - origin[1]
        for j in range(n):
            for i in range(n):
                p = lambda a, b: (origin[0] + ux * a / n + vx * b / n, origin[1] + uy * a / n + vy * b / n)
                poly = [p(i, j), p(i + 1, j), p(i + 1, j + 1), p(i, j + 1)]
                # A hair of overlap so no seams show between cells.
                gx = sum(q[0] for q in poly) / 4; gy = sum(q[1] for q in poly) / 4
                poly = [(q[0] + (q[0] - gx) * 0.04, q[1] + (q[1] - gy) * 0.04) for q in poly]
                c = tex[j][i]
                d.polygon(poly, fill=tuple(min(255, int(v * shade)) for v in c) + (255,))

    face(T, TR, TL, 1.12)       # top
    face(TL, C, BL, 0.86)       # left
    face(C, TR, B, 0.64)        # right
    d.line([TL, C, TR], fill=(255, 235, 210, 120), width=max(3, int(W * 0.004)), joint="curve")
    d.line([C, B], fill=(0, 0, 0, 90), width=max(3, int(W * 0.004)))
    d.line([T, TR, BR, B, BL, TL, T], fill=(30, 18, 10, 150), width=max(3, int(W * 0.0045)), joint="curve")
    return (T, TR, TL, C, BL, BR, B)


def draw(mode):
    light = mode == "light"
    if light:
        top, bot = (222, 232, 255), (255, 228, 236)
        blue, red = (70, 120, 255), (255, 80, 100)
        ga = (120, 120)
    else:
        top, bot = (6, 10, 30), (30, 9, 22)
        blue, red = (50, 100, 255), (255, 60, 85)
        ga = (190, 190)

    im = vgradient(top, bot)
    im.alpha_composite(glow((int(W * 0.15), int(W * 0.08)), int(W * 0.55), blue, ga[0]))
    im.alpha_composite(glow((int(W * 0.88), int(W * 0.96)), int(W * 0.60), red, ga[1]))

    cx, cy, r = W // 2, int(W * 0.545), int(W * 0.325)

    # Shadow under the block.
    sh = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([W * 0.24, W * 0.80, W * 0.76, W * 0.90], fill=(0, 0, 0, 130 if not light else 80))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(W * 0.025)))

    draw_dirt_block(im, cx, cy, r)

    # ---- The Dynamic Island: a black pill across the top of the block.
    pw, ph = int(W * 0.56), int(W * 0.156)
    pcx, pcy = cx, int(cy - r * 0.80)
    box = [pcx - pw // 2, pcy - ph // 2, pcx + pw // 2, pcy + ph // 2]

    # A Live Activity glow around it, blue to red.
    glowl = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ring = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    grad = Image.new("RGBA", (W, W))
    gd = ImageDraw.Draw(grad)
    for x in range(box[0] - 20, box[2] + 20):
        t = min(1, max(0, (x - box[0]) / (box[2] - box[0])))
        gd.line([(x, 0), (x, W)], fill=tuple(int(v) for v in lerp(blue, red, t)) + (255,))
    pad = int(W * 0.010)
    mask = Image.new("L", (W, W), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad], radius=(ph + 2 * pad) // 2, fill=255)
    md.rounded_rectangle(box, radius=ph // 2, fill=0)
    ring.paste(grad, (0, 0), mask)
    glowl = ring.filter(ImageFilter.GaussianBlur(W * 0.014))
    im.alpha_composite(glowl)
    im.alpha_composite(ring)

    # Its shadow on the block, then the pill itself.
    psh = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(psh).rounded_rectangle([box[0], box[1] + int(W * 0.018), box[2], box[3] + int(W * 0.018)], radius=ph // 2, fill=(0, 0, 0, 150))
    im.alpha_composite(psh.filter(ImageFilter.GaussianBlur(W * 0.014)))
    d = ImageDraw.Draw(im, "RGBA")
    d.rounded_rectangle(box, radius=ph // 2, fill=(6, 6, 9, 255))
    # A faint highlight along the top edge.
    hl = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(hl).rounded_rectangle([box[0] + 4, box[1] + 3, box[2] - 4, box[1] + ph // 2], radius=ph // 2, fill=(255, 255, 255, 9))
    pm = Image.new("L", (W, W), 0)
    ImageDraw.Draw(pm).rounded_rectangle(box, radius=ph // 2, fill=255)
    hl.putalpha(ImageChops.multiply(hl.getchannel("A"), pm))
    im.alpha_composite(hl)

    d = ImageDraw.Draw(im, "RGBA")
    # The camera lens, right: dark ring, deep blue glass, a small reflection.
    lr = int(ph * 0.30)
    lx, ly = box[2] - int(ph * 0.52), pcy
    d.ellipse([lx - lr, ly - lr, lx + lr, ly + lr], fill=(26, 28, 38, 255))
    d.ellipse([lx - lr * 0.72, ly - lr * 0.72, lx + lr * 0.72, ly + lr * 0.72], fill=(12, 16, 44, 255))
    d.ellipse([lx - lr * 0.36, ly - lr * 0.46, lx - lr * 0.06, ly - lr * 0.16], fill=(120, 140, 255, 200))
    # The sensor dot, left of the lens.
    sr = int(ph * 0.075)
    sx = lx - int(ph * 0.62)
    d.ellipse([sx - sr, ly - sr, sx + sr, ly + sr], fill=(22, 24, 32, 255))
    # A tiny dirt block as the Live Activity icon, left: the app inside its own island.
    mini = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    draw_dirt_block(mini, box[0] + int(ph * 0.62), pcy, int(ph * 0.34), n=4, seed=7)
    im.alpha_composite(mini)

    out = im.convert("RGB").resize((S, S), Image.LANCZOS)
    if mode == "tinted":
        g = out.convert("L").point(lambda v: min(255, int(v * 1.15)))
        out = Image.merge("RGB", (g, g, g))
    return out


if __name__ == "__main__":
    for m in ("light", "dark", "tinted"):
        draw(m).save(f"icon_{m}.png")
        print("wrote", f"icon_{m}.png")
