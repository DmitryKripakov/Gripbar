"""Renders Gripbar's engraved slot glyphs (Media/Glyph*.tga) in the style of
the native crossbar's A / B / X / Y slots. Needs Pillow.

usage: glyphs.py preview <out.png>
       glyphs.py build <font.ttf> <outdir> [TEXT ...]   (default: L4 R4 L5 R5 M1-M4 Fn)
       glyphs.py paddles <media dir>                      (GlyphP1-P4 from Media/P1-P4.tga)
       glyphs.py icon <media dir> [docs dir]              (Media/Icon.tga, docs/icon.png)

The shipped glyphs use Palatino Linotype Bold (palab.ttf).
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

SIZE = 256
FONTS = {
    "georgia": r"C:\Windows\Fonts\georgiab.ttf",
    "constantia": r"C:\Windows\Fonts\constanb.ttf",
    "palatino": r"C:\Windows\Fonts\palab.ttf",
    "cambria": r"C:\Windows\Fonts\cambriab.ttc",
    "times": r"C:\Windows\Fonts\timesbd.ttf",
    "bookman": r"C:\Windows\Fonts\BOOKOSB.TTF",
}


def text_mask(text, font_path, size=SIZE, fill_ratio=0.62):
    """Alpha mask of the text, centred, sized so its width/height fits."""
    font_size = int(size * 0.62)
    while True:
        font = ImageFont.truetype(font_path, font_size)
        box = font.getbbox(text)
        w, h = box[2] - box[0], box[3] - box[1]
        if w <= size * fill_ratio and h <= size * 0.52 or font_size < 10:
            break
        font_size -= 1
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    x = (size - w) / 2 - box[0]
    y = (size - h) / 2 - box[1]
    d.text((x, y), text, font=font, fill=255)
    return mask


def emboss(mask, size=SIZE):
    """Dark letter, vertical gradient, light rim at the bottom edge, dark rim
    on top: the engraved look of the native A / B / X / Y."""
    # Gradient fill for the letter body.
    grad = Image.new("RGBA", (size, size))
    gp = grad.load()
    top = (92, 84, 74)
    bottom = (44, 40, 36)
    for yy in range(size):
        t = yy / (size - 1)
        c = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        for xx in range(size):
            gp[xx, yy] = c + (255,)

    # Rims: shifted copies of the mask minus the mask itself.
    def shifted(dx, dy):
        return ImageChops.offset(mask, dx, dy)

    light = ImageChops.subtract(shifted(0, 4), mask).filter(ImageFilter.GaussianBlur(0.6))
    dark = ImageChops.subtract(shifted(0, -4), mask).filter(ImageFilter.GaussianBlur(0.6))
    outline = ImageChops.subtract(mask.filter(ImageFilter.MaxFilter(9)), mask).filter(ImageFilter.GaussianBlur(0.8))

    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # Soft dark outline around the letter.
    out = Image.alpha_composite(out, solid((10, 9, 8), outline, 0.75))
    # Dark rim above (engraved shadow).
    out = Image.alpha_composite(out, solid((8, 7, 6), dark, 0.9))
    # Letter body.
    body = grad.copy()
    body.putalpha(mask)
    out = Image.alpha_composite(out, body)
    # Inner highlight near the top of the strokes.
    inner = ImageChops.subtract(mask, shifted(0, 6)).filter(ImageFilter.GaussianBlur(0.5))
    out = Image.alpha_composite(out, solid((120, 110, 96), inner, 0.35))
    # Light rim below (bevel catch light).
    out = Image.alpha_composite(out, solid((150, 138, 118), light, 0.55))
    return out


def engrave(mask, size=SIZE, glow=True):
    """The native D-pad / face-button slot art (reference: the d-pad left
    slot): a warm spotlight in the middle of the slot fading to the dark rim,
    the symbol cut in near-black, with a light lip on its lower / right edges
    and a soft shadow on the upper / left ones."""
    import random

    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    if glow:
        # Radial spotlight: (84,76,65) in the centre -> transparent at the
        # inner edge of the slot ring, with a little grain.
        g = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        gp = g.load()
        cx = cy = (size - 1) / 2
        radius = size * 0.43
        rnd = random.Random(7)
        centre = (84, 76, 65)
        edge = (30, 26, 20)
        for yy in range(size):
            for xx in range(size):
                d = ((xx - cx) ** 2 + (yy - cy) ** 2) ** 0.5 / radius
                if d >= 1:
                    continue
                t = min(1.0, d)
                c = [centre[i] * (1 - t) + edge[i] * t for i in range(3)]
                n = rnd.uniform(-4, 4)
                c = tuple(max(0, min(255, int(v + n))) for v in c)
                # Opaque in the middle, feathered out towards the ring.
                a = 235 if d < 0.8 else int(235 * (1 - (d - 0.8) / 0.2))
                gp[xx, yy] = c + (a,)
        out = Image.alpha_composite(out, g)

    def shifted(dx, dy):
        return ImageChops.offset(mask, dx, dy)

    # Shadow cast over the upper / left edge of the cut.
    shadow = ImageChops.subtract(shifted(-3, -4), mask).filter(ImageFilter.GaussianBlur(2.0))
    out = Image.alpha_composite(out, solid((10, 9, 8), shadow, 0.55))

    # The cut itself: near black, a touch lighter at the bottom.
    body = Image.new("RGBA", (size, size))
    bp = body.load()
    top, bottom = (17, 17, 16), (24, 23, 21)
    for yy in range(size):
        t = yy / (size - 1)
        c = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        for xx in range(size):
            bp[xx, yy] = c + (255,)
    body.putalpha(mask)
    out = Image.alpha_composite(out, body)

    # Light lip on the lower / right edges (the far wall of the cut).
    lip = ImageChops.subtract(shifted(3, 4), mask).filter(ImageFilter.GaussianBlur(0.8))
    out = Image.alpha_composite(out, solid((96, 86, 70), lip, 0.85))
    # Faint inner rim on the upper / left edges inside the cut.
    inner = ImageChops.subtract(mask, shifted(2, 3)).filter(ImageFilter.GaussianBlur(0.7))
    out = Image.alpha_composite(out, solid((6, 6, 5), inner, 0.6))
    return out


def solid(color, alpha_mask, strength):
    layer = Image.new("RGBA", alpha_mask.size, color + (0,))
    layer.putalpha(alpha_mask.point(lambda v: int(v * strength)))
    return layer


def disk(size=SIZE):
    """Preview backdrop only: a dark translucent disk like an empty slot."""
    img = Image.new("RGBA", (size, size), (40, 60, 30, 255))
    d = ImageDraw.Draw(img)
    d.ellipse((6, 6, size - 6, size - 6), fill=(48, 44, 40, 255), outline=(110, 98, 84, 255), width=6)
    return img


def preview(out_path):
    texts = ["L4", "R4", "L5", "R5", "A"]
    rows = []
    for name, path in FONTS.items():
        if not os.path.exists(path):
            continue
        row = Image.new("RGBA", (SIZE * len(texts) + 160, SIZE), (30, 45, 25, 255))
        ImageDraw.Draw(row).text((4, SIZE // 2 - 6), name, fill=(230, 230, 230, 255))
        for i, t in enumerate(texts):
            cell = disk()
            cell = Image.alpha_composite(cell, emboss(text_mask(t, path, fill_ratio=0.62 if len(t) > 1 else 0.42)))
            row.paste(cell, (160 + i * SIZE, 0))
        rows.append(row)
    sheet = Image.new("RGBA", (rows[0].width, SIZE * len(rows)))
    for i, r in enumerate(rows):
        sheet.paste(r, (0, i * SIZE))
    sheet.save(out_path)


TEXT_GLYPHS = ["L4", "R4", "L5", "R5", "M1", "M2", "M3", "M4", "Fn"]


def build(font_path, outdir, texts=None):
    os.makedirs(outdir, exist_ok=True)
    for t in texts or TEXT_GLYPHS:
        mask = text_mask(t, font_path, fill_ratio=0.58)
        # Thicker strokes, matching the weight of the native X / Y / A / B.
        mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.0))
        img = engrave(mask)
        img.save(os.path.join(outdir, "Glyph" + t + ".tga"))
    print("built", outdir)


if __name__ == "__main__":
    if sys.argv[1] in ("paddles", "icon"):
        pass
    elif sys.argv[1] == "preview":
        preview(sys.argv[2])
    else:
        build(sys.argv[2], sys.argv[3], sys.argv[4:])


def build_paddles(media):
    """Engraved P1-P4 paddle glyphs from the original Media/P1-P4.tga shapes
    (the white paddle silhouette; its grey end becomes a second, lighter tone
    so P1 / P2 and P3 / P4 stay apart)."""
    for i in range(1, 5):
        src = Image.open(os.path.join(media, "P%d.tga" % i)).convert("RGBA")
        lum, alpha = src.convert("L").load(), src.getchannel("A").load()
        mask = Image.new("L", (SIZE, SIZE), 0)
        mp = mask.load()
        c = (SIZE - 1) / 2
        for y in range(SIZE):
            for x in range(SIZE):
                if ((x - c) ** 2 + (y - c) ** 2) ** 0.5 < SIZE * 0.37 and lum[x, y] > 140 and alpha[x, y] > 128:
                    mp[x, y] = 255
        mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(1.0))
        second = Image.new("L", (SIZE, SIZE), 0)
        sp, mp = second.load(), mask.load()
        for y in range(SIZE):
            for x in range(SIZE):
                if mp[x, y] > 200 and 120 < lum[x, y] < 225:
                    sp[x, y] = 255
        second = second.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.0))
        art = Image.alpha_composite(engrave(mask), solid((46, 43, 38), second, 0.9))
        art.save(os.path.join(media, "GlyphP%d.tga" % i))
    print("built paddles", media)


if __name__ == "__main__" and len(sys.argv) > 2 and sys.argv[1] == "paddles":
    build_paddles(sys.argv[2])


def _smooth(edge0, edge1, x):
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


def ring_slot(size, pad=4):
    """A round crossbar slot of our own: dark backing with a soft inner bevel
    (lighter at the top, darker at the bottom), a bronze rim and a thin dark
    outline, on transparent. Colours and proportions measured from the game's
    circle slot; no game art is copied."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = (size - 1) / 2
    radius = size / 2 - pad
    rim = (126, 101, 75)
    outline = (30, 14, 10)
    for y in range(size):
        for x in range(size):
            dx, dy = x - c, y - c
            d = (dx * dx + dy * dy) ** 0.5 / radius
            if d > 1.04:
                continue
            # backing with the inner bevel
            up = -dy / radius                      # +1 top, -1 bottom
            bevel = _smooth(0.70, 0.88, d)
            base = 33 + bevel * 6 * up
            back = (base + 1, base, base - 2)
            back_a = 1.0 - _smooth(0.90, 0.93, d)
            # bronze rim, brightest in its middle, with a soft glint where the
            # light comes from (top left) that fades out around the ring
            rim_a = _smooth(0.875, 0.915, d) * (1.0 - _smooth(0.975, 0.995, d))
            shade = 0.80 + 0.20 * (1.0 - abs(d - 0.945) / 0.05)
            angle = math.atan2(-dy, dx)                    # 0 right, +pi/2 top
            # Two glints: the main one at the top left, a softer one at the
            # bottom right; each fades out along a wide arc of the ring.
            main = max(0.0, math.cos(angle - math.radians(135))) ** 1.6
            rear = max(0.0, math.cos(angle - math.radians(-45))) ** 1.6
            glint = max(main, 0.75 * rear)
            shade *= 0.82 + 0.70 * glint
            spec = (main ** 3 + 0.6 * rear ** 3) * max(0.0, 1.0 - abs(d - 0.94) / 0.028)
            # thin outline just outside the rim
            out_a = _smooth(0.975, 0.99, d) * (1.0 - _smooth(1.005, 1.035, d)) * 0.9
            r = g = b = 0.0
            a = 0.0
            rim_col = tuple(min(255.0, v * shade + 120 * spec) for v in rim)
            for col, al in ((back, back_a), (rim_col, rim_a), (outline, out_a)):
                if al <= 0:
                    continue
                r = col[0] * al + r * (1 - al)
                g = col[1] * al + g * (1 - al)
                b = col[2] * al + b * (1 - al)
                a = al + a * (1 - al)
            if a > 0:
                px[x, y] = (int(r / a if a else 0), int(g / a if a else 0), int(b / a if a else 0), int(a * 255))
    return img


