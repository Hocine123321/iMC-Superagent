"""Draws the iMC Horizon app icons with code: a Minecraft dirt block on a navy-to-wine ground, lit in the two colours of a
launcher theme. One icon per colour theme (the presets of Settings > Look); the launcher switches to the matching one when
the theme changes (platform/ios/App/Swift/AppIconTheme.swift). The in-app mark is the same picture (BrandMark in Look.swift).
Each icon is three 1024x1024 files for iOS (any / dark / tinted), no transparency, no baked rounded corners: iOS masks it.

    python3 tools/make_app_icon.py --install   # writes every AppIcon*.appiconset into platform/ios/Assets.xcassets
    python3 tools/make_app_icon.py --check     # the presets, the asset sets and project.yml agree (CI runs this)
    python3 tools/make_app_icon.py             # writes icon_<theme>_<variant>.png here, for a look

PRESETS below is the same list as ThemePreset.all in platform/ios/App/Swift/Palette.swift; --check compares them."""
from PIL import Image, ImageDraw, ImageFilter
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


def vgradient(top, bottom):
    im = Image.new("RGBA", (W, W))
    d = ImageDraw.Draw(im)
    for y in range(W):
        c = lerp(top, bottom, y / (W - 1))
        d.line([(0, y), (W, y)], fill=tuple(int(v) for v in c) + (255,))
    return im


def glow(center, radius, colour, alpha):
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius], fill=colour + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.55))


def texture(seed, n=16):
    rnd = random.Random(seed)
    tex = [[rnd.choice(DIRT) for _ in range(n)] for _ in range(n)]
    for _ in range(n):                      # a few darker clumps, as in the game's dirt
        tex[rnd.randrange(n)][rnd.randrange(n)] = (96, 66, 44)
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
                gx = sum(q[0] for q in poly) / 4; gy = sum(q[1] for q in poly) / 4
                poly = [(q[0] + (q[0] - gx) * 0.04, q[1] + (q[1] - gy) * 0.04) for q in poly]   # no seams between cells
                d.polygon(poly, fill=tuple(min(255, int(v * shade)) for v in tex[j][i]) + (255,))

    face(T, TR, TL, 1.12)       # top
    face(TL, C, BL, 0.86)       # left
    face(C, TR, B, 0.64)        # right
    d.line([TL, C, TR], fill=(255, 235, 210, 120), width=max(3, int(W * 0.004)), joint="curve")
    d.line([C, B], fill=(0, 0, 0, 90), width=max(3, int(W * 0.004)))
    d.line([T, TR, BR, B, BL, TL, T], fill=(30, 18, 10, 150), width=max(3, int(W * 0.0045)), joint="curve")


def draw(variant, first, second):
    light = variant == "light"
    top, bot = ((222, 232, 255), (255, 228, 236)) if light else ((6, 10, 30), (30, 9, 22))
    c1, c2 = rgb(first), rgb(second)
    a1, a2 = (125, 125) if light else (190, 190)

    im = vgradient(top, bot)
    im.alpha_composite(glow((int(W * 0.15), int(W * 0.08)), int(W * 0.55), c1, a1))
    im.alpha_composite(glow((int(W * 0.88), int(W * 0.96)), int(W * 0.60), c2, a2))

    # A faint block grid behind the block, tinted in the two colours, fading downwards.
    grid = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grid)
    cell = W // 14
    for r_ in range(15):
        for c_ in range(15):
            hsh = (r_ * 73856093) ^ (c_ * 19349663)
            v = (abs(hsh) % 1000) / 1000
            if v < 0.64:
                continue
            col = c1 if (hsh & 4) == 0 else c2
            gd.rounded_rectangle([c_ * cell + 6, r_ * cell + 6, (c_ + 1) * cell - 6, (r_ + 1) * cell - 6], radius=18,
                                 fill=col + (int(30 + (v - 0.64) * 140),))
    fade = Image.new("L", (W, W))
    fd = ImageDraw.Draw(fade)
    for y in range(W):
        fd.line([(0, y), (W, y)], fill=int(255 * (1 - y / W)))
    im.alpha_composite(Image.composite(grid, Image.new("RGBA", (W, W), (0, 0, 0, 0)), fade))

    cx, cy, r = W // 2, int(W * 0.50), int(W * 0.37)
    sh = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([W * 0.22, W * 0.80, W * 0.78, W * 0.91], fill=(0, 0, 0, 135 if not light else 80))
    im.alpha_composite(sh.filter(ImageFilter.GaussianBlur(W * 0.026)))
    draw_dirt_block(im, cx, cy, r)

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
