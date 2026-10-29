"""Poster / icon / preview for A-Life: Reactive Survivors, in the style of the SmoothRide / ZombieSync / Tripping
Zombies MP Fix / Wandering Hordes Performance Fix art (dark grid, Bahnschrift, white + teal title, badges, teal glow,
spaced caption): a survivor swinging at a zombie that is still two rings away.

  python -I make_art.py      writes 42/poster.png, 42/icon.png and docs/preview.png (repo layout)
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
FONT = r"C:\Windows\Fonts\bahnschrift.ttf"
TEAL = (34, 211, 197)
WHITE = (240, 244, 246)
BG0, BG1 = (13, 18, 22), (22, 30, 36)
FAINT = (52, 66, 76)
AMBER = (232, 160, 70)
ZOMBIE = (74, 86, 94)
RED = (224, 64, 52)


def font(size, style="Bold"):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name(style)
    except Exception:
        pass
    return f


def background(w, h):
    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        k = y / (h - 1)
        c = tuple(int(BG0[i] + (BG1[i] - BG0[i]) * k) for i in range(3))
        for x in range(w):
            px[x, y] = c
    d = ImageDraw.Draw(im)
    for x in range(0, w, 32):
        d.line([(x, 0), (x, h)], fill=(26, 35, 42))
    for y in range(0, h, 32):
        d.line([(0, y), (w, y)], fill=(26, 35, 42))
    return im


def spaced(d, xy, text, f, fill, spacing):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=f, fill=fill)
        x += d.textlength(ch, font=f) + spacing
    return x


def text_width(d, text, f, spacing):
    return sum(d.textlength(ch, font=f) for ch in text) + spacing * (len(text) - 1)


def fit(d, text, size, width, style="Bold"):
    f = font(size, style)
    while d.textlength(text, font=f) > width and size > 10:
        size -= 2
        f = font(size, style)
    return f


def survivor(d, x, y, h, fill):
    """standing figure, feet at (x, y), bat raised to the right"""
    r = h * 0.11
    d.ellipse([x - r, y - h, x + r, y - h + 2 * r], fill=fill)
    d.line([(x, y - h + 2 * r), (x, y - h * 0.34)], fill=fill, width=max(2, int(h * 0.11)))
    d.line([(x, y - h * 0.34), (x - h * 0.11, y)], fill=fill, width=max(2, int(h * 0.08)))
    d.line([(x, y - h * 0.34), (x + h * 0.11, y)], fill=fill, width=max(2, int(h * 0.08)))
    d.line([(x, y - h * 0.64), (x + h * 0.30, y - h * 0.80)], fill=fill, width=max(2, int(h * 0.07)))
    d.line([(x + h * 0.30, y - h * 0.80), (x + h * 0.52, y - h * 1.08)], fill=fill, width=max(2, int(h * 0.085)))


def zombie(d, x, y, h, fill):
    """leaning figure, feet at (x, y), arms reaching left, one red eye"""
    r = h * 0.11
    hx = x - h * 0.10
    d.ellipse([hx - r, y - h * 0.96, hx + r, y - h * 0.96 + 2 * r], fill=fill)
    d.line([(hx, y - h * 0.96 + 2 * r), (x, y - h * 0.34)], fill=fill, width=max(2, int(h * 0.11)))
    d.line([(x, y - h * 0.34), (x - h * 0.08, y)], fill=fill, width=max(2, int(h * 0.08)))
    d.line([(x, y - h * 0.34), (x + h * 0.14, y)], fill=fill, width=max(2, int(h * 0.08)))
    d.line([(x - h * 0.04, y - h * 0.66), (x - h * 0.44, y - h * 0.62)], fill=fill, width=max(2, int(h * 0.065)))
    d.line([(x - h * 0.04, y - h * 0.58), (x - h * 0.42, y - h * 0.50)], fill=fill, width=max(2, int(h * 0.065)))
    er = max(1.5, h * 0.03)
    d.ellipse([hx - r * 0.55 - er, y - h * 0.96 + r * 0.8 - er, hx - r * 0.55 + er, y - h * 0.96 + r * 0.8 + er], fill=RED)


def scene(im, s, sx, sy, zx, h, rings, labels=None):
    """survivor at (sx, sy) feet, zombie at (zx, sy); rings = ((radius, alpha), ...) around the survivor's feet"""
    size = im.size[0]
    glow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    g = ImageDraw.Draw(glow)
    sharp = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(sharp)
    d.line([(int(16 * s), sy), (size - int(16 * s), sy)], fill=FAINT + (255,), width=max(1, int(2 * s)))
    for radius, alpha in rings:
        box = [sx - radius, sy - radius * 0.30, sx + radius, sy + radius * 0.30]
        g.ellipse(box, outline=TEAL + (alpha,), width=max(2, int(5 * s)))
        d.ellipse(box, outline=TEAL + (alpha,), width=max(1, int(2 * s)))
    # the swing: an arc of the bat
    arc = [sx - h * 0.05, sy - h * 1.22, sx + h * 0.95, sy - h * 0.36]
    g.arc(arc, start=215, end=330, fill=TEAL + (230,), width=max(2, int(6 * s)))
    d.arc(arc, start=215, end=330, fill=TEAL + (255,), width=max(1, int(3 * s)))
    zombie(d, zx, sy, h * 0.98, ZOMBIE + (255,))
    survivor(d, sx, sy, h, WHITE + (255,))
    if labels:
        fl = font(int(14 * s), "SemiBold")
        for text, (lx, ly) in labels:
            d.text((lx, ly), text, font=fl, fill=(120, 190, 184, 255))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(7 * s)))
    im.alpha_composite(sharp)


