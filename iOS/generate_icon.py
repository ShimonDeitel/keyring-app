from PIL import Image, ImageDraw

SIZE = 1024
BG = "#F1EFEA"
img = Image.new("RGB", (SIZE, SIZE), BG)
draw = ImageDraw.Draw(img)

BRASS = "#B69244"
BRASS_DK = "#8F7133"

cx, cy = SIZE // 2, SIZE // 2

# Key bow (ring/head of the key) - top area, offset up-left
bow_cx, bow_cy = cx - 140, cy - 200
bow_r_outer = 175
bow_r_inner = 90
draw.ellipse([bow_cx - bow_r_outer, bow_cy - bow_r_outer, bow_cx + bow_r_outer, bow_cy + bow_r_outer], fill=BRASS)
draw.ellipse([bow_cx - bow_r_inner, bow_cy - bow_r_inner, bow_cx + bow_r_inner, bow_cy + bow_r_inner], fill=BG)

# Key shaft: diagonal bar from bow down to bottom-right, with teeth.
import math
angle = math.radians(45)
shaft_len = 560
ex = bow_cx + math.cos(angle) * shaft_len
ey = bow_cy + math.sin(angle) * shaft_len
draw.line([(bow_cx + bow_r_outer * 0.6, bow_cy + bow_r_outer * 0.6), (ex, ey)], fill=BRASS, width=64)

# Teeth (bit) at the tip: a few perpendicular notches.
perp = angle + math.pi / 2
for t in range(3):
    tx = ex - math.cos(angle) * (t * 60)
    ty = ey - math.sin(angle) * (t * 60)
    length = 70 - t * 15
    px = math.cos(perp) * length
    py = math.sin(perp) * length
    draw.line([(tx, ty), (tx + px, ty + py)], fill=BRASS, width=30)

img.save("/tmp/keyring_icon.png")
print("saved", img.size)
