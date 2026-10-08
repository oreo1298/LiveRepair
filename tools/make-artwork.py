#!/usr/bin/env python3
"""Draw the LiveRepair wallpaper and the syslinux boot menu splash (needs Pillow and DejaVu fonts).

    python3 tools/make-artwork.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_REGULAR = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
TOP, BOTTOM = (22, 34, 48), (12, 18, 26)
ACCENT = (64, 156, 255)


def gradient(w, h):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        row = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
        for x in range(w):
            px[x, y] = row
    return img


def background(y, h):
    t = y / (h - 1)
    return tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))


def wrench(draw, cx, cy, s, color, h):
    """A simple wrench: a handle with a ring at its head (h: image height, for the background)."""
    draw.line([(cx - s, cy + s), (cx + s * 0.45, cy - s * 0.45)], fill=color, width=round(s * 0.32))
    r = s * 0.55
    hx, hy = cx + s * 0.55, cy - s * 0.55
    draw.ellipse([hx - r, hy - r, hx + r, hy + r], outline=color, width=round(s * 0.26))
    # the jaw opening
    draw.polygon([(hx, hy), (hx + r * 1.4, hy - r * 0.2), (hx + r * 0.2, hy - r * 1.4)], fill=background(round(hy), h))


def wallpaper():
    w, h = 1920, 1080
    img = gradient(w, h)
    d = ImageDraw.Draw(img)
    title = ImageFont.truetype(FONT, 96)
    sub = ImageFont.truetype(FONT_REGULAR, 30)
    tagline = "clone · recover · check · burn · boot"
    text_w = max(d.textlength("LiveRepair", font=title), d.textlength(tagline, font=sub))
    x = w - 160 - text_w           # right-aligned, clear of the desktop icons on the left
    wrench(d, x - 110, 470, 70, ACCENT, h)
    d.text((x, 470), "LiveRepair", font=title, fill=(235, 240, 245), anchor="lm")
    d.text((x + 2, 560), tagline, font=sub, fill=(150, 165, 180), anchor="lm")
    out = ROOT / "profile/airootfs/usr/share/backgrounds/liverepair/wallpaper.png"
    img.quantize(colors=128, method=Image.Quantize.MEDIANCUT).save(out, optimize=True)
    print(out, out.stat().st_size)


def splash():
    w, h = 640, 480
    img = gradient(w, h)
    d = ImageDraw.Draw(img)
    wrench(d, 214, 70, 26, ACCENT, h)
    d.text((262, 72), "LiveRepair", font=ImageFont.truetype(FONT, 40), fill=(235, 240, 245), anchor="lm")
    out = ROOT / "profile/syslinux/splash.png"
    img.quantize(colors=64, method=Image.Quantize.MEDIANCUT).save(out, optimize=True)
    print(out, out.stat().st_size)


if __name__ == "__main__":
    wallpaper()
    splash()