ICON_FONT = r"C:\Windows\Fonts\palab.ttf"


def build_icon(media, docs=None, text="R4"):
    """The addon icon: one round slot with an engraved glyph. Media/Icon.tga
    (128 x 128) and, with a docs folder, docs/icon.png (256 x 256)."""
    big = 512
    slot = ring_slot(big, pad=8)
    # The letters alone (no glow of their own: the slot's glow is below),
    # built the same way as the in-game glyphs.
    inner = int(big * 0.92)
    mask = text_mask(text, ICON_FONT, size=SIZE, fill_ratio=0.58)
    mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.0))
    g = engrave(mask, glow=False).resize((inner, inner), Image.LANCZOS)
    # keep the glyph (and its glow) inside the rim
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).ellipse((big * 0.075, big * 0.075, big * 0.925, big * 0.925), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(4))
    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    layer.alpha_composite(g, ((big - inner) // 2, (big - inner) // 2))
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    # The slot's own glow fills the whole disk up to the rim, like the game's
    # slot (the glyph texture's glow is sized for in-game slots and comes out
    # too small once the glyph is scaled down here).
    glow = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    gp = glow.load()
    c = (big - 1) / 2
    reach = big / 2 * 0.86
    centre, edge = (84, 76, 65), (33, 31, 28)
    for y in range(big):
        for x in range(big):
            dist = ((x - c) ** 2 + (y - c) ** 2) ** 0.5 / reach
            if dist >= 1:
                continue
            t = dist ** 1.3
            col = tuple(int(centre[i] * (1 - t) + edge[i] * t) for i in range(3))
            gp[x, y] = col + (int(255 * (1 - _smooth(0.85, 1.0, dist))),)
    slot = Image.alpha_composite(slot, glow)
    icon = Image.alpha_composite(slot, layer)
    # the rim on top again, so the glow never washes over it
    rim_only = slot.copy()
    rim_mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(rim_mask).ellipse((big * 0.05, big * 0.05, big * 0.95, big * 0.95), fill=255)
    rim_only.putalpha(ImageChops.subtract(slot.getchannel("A"), rim_mask))
    icon = Image.alpha_composite(icon, rim_only)
    icon.resize((128, 128), Image.LANCZOS).save(os.path.join(media, "Icon.tga"))
    if docs:
        os.makedirs(docs, exist_ok=True)
        icon.resize((256, 256), Image.LANCZOS).save(os.path.join(docs, "icon.png"))
        # Square logo for CurseForge: the slot on transparency, a little
        # padding around it.
        logo = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
        logo.alpha_composite(icon.resize((464, 464), Image.LANCZOS), (24, 24))
        logo.save(os.path.join(docs, "logo.png"))
    print("built icon", media)


if __name__ == "__main__" and len(sys.argv) > 2 and sys.argv[1] == "icon":
    build_icon(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
