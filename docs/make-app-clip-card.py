"""Generates the 3000x2000 App Clip card image for 모아.

No text: iOS draws the title, subtitle and action button over the card itself.
Drawn at 2x and downscaled so every edge stays smooth.
"""
from PIL import Image, ImageDraw, ImageFilter
import math, random
from pathlib import Path

S = 2                      # supersampling
W, H = 3000 * S, 2000 * S
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


def qr_glyph(size: int) -> Image.Image:
    """A stylized QR: three finder eyes plus scattered modules."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    n = 9                                   # modules per side
    gap = size / n * 0.14
    cell = size / n
    white = (255, 255, 255, 255)

    def module(cx, cy, span=1, fill=white):
        x0 = cx * cell + gap / 2
        y0 = cy * cell + gap / 2
        x1 = (cx + span) * cell - gap / 2
        y1 = (cy + span) * cell - gap / 2
        d.rounded_rectangle([x0, y0, x1, y1], radius=cell * 0.28, fill=fill)

    def eye(cx, cy):
        x0, y0 = cx * cell, cy * cell
        x1, y1 = (cx + 3) * cell, (cy + 3) * cell
        d.rounded_rectangle([x0, y0, x1, y1], radius=cell * 0.75, fill=white)
        d.rounded_rectangle(
            [x0 + cell * 0.62, y0 + cell * 0.62, x1 - cell * 0.62, y1 - cell * 0.62],
            radius=cell * 0.45, fill=(0, 0, 0, 0),
        )
        d.rounded_rectangle(
            [x0 + cell * 1.05, y0 + cell * 1.05, x1 - cell * 1.05, y1 - cell * 1.05],
            radius=cell * 0.3, fill=white,
        )

    eye(0, 0); eye(n - 3, 0); eye(0, n - 3)

    taken = set()
    for cx in range(n):
        for cy in range(n):
            in_eye = (cx < 3 and cy < 3) or (cx >= n - 3 and cy < 3) or (cx < 3 and cy >= n - 3)
            if in_eye or (cx == 3 and cy == 3):
                taken.add((cx, cy))
    for cx in range(n):
        for cy in range(n):
            if (cx, cy) in taken:
                continue
            if random.random() < 0.42:
                module(cx, cy)
    return img


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

    qr_size = int(H * 0.50)
    qr = qr_glyph(qr_size)
    qr_center = (int(W * 0.29), int(H * 0.50))
    canvas.alpha_composite(qr, (qr_center[0] - qr_size // 2, qr_center[1] - qr_size // 2))

    # Photos flow out of the QR toward the right.
    tiles = [
        (photo_tile(int(W * 0.168), int(W * 0.200), (126, 186, 205), (206, 158, 120)), (W * 0.550, H * 0.61), 9),
        (photo_tile(int(W * 0.178), int(W * 0.216), (150, 199, 210), (231, 176, 128), sun=False), (W * 0.702, H * 0.45), -5),
        (photo_tile(int(W * 0.190), int(W * 0.230), (176, 213, 214), (243, 186, 132)), (W * 0.858, H * 0.55), 7),
    ]
    for tile, center, angle in tiles:
        place(canvas, tile, (int(center[0]), int(center[1])), angle)

    # A few travelling dots between the code and the photos.
    d = ImageDraw.Draw(canvas)
    for i in range(7):
        t = i / 6
        x = W * (0.395 + 0.075 * t)
        y = H * (0.52 - 0.10 * math.sin(t * math.pi))
        r = (11 + 14 * (1 - t)) * S
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, int(110 + 130 * (1 - t))))

    out = canvas.convert("RGB").resize((3000, 2000), Image.LANCZOS)
    out.save(str(Path(__file__).with_name("app-clip-card.png")), optimize=True)
    print("saved", out.size)


main()