def badge(d, x, y, w, h, s, text, fill=None, outline=None, color=WHITE):
    if fill is not None:
        d.rounded_rectangle([x, y, x + w, y + h], radius=int(7 * s), fill=fill)
    else:
        d.rounded_rectangle([x, y, x + w, y + h], radius=int(7 * s), outline=outline, width=max(1, int(2 * s)))
    fb = font(int(24 * s), "SemiBold")
    tw = d.textlength(text, font=fb)
    d.text((x + (w - tw) / 2, y + int(5 * s)), text, font=fb, fill=color)


def poster(size=512):
    s = size / 512
    im = background(size, size).convert("RGBA")
    d = ImageDraw.Draw(im)
    f1 = fit(d, "A-LIFE REACTIVE", int(52 * s), int(452 * s))
    d.text((int(30 * s), int(22 * s)), "A-LIFE REACTIVE", font=f1, fill=WHITE)
    title = "SURVIVORS"
    f2 = fit(d, title, int(96 * s), int(452 * s))
    glow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).text((int(28 * s), int(84 * s)), title, font=f2, fill=TEAL + (200,))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(10 * s)))
    d = ImageDraw.Draw(im)
    d.text((int(28 * s), int(84 * s)), title, font=f2, fill=TEAL)
    # badges: LUA, B42, TEST VERSION
    by, bh = int(176 * s), int(38 * s)
    badge(d, int(30 * s), by, int(74 * s), bh, s, "LUA", fill=TEAL, color=(10, 30, 32))
    badge(d, int(116 * s), by, int(80 * s), bh, s, "B42", outline=(200, 208, 214), color=(220, 226, 230))
    badge(d, int(208 * s), by, int(176 * s), bh, s, "TEST VERSION", outline=AMBER, color=AMBER)
    # the scene: survivor, two rings (2.5 and 6 tiles), zombie inside the outer ring
    sy = int(386 * s)
    scene(im, s, int(198 * s), sy, int(372 * s), 122 * s,
          ((188 * s, 120), (70 * s, 210)),
          labels=[("2.5", (int(252 * s), int(400 * s))), ("6 TILES", (int(338 * s), int(428 * s)))])
    d = ImageDraw.Draw(im)
    fc = font(int(19 * s), "SemiBold")
    cap = "NPCS FIGHT BACK BEFORE THE BITE"
    w = text_width(d, cap, fc, 3 * s)
    spaced(d, ((size - w) / 2, int(468 * s)), cap, fc, (190, 200, 210), 3 * s)
    return im.convert("RGB")


def icon(size=128):
    s = size / 128
    im = background(size, size).convert("RGBA")
    scene(im, s * 2.2, int(44 * s), int(104 * s), int(96 * s), 78 * s, ((58 * s, 150), (22 * s, 220)))
    return im.convert("RGB")


if __name__ == "__main__":
    mod42 = os.path.join(PROJ, "42")
    docs = os.path.join(PROJ, "docs")
    os.makedirs(docs, exist_ok=True)
    p = poster(512)
    p.save(os.path.join(mod42, "poster.png"))
    p.save(os.path.join(docs, "preview.png"))
    icon(128).save(os.path.join(mod42, "icon.png"))
    print("written:", os.path.join(mod42, "poster.png"), os.path.join(mod42, "icon.png"), os.path.join(docs, "preview.png"))
