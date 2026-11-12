"""Draws the iMC Horizon app icon with code: a glass-like isometric block, blue on one side and red on the other,
over a navy-to-wine ground with a blue-to-red horizon line. It is the same mark the launcher draws in SwiftUI
(BrandMark in platform/ios/App/Swift/Look.swift). Three 1024x1024 variants for iOS (any / dark / tinted).
No transparency, no baked rounded corners: iOS applies its own mask.

    python3 tools/make_app_icon.py     # writes icon_light.png, icon_dark.png, icon_tinted.png here
    (copy them to platform/ios/Assets.xcassets/AppIcon.appiconset/icon-*.png)"""
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math

S = 1024
SS = 2                  # supersample for clean edges
W = S * SS


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
    """A soft round glow, as an RGBA layer."""
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius], fill=colour + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.55))


def face(base, poly, top_colour, bottom_colour):
    """Fills a polygon with a vertical gradient."""
    ys = [p[1] for p in poly]
    y0, y1 = int(min(ys)), int(max(ys)) + 1
    grad = vgradient(top_colour, bottom_colour, (W, y1 - y0))
    full = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    full.paste(grad, (0, y0))
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    base.alpha_composite(Image.composite(full, Image.new("RGBA", (W, W), (0, 0, 0, 0)), mask))
    return mask


def lerp_pt(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def draw(mode):
    light = mode == "light"
    if light:
        ground_top, ground_bot = (226, 234, 255), (255, 232, 238)
        blue_glow, red_glow = (70, 120, 255), (255, 80, 100)
        glow_a = (120, 120)
    else:
        ground_top, ground_bot = (6, 10, 30), (30, 9, 22)
        blue_glow, red_glow = (50, 100, 255), (255, 60, 85)
        glow_a = (190, 190)

    im = vgradient(ground_top, ground_bot)
    im.alpha_composite(glow((int(W * 0.18), int(W * 0.10)), int(W * 0.55), blue_glow, glow_a[0]))
    im.alpha_composite(glow((int(W * 0.86), int(W * 0.94)), int(W * 0.60), red_glow, glow_a[1]))

    # A faint block grid, fading out downwards.
    grid = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grid)
    cell = W // 14
    for r in range(15):
        for c in range(15):
            h = (r * 73856093) ^ (c * 19349663)
            v = (abs(h) % 1000) / 1000
            if v < 0.62:
                continue
            col = blue_glow if (h & 4) == 0 else red_glow
            gd.rounded_rectangle([c * cell + 6, r * cell + 6, (c + 1) * cell - 6, (r + 1) * cell - 6], radius=18,
                                 fill=col + (int(34 + (v - 0.62) * 150),))
    fade = vgradient((255, 255, 255), (0, 0, 0)).convert("L")
    grid.putalpha(ImageChops.multiply(grid.getchannel("A"), fade))
    im.alpha_composite(grid)

    # The horizon: a thin line, blue on the left to red on the right, with a glow.
    hy = int(W * 0.70)
    line = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ld = ImageDraw.Draw(line)
    for x in range(W):
        c = lerp(blue_glow, red_glow, x / (W - 1))
        ld.line([(x, hy), (x, hy + int(W * 0.006))], fill=tuple(int(v) for v in c) + (230,))
    im.alpha_composite(line.filter(ImageFilter.GaussianBlur(W * 0.012)))
    im.alpha_composite(line)

    # Shadow under the block.
    sh = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([W * 0.27, W * 0.745, W * 0.73, W * 0.84], fill=(0, 0, 0, 120 if not light else 70))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(W * 0.022)))

    # The block.
    cx, cy, r = W // 2, int(W * 0.485), int(W * 0.30)
    h = r * math.sqrt(3) / 2
    T = (cx, cy - r); TR = (cx + h, cy - r / 2); BR = (cx + h, cy + r / 2)
    B = (cx, cy + r); BL = (cx - h, cy + r / 2); TL = (cx - h, cy - r / 2); C = (cx, cy)

    left_mask = face(im, [TL, C, B, BL], (78, 132, 255), (22, 48, 168))
    right_mask = face(im, [C, TR, BR, B], (255, 96, 110), (160, 16, 48))
    top_mask = face(im, [T, TR, C, TL], (255, 255, 255), (196, 214, 255))

    # Glass: a soft diagonal gloss on each face, a lit rim along the top edges, a thin line between faces.
    gloss = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gloss)
    # One broad, soft sheen across the top face and a lighter one down each side; blurred so no edge shows.
    gd.polygon([lerp_pt(TL, T, 0.15), lerp_pt(TL, T, 0.75), lerp_pt(C, TR, 0.35), lerp_pt(TL, C, 0.45)], fill=(255, 255, 255, 60))
    gd.polygon([TL, lerp_pt(TL, C, 0.5), lerp_pt(BL, B, 0.35), BL], fill=(255, 255, 255, 26))
    gd.polygon([lerp_pt(C, TR, 0.5), TR, BR, lerp_pt(B, BR, 0.35)], fill=(255, 255, 255, 22))
    gloss = gloss.filter(ImageFilter.GaussianBlur(W * 0.03))
    all_mask = ImageChops.lighter(ImageChops.lighter(left_mask, right_mask), top_mask)
    gloss.putalpha(ImageChops.multiply(gloss.getchannel("A"), all_mask))
    im.alpha_composite(gloss)

    # A 2 x 2 grid of pixels on each side face, like a block texture.
    tex = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    td = ImageDraw.Draw(tex)
    for (a, b, c_, d_) in ((TL, C, B, BL), (C, TR, BR, B)):
        for t in (0.5,):
            td.line([lerp_pt(a, b, t), lerp_pt(d_, c_, t)], fill=(255, 255, 255, 46), width=max(2, int(W * 0.003)))
            td.line([lerp_pt(a, d_, t), lerp_pt(b, c_, t)], fill=(255, 255, 255, 46), width=max(2, int(W * 0.003)))
    tex.putalpha(ImageChops.multiply(tex.getchannel("A"), ImageChops.lighter(left_mask, right_mask)))
    im.alpha_composite(tex)

    d = ImageDraw.Draw(im, "RGBA")
    d.line([TL, C, TR], fill=(255, 255, 255, 150), width=max(3, int(W * 0.0045)), joint="curve")
    d.line([C, B], fill=(255, 255, 255, 110), width=max(3, int(W * 0.004)))
    d.line([T, TR, BR, B, BL, TL, T], fill=(255, 255, 255, 80), width=max(2, int(W * 0.003)), joint="curve")
    d.line([TL, T, TR], fill=(255, 255, 255, 230), width=max(3, int(W * 0.0045)), joint="curve")

    out = im.convert("RGB").resize((S, S), Image.LANCZOS)
    if mode == "tinted":
        # A greyscale design, iOS colours it: keep the contrast between the three faces.
        g = out.convert("L")
        g = g.point(lambda v: min(255, int(v * 1.12)))
        out = Image.merge("RGB", (g, g, g))
    return out


if __name__ == "__main__":
    for m in ("light", "dark", "tinted"):
        draw(m).save(f"icon_{m}.png")
        print("wrote", f"icon_{m}.png")
