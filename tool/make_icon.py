# Generates the RehabPlus app icon into assets/icon/: a bold white "R" with the
# blue shield-plus logo as a badge at its top right, on the app's teal
# gradient (same colors as the login page and splash).
#
# Run: python3 tool/make_icon.py   (needs Pillow)
# then: dart run flutter_launcher_icons
# then: git checkout -- ios/Runner.xcodeproj/project.pbxproj   (plugin bug, see
#       flutter_launcher_icons.yaml)
#
# Tweak the colors, the shield proportions in shield_points() or the layout in
# draw_mark() and re-run.
from PIL import Image, ImageDraw, ImageFont
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "icon")
S = 1024          # output size
SS = 4            # supersampling factor for smooth edges
FONT = "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf"
SHIELD_BLUE = (0x51, 0x81, 0xF2)
# Login-page gradient, top-left -> bottom-right. The adaptive icon background
# in flutter_launcher_icons.yaml is the middle stop.
GRADIENT = [(0x0D, 0x6E, 0x71), (0x1E, 0x8E, 0x92), (0x2F, 0xB8, 0xBD)]


def cubic(p0, p1, p2, p3, steps=64):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        pts.append((
            mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0],
            mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1],
        ))
    return pts


def shield_points(cx, top, w, h):
    """Shield outline: rounded top corners, straight sides, curving to a point."""
    r = 0.13 * w
    l, rr = cx - w / 2, cx + w / 2
    side_end = top + 0.47 * h
    bottom = top + h
    pts = []
    pts += cubic((l, top + r), (l, top + r * 0.45), (l + r * 0.45, top), (l + r, top))
    pts += cubic((rr - r, top), (rr - r * 0.45, top), (rr, top + r * 0.45), (rr, top + r))
    pts.append((rr, side_end))
    pts += cubic((rr, side_end), (rr, top + 0.80 * h), (cx + 0.16 * w, top + 0.93 * h), (cx, bottom))
    pts += cubic((cx, bottom), (cx - 0.16 * w, top + 0.93 * h), (l, top + 0.80 * h), (l, side_end))
    return pts


def gradient():
    """Diagonal 3-stop gradient like the login page."""
    small = Image.new("RGB", (256, 256))
    px = small.load()
    assert px is not None
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            a, b, u = (GRADIENT[0], GRADIENT[1], t * 2) if t < 0.5 else (GRADIENT[1], GRADIENT[2], t * 2 - 1)
            px[x, y] = tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3))
    return small.resize((S, S), Image.Resampling.BICUBIC).convert("RGBA")


def draw_mark(img, scale):
    """White R plus the shield badge, drawn supersampled onto img (RGBA)."""
    n = S * SS
    k = scale * SS
    c = n / 2
    # Shift so the R + badge group (not just the R) is centred.
    ox, oy = -50 * k, 55 * k
    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # The R, a little left and low so the badge fits at its top right.
    font = ImageFont.truetype(FONT, int(640 * k))
    d.text((c - 70 * k + ox, c + 40 * k + oy), "R", font=font, fill="white", anchor="mm")

    # Shield badge: white ring so it stands out on the teal, blue shield, white plus.
    bw, bh = 250 * k, 285 * k
    bx, btop = c + 225 * k + ox, c - 395 * k + oy
    ring = 26 * k
    d.polygon(shield_points(bx, btop - ring, bw + 2 * ring, bh + 2.3 * ring), fill="white")
    d.polygon(shield_points(bx, btop, bw, bh), fill=SHIELD_BLUE)
    py = btop + bh * 0.42
    arm, bar = 70 * k, 30 * k
    d.rounded_rectangle([bx - arm, py - bar / 2, bx + arm, py + bar / 2], radius=bar / 2, fill="white")
    d.rounded_rectangle([bx - bar / 2, py - arm, bx + bar / 2, py + arm], radius=bar / 2, fill="white")

    img.alpha_composite(layer.resize((S, S), Image.Resampling.LANCZOS))
    return img


os.makedirs(OUT, exist_ok=True)

# Full icon (iOS, legacy Android, web, desktop): square, opaque (iOS rejects alpha).
draw_mark(gradient(), 0.86).convert("RGB").save(os.path.join(OUT, "app_icon.png"))

# Android adaptive foreground: transparent; the plugin insets it 16% and the
# launcher masks it (circle/squircle), so keep the mark inside the round mask.
draw_mark(Image.new("RGBA", (S, S), (0, 0, 0, 0)), 0.80).save(os.path.join(OUT, "app_icon_foreground.png"))
print("wrote", OUT)
