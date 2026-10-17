# Generates the PLACEHOLDER app icon into assets/icon/. Delete once real artwork exists.
# Run: python3 tool/make_placeholder_icon.py  (needs Pillow), then: dart run flutter_launcher_icons
from PIL import Image, ImageDraw, ImageFont
import os

OUT = "/home/izaac/Documents/RehabPlus-Remote-PT-Monitoring-camera-monitoring/assets/icon"
os.makedirs(OUT, exist_ok=True)
S = 1024
FONT = "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf"
TOP, BOT = (0x00, 0xBC, 0xD4), (0x00, 0x83, 0x8F)  # theme cyan -> teal


def gradient():
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(TOP, BOT)))
    return img


def draw_mark(img, scale):
    """White 'R' with a small plus badge, centered; scale shrinks it for adaptive safe zone."""
    d = ImageDraw.Draw(img)
    c = S / 2
    font = ImageFont.truetype(FONT, int(620 * scale))
    d.text((c - 40 * scale, c + 20 * scale), "R", font=font, fill="white", anchor="mm")
    # plus badge, top-right of the R
    px, py = c + 230 * scale, c - 230 * scale
    arm, w = 110 * scale, 46 * scale
    d.rounded_rectangle([px - arm, py - w / 2, px + arm, py + w / 2], radius=w / 2, fill="white")
    d.rounded_rectangle([px - w / 2, py - arm, px + w / 2, py + arm], radius=w / 2, fill="white")


# Full icon (iOS, legacy Android, web, desktop) - square, no transparency (iOS requires that)
full = gradient()
draw_mark(full, 1.0)
full.save(f"{OUT}/app_icon.png")

# Android adaptive foreground - transparent; plugin insets it 16% and the launcher masks it
fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
draw_mark(fg, 1.0)
fg.save(f"{OUT}/app_icon_foreground.png")
print("ok")
