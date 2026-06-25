#!/usr/bin/env python3
"""Generate the Nudge app icon: a 'ping' — a dot with ripples radiating out (a
nudge) — in the app's warm brown theme. Cream glyph on a brown gradient; the
outer ring fades so it reads as motion. Renders at 3x supersample, outputs
light / dark / tinted 1024px variants into the AppIcon asset."""

from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(__file__),
                   "ios/Nudge/Nudge/Assets.xcassets/AppIcon.appiconset")
S = 1024
SS = 3
BIG = S * SS

def gradient(c0, c1, size):
    n = 64
    small = Image.new("RGB", (n, n)); px = small.load()
    for y in range(n):
        for x in range(n):
            t = (x + y) / (2 * (n - 1))
            px[x, y] = (int(c0[0]+(c1[0]-c0[0])*t),
                        int(c0[1]+(c1[1]-c0[1])*t),
                        int(c0[2]+(c1[2]-c0[2])*t))
    return small.resize((size, size), Image.BICUBIC)

def render(c0, c1, glyph=(246, 237, 219)):
    base = gradient(c0, c1, BIG).convert("RGBA")
    ov = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    cx = cy = BIG * 0.5

    def ring(r, w, a):
        d.ellipse([cx - r, cy - r, cx + r, cy + r],
                  outline=(glyph[0], glyph[1], glyph[2], a), width=int(w))

    # centre dot, then two ripples — the outer one fades (nudge radiating out)
    dot = BIG * 0.072
    d.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=(glyph[0], glyph[1], glyph[2], 255))
    ring(BIG * 0.165, BIG * 0.030, 255)
    ring(BIG * 0.270, BIG * 0.026, 150)

    base = Image.alpha_composite(base, ov)
    return base.resize((S, S), Image.LANCZOS).convert("RGB")

render((124, 84, 48), (74, 48, 24)).save(os.path.join(OUT, "icon-1024.png"))            # light
render((58, 38, 22),  (32, 20, 10)).save(os.path.join(OUT, "icon-dark-1024.png"))        # dark
render((26, 25, 27),  (44, 42, 48), glyph=(226, 223, 220)).save(
    os.path.join(OUT, "icon-tinted-1024.png"))                                           # tinted
print("wrote ping icon (light/dark/tinted) to", OUT)
