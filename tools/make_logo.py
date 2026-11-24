"""Render the Better Cooldown Manager logo in the same style as Pa_nts' other addon
logos: dark rounded tile, light grey border, flat gold + cream icon with dark outlines.

The icon is a cream Cooldown Manager icon with a cooldown sweep across it, and a
gold "+" badge (it improves the built-in manager).

Usage: python make_logo.py <out_dir>
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

S = 1600  # draw big, downsample for smooth edges
out_dir = Path(sys.argv[1])
out_dir.mkdir(parents=True, exist_ok=True)

# Palette shared with the other logos
TILE_DARK = (13, 13, 13, 255)
TILE_LIGHT = (20, 20, 23, 255)
BORDER = (153, 153, 153, 255)
BORDER_INNER = (116, 116, 116, 255)
GOLD = (255, 209, 0, 255)
GOLD_DARK = (214, 150, 0, 255)
CREAM = (254, 252, 214, 255)
CREAM_SHADE = (200, 186, 156, 255)
OUTLINE = (58, 40, 34, 255)
SWEEP = (58, 40, 34, 150)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# --- Tile: dark fill with a subtle top-to-bottom gradient, grey border ----------
radius = int(S * 0.10)
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
for y in range(S):
    gd.line([(0, y), (S, y)], fill=lerp(TILE_LIGHT, TILE_DARK, y / S))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=radius, fill=255)
img.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(img)
bw = int(S * 0.036)
d.rounded_rectangle([0, 0, S - 1, S - 1], radius=radius, outline=BORDER, width=bw)
d.rounded_rectangle([bw, bw, S - 1 - bw, S - 1 - bw], radius=radius - bw, outline=BORDER_INNER, width=int(S * 0.008))

# --- Cooldown icon: cream square, shaded toward the edges -----------------------
x0, y0, x1, y1 = int(S * 0.22), int(S * 0.20), int(S * 0.74), int(S * 0.72)
icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ip = icon.load()
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
hw, hh = (x1 - x0) / 2, (y1 - y0) / 2
for y in range(y0, y1):
    for x in range(x0, x1):
        t = max(abs(x - cx) / hw, abs(y - cy) / hh)
        ip[x, y] = lerp(CREAM, CREAM_SHADE, max(0.0, (t - 0.55) / 0.45) ** 1.6)
imask = Image.new("L", (S, S), 0)
ImageDraw.Draw(imask).rounded_rectangle([x0, y0, x1, y1], radius=int(S * 0.03), fill=255)
img.paste(icon, (0, 0), imask)

# Cooldown sweep: a dark pie from 12 o'clock covering the remaining 70%,
# clipped to the icon square (like the swipe on a real cooldown icon).
sweep = Image.new("RGBA", (S, S), (0, 0, 0, 0))
big = int(hw * 1.6)
ImageDraw.Draw(sweep).pieslice([cx - big, cy - big, cx + big, cy + big], start=-90 + 108, end=270, fill=SWEEP)
clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
clipped.paste(sweep, (0, 0), imask)
img = Image.alpha_composite(img, clipped)

d = ImageDraw.Draw(img)
ow = int(S * 0.016)
# Sweep edge line from the centre to 12 o'clock and along the leading edge
d.line([(cx, cy), (cx, y0 + ow)], fill=OUTLINE, width=int(ow * 0.8))
ang = math.radians(-90 + 108)
ex, ey = cx + math.cos(ang) * hw * 1.5, cy + math.sin(ang) * hh * 1.5
# clip leading edge to the square
scale = min(hw / max(abs(ex - cx), 1e-6), hh / max(abs(ey - cy), 1e-6))
d.line([(cx, cy), (cx + (ex - cx) * scale * 0.97, cy + (ey - cy) * scale * 0.97)], fill=OUTLINE, width=int(ow * 0.8))
d.rounded_rectangle([x0, y0, x1, y1], radius=int(S * 0.03), outline=OUTLINE, width=ow)

# --- Gold "+" badge, bottom right (like the coin on the other logos) ------------
bx, by, br = int(S * 0.73), int(S * 0.72), int(S * 0.125)
d.ellipse([bx - br - ow, by - br - ow, bx + br + ow, by + br + ow], fill=OUTLINE)
d.ellipse([bx - br, by - br, bx + br, by + br], fill=GOLD)
ring = int(br * 0.74)
d.ellipse([bx - ring, by - ring, bx + ring, by + ring], outline=GOLD_DARK, width=int(S * 0.014))
arm, thick = int(br * 0.46), int(br * 0.17)
d.rounded_rectangle([bx - arm, by - thick, bx + arm, by + thick], radius=thick // 2, fill=GOLD_DARK)
d.rounded_rectangle([bx - thick, by - arm, bx + thick, by + arm], radius=thick // 2, fill=GOLD_DARK)

# --- Export ---------------------------------------------------------------------
for size in (400, 800):
    img.resize((size, size), Image.LANCZOS).save(out_dir / f"logo-{size}.png")
print("ok")
