"""Generates the 1800x1200 App Clip card image for 모아.

No text and no QR code: iOS draws the title, subtitle and action button over the card, and
the card is what appears *after* scanning, so another QR on it only confuses the guest.
Drawn at 2x and downscaled so every edge stays smooth.
"""
from PIL import Image, ImageDraw, ImageFilter
import math, random
from pathlib import Path

S = 2                      # supersampling
W, H = 1800 * S, 1200 * S
TEAL_DARK = (10, 58, 68)
TEAL = (20, 96, 110)
WARM = (240, 138, 93)

random.seed(7)


def background() -> Image.Image:
    base = Image.new("RGB", (W, H), TEAL)
    px = base.load()
    # Diagonal gradient, dark top-left to lighter bottom-right.
    for y in range(H):
        for x in range(0, W, 8):
            t = (x / W * 0.55 + y / H * 0.45)
            r = int(TEAL_DARK[0] + (TEAL[0] - TEAL_DARK[0]) * t)
            g = int(TEAL_DARK[1] + (TEAL[1] - TEAL_DARK[1]) * t)
            b = int(TEAL_DARK[2] + (TEAL[2] - TEAL_DARK[2]) * t)
            for dx in range(8):
                if x + dx < W:
                    px[x + dx, y] = (r, g, b)

    # Warm glow behind the photos, the accent from the app icon.
    glow = Image.new("RGB", (W, H), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([W * 0.55, H * 0.30, W * 1.25, H * 1.25], fill=WARM)
    glow = glow.filter(ImageFilter.GaussianBlur(260 * S))
    base = Image.blend(base, Image.blend(base, glow, 0.30), 0.55)

    # Soft vignette so the bright tiles keep their edges against the corners.
    vignette = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vignette).ellipse([-W * 0.25, -H * 0.35, W * 1.25, H * 1.35], fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(200 * S))
    dark = Image.new("RGB", (W, H), (6, 34, 40))
    return Image.composite(base, dark, vignette)


def photo_tile(w: int, h: int, sky, ground, sun=True) -> Image.Image:
    """A rounded photo card: white frame, simple landscape inside."""
    pad = int(min(w, h) * 0.055)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    radius = int(min(w, h) * 0.09)
    d.rounded_rectangle([0, 0, w, h], radius=radius, fill=(255, 255, 255, 255))

    inner = Image.new("RGB", (w - pad * 2, h - pad * 2), sky)
    ip = inner.load()
    iw, ih = inner.size
    for y in range(ih):
        t = y / ih
        c = tuple(int(sky[i] + (ground[i] - sky[i]) * t) for i in range(3))
        for x in range(iw):
            ip[x, y] = c
    idr = ImageDraw.Draw(inner)
    if sun:
        idr.ellipse([iw * 0.60, ih * 0.14, iw * 0.60 + ih * 0.22, ih * 0.14 + ih * 0.22],
                    fill=(255, 245, 228))
    # Two hills, darker than the sky so the tile reads as a photo at a glance.
    hill = tuple(max(0, int(c * 0.62)) for c in ground)
    idr.polygon([(0, ih), (iw * 0.34, ih * 0.52), (iw * 0.68, ih)], fill=hill)
    hill2 = tuple(max(0, int(c * 0.78)) for c in ground)
    idr.polygon([(iw * 0.42, ih), (iw * 0.76, ih * 0.62), (iw, ih * 0.94), (iw, ih)], fill=hill2)

    mask = Image.new("L", inner.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, iw, ih], radius=int(radius * 0.7), fill=255)
    img.paste(inner, (pad, pad), mask)
    return img


def place(canvas: Image.Image, tile: Image.Image, center, angle: float):
    rotated = tile.rotate(angle, expand=True, resample=Image.BICUBIC)

    shadow = Image.new("RGBA", rotated.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 120), (0, 0), rotated.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(26 * S))
    sx = int(center[0] - rotated.width / 2)
    sy = int(center[1] - rotated.height / 2)
    canvas.alpha_composite(shadow, (sx + 10 * S, sy + 22 * S))
    canvas.alpha_composite(rotated, (sx, sy))


def main():
    canvas = background().convert("RGBA")

    # A fan of photos gathering in one place — what the app does, without a word of text.
    # Outer cards first so the biggest one lands in front.
    tiles = [
        (photo_tile(int(W * 0.150), int(W * 0.185), (126, 186, 205), (206, 158, 120)), (W * 0.268, H * 0.455), 16),
        (photo_tile(int(W * 0.155), int(W * 0.191), (176, 213, 214), (243, 186, 132)), (W * 0.732, H * 0.455), -16),
        (photo_tile(int(W * 0.170), int(W * 0.210), (150, 199, 210), (231, 176, 128)), (W * 0.392, H * 0.492), 8),
        (photo_tile(int(W * 0.172), int(W * 0.212), (140, 195, 212), (238, 182, 130)), (W * 0.608, H * 0.492), -8),
        (photo_tile(int(W * 0.196), int(W * 0.242), (160, 205, 212), (246, 190, 136)), (W * 0.500, H * 0.470), 0),
    ]
    for tile, center, angle in tiles:
        place(canvas, tile, (int(center[0]), int(center[1])), angle)

    out = canvas.convert("RGB").resize((1800, 1200), Image.LANCZOS)
    out.save(str(Path(__file__).with_name("app-clip-card.png")), optimize=True)
    print("saved", out.size)


main()
