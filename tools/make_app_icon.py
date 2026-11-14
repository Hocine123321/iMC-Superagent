"""Draws the iMC Horizon app icons with code: a Minecraft dirt block over a horizon (a sky with a soft glow behind the block,
stepped ground, a thin horizon line), in the two colours of a launcher theme. One icon per colour theme (the presets of
Settings > Look); the launcher switches to the matching one when the theme changes, or the person picks one by hand
(platform/ios/App/Swift/AppIconTheme.swift). The block is drawn exactly as the in-app mark is (BrandMark in Look.swift: six
cells to a face, the same browns chosen by the same formula), so the icon and the mark are one picture.
Each icon is three 1024x1024 files for iOS (any / dark / tinted), no transparency, no baked rounded corners: iOS masks it.

    python3 tools/make_app_icon.py --install   # writes every AppIcon*.appiconset into platform/ios/Assets.xcassets
    python3 tools/make_app_icon.py --check     # the presets, the asset sets and project.yml agree (CI runs this)
    python3 tools/make_app_icon.py             # writes icon_<theme>_<variant>.png here, for a look

PRESETS below is the same list as ThemePreset.all in platform/ios/App/Swift/Palette.swift; --check compares them."""
import json
import math
import os
import random
import re
import sys

S = 1024
SS = 2
W = S * SS

# id, first colour, second colour (RRGGBB), as in Palette.swift. The first is the primary icon ("AppIcon").
PRESETS = [
    ("blue-red", 0x5B9BFF, 0xFF5A66),
    ("red-blue", 0xFF5A66, 0x5B9BFF),
    ("ocean", 0x38BDF8, 0x2DD4BF),
    ("sunset", 0xFF8A3D, 0xFF4D8D),
    ("forest", 0x4ADE80, 0xE3C541),
    ("violet", 0xA78BFA, 0x60A5FA),
    ("ember", 0xFF5A4D, 0xFFA23D),
    ("mint", 0x2DD4BF, 0x818CF8),
    ("slate", 0x94A3B8, 0x64748B),
]

DIRT = [(134, 96, 67), (134, 96, 67), (134, 96, 67), (121, 85, 58), (121, 85, 58), (150, 108, 74),
        (110, 76, 52), (160, 118, 84), (96, 66, 44)]

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "platform", "ios", "Assets.xcassets")
SWIFT_PALETTE = os.path.join(HERE, "..", "platform", "ios", "App", "Swift", "Palette.swift")
PROJECT_YML = os.path.join(HERE, "..", "platform", "ios", "project.yml")


def set_name(preset_id):
    return "AppIcon" if preset_id == PRESETS[0][0] else "AppIcon-" + preset_id


def rgb(v):
    return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(len(a)))


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def cell_colour(face, i, j):
    """The brown of one cell, by the same formula BrandMark uses in SwiftUI (Look.swift)."""
    h = abs((face * 7919) ^ (i * 73856093) ^ (j * 19349663))
    return DIRT[h % len(DIRT)]


def draw_dirt_block(im, cx, cy, r, n=6):
    """An isometric dirt block centred on (cx, cy), `r` from the centre to the top corner, n cells to a face."""
    h = r * math.sqrt(3) / 2
    T = (cx, cy - r); TR = (cx + h, cy - r / 2); TL = (cx - h, cy - r / 2)
    C = (cx, cy); BL = (cx - h, cy + r / 2); B = (cx, cy + r)
    d = ImageDraw.Draw(im)

    def face(face_id, origin, u_end, v_end, shade):
        ux, uy = u_end[0] - origin[0], u_end[1] - origin[1]
        vx, vy = v_end[0] - origin[0], v_end[1] - origin[1]
        for j in range(n):
            for i in range(n):
                p = lambda a, b: (origin[0] + ux * a / n + vx * b / n, origin[1] + uy * a / n + vy * b / n)
                colour = tuple(min(255, int(v * shade)) for v in cell_colour(face_id, i, j)) + (255,)
                poly = [p(i, j), p(i + 1, j), p(i + 1, j + 1), p(i, j + 1)]
                d.polygon(poly, fill=colour)
                d.line(poly + [poly[0]], fill=colour, width=2)      # no seams between cells (the mark strokes its cells too)

    face(0, T, TR, TL, 1.12)    # top
    face(1, TL, C, BL, 0.86)    # left
    face(2, C, TR, B, 0.64)     # right
    # The one highlight the mark has: a light rim along the two top edges that meet at the front corner.
    d.line([TL, C, TR], fill=(255, 235, 209, 128), width=max(3, int(r * 0.026)), joint="curve")


