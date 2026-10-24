# Generates the RehabPlus app icon into assets/icon/.
#
# Design (Apple's app-icon guidance, from the apple-design and
# ios-hig-design skills): one simple, centred glyph that reads at 29 px,
# no text, a gently lit background, nothing near the edges.
#   * Glyph: the app's own shield-plus logo (the same mark as the splash
#     screen and the Home header): a white shield with the plus cut out, so
#     the background shows through it. Replaces the old white "R" + blue
#     shield badge (Apple: avoid text in icons; one mark, not two).
#   * Background: the brand teal as a soft TOP-TO-BOTTOM gradient (lighter at
#     the top, as if lit from above, like Apple's own icons) instead of the
#     old diagonal three-stop gradient.
#   * A very faint shadow under the shield gives a hint of depth without a
#     "drop shadow" look.
#
# Files written (all 1024x1024):
#   app_icon.png             opaque square: iOS (which applies the rounded
#                            "squircle" mask itself), legacy Android, web,
#                            desktop.
#   app_icon_foreground.png  transparent shield for Android adaptive icons
#                            (background colour in flutter_launcher_icons.yaml).
#   app_icon_monochrome.png  white-on-transparent shield for Android 13+
#                            themed icons (the launcher tints it to match the
#                            wallpaper: Android's version of iOS "tinted"
#                            icons).
#
# Run: python3 tool/make_icon.py   (needs Pillow)
# then: dart run flutter_launcher_icons
# then: git checkout -- ios/Runner.xcodeproj/project.pbxproj   (plugin bug, see
#       flutter_launcher_icons.yaml)
#
# Tweak: colours below, the shield proportions in shield_points(), or the
# glyph size (GLYPH_*) and re-run.
from PIL import Image, ImageDraw, ImageFilter
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "icon")
S = 1024          # output size
SS = 4            # supersampling factor for smooth edges

# Brand teal (lib/core/app_palette.dart: teal 23A8AA, midTeal 1A8587).
TOP = (0x2C, 0xB5, 0xB6)      # a touch lighter than teal: the "lit" top
BOTTOM = (0x14, 0x7A, 0x7D)   # between midTeal and darkTeal
# Adaptive-icon background (flat; Android draws it): the gradient's middle.
# Keep in sync with adaptive_icon_background in flutter_launcher_icons.yaml.
ADAPTIVE_BG = "#1F9799"

# Shield height as a share of the canvas. The full icon keeps the glyph
# inside Apple's central grid; the adaptive foreground is smaller because
# Android insets it 16% and may mask it to a circle.
GLYPH_FULL = 0.56
GLYPH_ADAPTIVE = 0.50


def cubic(p0, p1, p2, p3, steps=96):
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
    """Shield outline: softly rounded top corners (continuous curves, like
    Apple's shapes rather than circle-arc corners), gently bowed sides that
    meet in a slightly rounded point."""
    r = 0.20 * w
    l, rr = cx - w / 2, cx + w / 2
    bottom = top + h
    tip = 0.035 * w
    pts = []
    pts += cubic((l, top + r), (l, top + r * 0.30), (l + r * 0.30, top), (l + r, top))
    pts += cubic((l + r, top), (cx - 0.1 * w, top), (cx + 0.1 * w, top), (rr - r, top))
    pts += cubic((rr - r, top), (rr - r * 0.30, top), (rr, top + r * 0.30), (rr, top + r))
    pts += cubic((rr, top + r), (rr, top + 0.62 * h), (cx + 0.30 * w, top + 0.86 * h), (cx + tip, bottom - 0.006 * h))
    pts += cubic((cx + tip, bottom - 0.006 * h), (cx + 0.012 * w, bottom + 0.004 * h),
                 (cx - 0.012 * w, bottom + 0.004 * h), (cx - tip, bottom - 0.006 * h))
    pts += cubic((cx - tip, bottom - 0.006 * h), (cx - 0.30 * w, top + 0.86 * h), (l, top + 0.62 * h), (l, top + r))
    return pts


def background():
    """Soft vertical gradient, lighter at the top."""
    col = Image.new("RGB", (1, 256))
    px = col.load()
    assert px is not None
    for y in range(256):
        t = y / 255
        t = t * t * (3 - 2 * t)  # ease: most of the change in the middle
        px[0, y] = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
    return col.resize((S, S), Image.Resampling.BICUBIC).convert("RGBA")


def shield_mask(glyph):
    """L mask of the shield (255 inside) with the plus cut out."""
    n = S * SS
    mask = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(mask)
    h = glyph * n
    w = h * 0.84
    cx = n / 2
    # Optical centre: the pointed bottom looks lighter than the flat top, so
    # sit the shape a little low to look centred.
    top = (n - h) / 2 + 0.02 * n
    d.polygon(shield_points(cx, top, w, h), fill=255)
    py = top + h * 0.43
    arm, bar = 0.25 * w, 0.115 * w
    d.rounded_rectangle([cx - arm, py - bar / 2, cx + arm, py + bar / 2], radius=bar / 2, fill=0)
    d.rounded_rectangle([cx - bar / 2, py - arm, cx + bar / 2, py + arm], radius=bar / 2, fill=0)
    return mask.resize((S, S), Image.Resampling.LANCZOS)


def white_glyph(glyph, shadow=True):
    """RGBA layer: the white shield, with an optional faint shadow."""
    mask = shield_mask(glyph)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    if shadow:
        sh = Image.new("RGBA", (S, S), (0, 40, 42, 0))
        sh.putalpha(mask.point(lambda v: int(v * 0.28)))
        sh = sh.filter(ImageFilter.GaussianBlur(14))
        layer.alpha_composite(sh, (0, 10))
    white = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    white.putalpha(mask)
    layer.alpha_composite(white)
    return layer


os.makedirs(OUT, exist_ok=True)

# Full icon: opaque square (iOS rejects alpha and masks the corners itself).
full = background()
full.alpha_composite(white_glyph(GLYPH_FULL))
full.convert("RGB").save(os.path.join(OUT, "app_icon.png"))

# Android adaptive foreground: transparent; the background colour comes from
# the yaml. No shadow: launchers add their own depth.
white_glyph(GLYPH_ADAPTIVE, shadow=False).save(os.path.join(OUT, "app_icon_foreground.png"))

# Android 13+ themed icon: the same silhouette in one colour; the launcher
# tints it.
mono = Image.new("RGBA", (S, S), (255, 255, 255, 0))
mono.putalpha(shield_mask(GLYPH_ADAPTIVE))
mono.save(os.path.join(OUT, "app_icon_monochrome.png"))

print("wrote", OUT, "adaptive background", ADAPTIVE_BG)
