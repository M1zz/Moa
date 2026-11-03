"""Generates the 1800x1200 App Clip card image for 보태줘.

No text and no QR code: iOS draws the title, subtitle and action button below the card, and
the card is what appears *after* scanning, so another QR on it only confuses the guest.
Colours and the polaroid shape come from the app icon, so the card and the icon read as one.
Drawn at 2x and downscaled so every edge stays smooth.
"""
from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path

S = 2                      # supersampling
W, H = 1800 * S, 1200 * S

# App icon palette.
TEAL = (22, 96, 109)
TEAL_DEEP = (12, 62, 72)
WARM = (237, 137, 93)
SUN = (255, 205, 120)
WHITE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def background() -> Image.Image:
    # Teal at the top melting into the icon's warm orange at the bottom.
    col = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H - 1)
        if t < 0.45:
            c = lerp(TEAL_DEEP, TEAL, t / 0.45)
        else:
            c = lerp(TEAL, WARM, ((t - 0.45) / 0.55) ** 1.4)
        col.putpixel((0, y), c)
    base = col.resize((W, H))

    # Soft light behind the stack so the eye lands on the middle.
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse([W * 0.28, H * 0.12, W * 0.72, H * 0.92], fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(180 * S))
    light = Image.new("RGB", (W, H), (120, 190, 190))
    base = Image.composite(light, base, glow.point(lambda v: int(v * 0.28)))

    # Darken the corners a little.
    vig = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vig).ellipse([-W * 0.2, -H * 0.3, W * 1.2, H * 1.3], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(220 * S))
    dark = Image.new("RGB", (W, H), (8, 40, 48))
    return Image.composite(base, dark, vig.point(lambda v: int(80 + v * 175 / 255)))


def polaroid(w: int, sky, hill, sun=SUN, dots=False) -> Image.Image:
    """A white polaroid like the app icon: photo on top, wider strip at the bottom."""
    h = int(w * 1.18)
    pad = int(w * 0.075)
    strip = int(w * 0.24)
    radius = int(w * 0.10)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=WHITE + (255,))

    iw, ih = w - pad * 2, h - pad - strip
    photo = Image.new("RGB", (iw, ih), sky)
    pd = ImageDraw.Draw(photo)
    r = ih * 0.12
    pd.ellipse([iw * 0.72 - r, ih * 0.24 - r, iw * 0.72 + r, ih * 0.24 + r], fill=sun)
    pd.polygon([(-iw * 0.05, ih), (iw * 0.36, ih * 0.50), (iw * 0.62, ih * 0.80), (iw * 0.62, ih)], fill=hill)
    pd.polygon([(iw * 0.40, ih), (iw * 0.70, ih * 0.62), (iw * 1.05, ih), ], fill=hill)
    pd.rectangle([0, ih * 0.93, iw, ih], fill=hill)

    mask = Image.new("L", (iw, ih), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, iw - 1, ih - 1], radius=int(radius * 0.55), fill=255)
    img.paste(photo, (pad, pad), mask)

    if dots:
        cy = h - strip / 2
        dr = w * 0.032
        for i, c in enumerate([WARM, TEAL, WARM]):
            cx = w / 2 + (i - 1) * w * 0.11
            d.ellipse([cx - dr, cy - dr, cx + dr, cy + dr], fill=c)
    return img


def place(canvas: Image.Image, tile: Image.Image, center, angle: float, opacity=1.0, shadow=1.0):
    rotated = tile.rotate(angle, expand=True, resample=Image.BICUBIC)
    if opacity < 1:
        a = rotated.split()[3].point(lambda v: int(v * opacity))
        rotated.putalpha(a)

    # Shadow on a padded canvas so the blur never gets clipped into a hard box.
    blur = int(28 * S)
    m = blur * 3
    sh = Image.new("RGBA", (rotated.width + m * 2, rotated.height + m * 2), (0, 0, 0, 0))
    alpha = Image.new("L", sh.size, 0)
    alpha.paste(rotated.split()[3].point(lambda v: int(v * 0.42 * shadow)), (m, m))
    alpha = alpha.filter(ImageFilter.GaussianBlur(blur))
    sh.putalpha(alpha)

    x = int(center[0] - rotated.width / 2)
    y = int(center[1] - rotated.height / 2)
    canvas.alpha_composite(sh, (x - m + 8 * S, y - m + 26 * S))
    canvas.alpha_composite(rotated, (x, y))


def trail(canvas: Image.Image, start, end, bend):
    """A faint dotted arc from a drifting photo toward the stack."""
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    (x0, y0), (x1, y1) = start, end
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2 + bend
    n = 9
    for i in range(1, n):
        t = i / n
        x = (1 - t) ** 2 * x0 + 2 * (1 - t) * t * cx + t ** 2 * x1
        y = (1 - t) ** 2 * y0 + 2 * (1 - t) * t * cy + t ** 2 * y1
        r = (5 + 5 * (1 - t)) * S
        a = int(150 * (1 - t) + 40)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))
    canvas.alpha_composite(layer)


def main():
    canvas = background().convert("RGBA")
    cx, cy = W * 0.5, H * 0.50

    # Photos from several people drifting in from both sides, each a different moment.
    drifting = [
        # (width, sky, hill, center, angle, opacity, trail bend)
        (W * 0.115, (110, 170, 190), (60, 120, 130), (W * 0.105, H * 0.24), 18, 0.95, 90),
        (W * 0.130, (250, 196, 150), (200, 110, 80), (W * 0.150, H * 0.73), -12, 1.0, -80),
        (W * 0.115, (180, 150, 200), (110, 80, 140), (W * 0.895, H * 0.25), -20, 0.95, 90),
        (W * 0.130, (140, 200, 200), (40, 110, 110), (W * 0.850, H * 0.74), 14, 1.0, -80),
    ]
    for w, sky, hill, pos, angle, op, bend in drifting:
        tx = cx - (W * 0.13 if pos[0] < cx else -W * 0.13)
        trail(canvas, (pos[0] + (W * 0.07 if pos[0] < cx else -W * 0.07), pos[1]), (tx, cy), bend * S)
    for w, sky, hill, pos, angle, op, bend in drifting:
        place(canvas, polaroid(int(w), sky, hill), pos, angle, op, 0.7)

    # The gathered stack, same shape as the app icon.
    big = int(W * 0.235)
    place(canvas, polaroid(big, (200, 225, 225), (150, 190, 190)), (cx - W * 0.012, cy + H * 0.01), 11, 0.55, 0.5)
    place(canvas, polaroid(big, (235, 210, 190), (215, 160, 130)), (cx + W * 0.012, cy), -9, 0.70, 0.6)
    place(canvas, polaroid(big, TEAL, WARM, dots=True), (cx, cy - H * 0.01), 0)

    out = canvas.convert("RGB").resize((1800, 1200), Image.LANCZOS)
    out.save(str(Path(__file__).with_name("app-clip-card.png")), optimize=True)
    print("saved", out.size)


main()