def draw(variant, first, second):
    global Image, ImageDraw, ImageFilter
    from PIL import Image, ImageDraw, ImageFilter          # only drawing needs Pillow; --check runs without it
    c1, c2 = rgb(first), rgb(second)
    if variant == "light":
        sky_top, sky_bot = mix((255, 255, 255), c1, 0.45), mix((255, 246, 232), c2, 0.35)
        hill1, hill2 = tuple(int(v * 0.66) for v in c2), tuple(int(v * 0.50) for v in c2)
        glow = mix((255, 255, 255), c1, 0.30)
        line = mix((255, 255, 255), c1, 0.20)
    else:
        sky_top, sky_bot = (8, 12, 34), mix((14, 20, 46), c1, 0.30)
        hill1, hill2 = mix((10, 16, 30), c2, 0.24), mix((8, 12, 24), c2, 0.13)
        glow = c1
        line = c1

    # The sky.
    im = Image.new("RGB", (W, W))
    d = ImageDraw.Draw(im)
    for y in range(W):
        d.line([(0, y), (W, y)], fill=mix(sky_top, sky_bot, y / (W - 1)))
    im = im.convert("RGBA")

    # A soft glow behind the block, like a sun or a moon.
    gl = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gl)
    gcx, gcy = W // 2, int(W * 0.46)
    for i in range(14):
        rad = int(W * (0.40 - i * 0.022))
        gd.ellipse([gcx - rad, gcy - rad, gcx + rad, gcy + rad], fill=glow + (int(10 + i * 7),))
    im = Image.alpha_composite(im, gl.filter(ImageFilter.GaussianBlur(W * 0.02)))
    d = ImageDraw.Draw(im, "RGBA")

    # Stepped ground made of whole blocks, in two layers, and a thin horizon line.
    horizon_y = int(W * 0.66)
    cell = W // 16

    def hills(base, colour, seed, amp):
        v = seed
        for i in range(18):
            v = (v * 37 + 11) % 7
            hy = base - (v % amp) * cell // 2
            d.rectangle([i * cell - cell // 2, hy, (i + 1) * cell - cell // 2, W], fill=colour)

    hills(horizon_y - cell // 2, hill1, 3, 4)
    hills(horizon_y + cell, hill2, 5, 3)
    d.rectangle([0, horizon_y + cell // 3, W, horizon_y + cell // 3 + int(W * 0.006)], fill=line + (150,))

    # The block's soft shadow, then the block.
    sh = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([W * 0.28, W * 0.745, W * 0.72, W * 0.83], fill=(0, 0, 0, 120 if variant != "light" else 80))
    im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(W * 0.02)))
    draw_dirt_block(im, W // 2, int(W * 0.49), int(W * 0.30))

    out = im.convert("RGB").resize((S, S), Image.LANCZOS)
    if variant == "tinted":
        g = out.convert("L").point(lambda v: min(255, int(v * 1.15)))
        out = Image.merge("RGB", (g, g, g))
    return out


CONTENTS = {
    "images": [
        {"filename": "icon-light.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        {"appearances": [{"appearance": "luminosity", "value": "dark"}], "filename": "icon-dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
        {"appearances": [{"appearance": "luminosity", "value": "tinted"}], "filename": "icon-tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"},
    ],
    "info": {"author": "xcode", "version": 1},
}


def install():
    for pid, first, second in PRESETS:
        folder = os.path.join(ASSETS, set_name(pid) + ".appiconset")
        os.makedirs(folder, exist_ok=True)
        for variant in ("light", "dark", "tinted"):
            draw(variant, first, second).save(os.path.join(folder, f"icon-{variant}.png"), optimize=True)
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump(CONTENTS, f, indent=2)
            f.write("\n")
        print("wrote", folder)


def check():
    problems = []
    swift = open(SWIFT_PALETTE, encoding="utf-8").read()
    found = re.findall(r'ThemePreset\(id: "([a-z-]+)", name: "[^"]+", first: 0x([0-9A-Fa-f]{6}), second: 0x([0-9A-Fa-f]{6})', swift)
    mine = [(p, f"{a:06X}", f"{b:06X}") for p, a, b in PRESETS]
    theirs = [(p, a.upper(), b.upper()) for p, a, b in found]
    if mine != theirs:
        problems.append(f"PRESETS here and ThemePreset.all in Palette.swift differ:\n  here:  {mine}\n  swift: {theirs}")
    for pid, _, _ in PRESETS:
        folder = os.path.join(ASSETS, set_name(pid) + ".appiconset")
        for name in ("Contents.json", "icon-light.png", "icon-dark.png", "icon-tinted.png"):
            if not os.path.exists(os.path.join(folder, name)):
                problems.append(f"missing {set_name(pid)}.appiconset/{name}")
    yml = open(PROJECT_YML, encoding="utf-8").read()
    m = re.search(r'ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES:\s*"([^"]*)"', yml)
    listed = m.group(1).split() if m else []
    want = [set_name(p) for p, _, _ in PRESETS[1:]]
    if sorted(listed) != sorted(want):
        problems.append(f"project.yml ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES is {listed}, expected {want}")
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print(f"app icons agree: {len(PRESETS)} themes, {len(want)} alternate icons")


if __name__ == "__main__":
    if "--install" in sys.argv:
        install()
    elif "--check" in sys.argv:
        check()
    else:
        for pid, a, b in PRESETS:
            for v in ("light", "dark", "tinted"):
                draw(v, a, b).save(f"icon_{pid}_{v}.png")
        print("wrote the icons here")
