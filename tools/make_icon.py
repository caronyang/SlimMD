"""SlimMD logo generator.

Produces candidate PNG previews and the final multi-size .ico used by:
  - the application window / taskbar (ApplicationIcon)
  - the Inno Setup installer (SetupIconFile)

Usage:  python tools/make_icon.py            # previews + ico
        python tools/make_icon.py --preview  # previews only
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SIZE = 256
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "src", "SlimMD")
PREVIEW_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "art")

FONTS = [
    r"C:\Windows\Fonts\segoeuib.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
    r"C:\Windows\Fonts\verdanab.ttf",
    r"C:\Windows\Fonts\tahomabd.ttf",
]


def first_font():
    for p in FONTS:
        if os.path.exists(p):
            return p
    raise SystemExit("no font found")


def gradient(size, top, bottom, angle="diag"):
    """Simple linear gradient image."""
    w = h = size
    img = Image.new("RGB", (w, h))
    px = img.load()
    tr, tg, tb = top
    br, bg, bb = bottom
    for y in range(h):
        for x in range(w):
            if angle == "diag":
                t = ((x / (w - 1)) + (y / (h - 1))) / 2
            else:
                t = y / (h - 1)
            px[x, y] = (
                int(tr + (br - tr) * t),
                int(tg + (bg - tg) * t),
                int(tb + (bb - tb) * t),
            )
    return img


def rounded_mask(size, box, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle(box, radius=radius, fill=255)
    return mask


def gloss(img, box, radius):
    """Subtle top highlight inside the tile."""
    x0, y0, x1, y1 = box
    h = y1 - y0
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    for i in range(int(h * 0.45)):
        a = int(46 * (1 - i / (h * 0.45)))
        d.line([(x0, y0 + i), (x1, y0 + i)], fill=(255, 255, 255, a))
    mask = Image.new("L", img.size, 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle(box, radius=radius, fill=255)
    overlay.putalpha(Image.composite(overlay.split()[3], Image.new("L", img.size, 0), mask))
    return Image.alpha_composite(img, overlay)


def geometric_m(draw, cx, cy, height, stroke, color):
    """Draw a bold geometric 'M' from polygons (no font dependency)."""
    half = height * 0.62  # half width of the letter
    x0, x1 = cx - half, cx + half
    top, bottom = cy - height / 2, cy + height / 2
    s = stroke
    mid = cx
    # left leg
    draw.rectangle([x0, top, x0 + s, bottom], fill=color)
    # right leg
    draw.rectangle([x1 - s, top, x1, bottom], fill=color)
    # left diagonal (top-left -> center bottom)
    draw.polygon(
        [(x0, top), (x0 + s, top), (mid + s * 0.15, bottom), (mid - s * 0.15, bottom)],
        fill=color,
    )
    # right diagonal (center bottom -> top-right)
    draw.polygon(
        [(mid - s * 0.15, bottom), (mid + s * 0.15, bottom), (x1, top), (x1 - s, top)],
        fill=color,
    )


def underscore(draw, cx, cy, width, height, color):
    draw.rounded_rectangle(
        [cx - width / 2, cy - height / 2, cx + width / 2, cy + height / 2],
        radius=height / 2,
        fill=color,
    )


def base_tile(box, radius, top, bottom):
    img = gradient(SIZE, top, bottom).convert("RGBA")
    mask = rounded_mask(SIZE, box, radius)
    img.putalpha(mask)
    img = gloss(img, box, radius)
    return img


def variant_card_font():
    """Slim portrait card, Segoe UI Bold 'M' + underscore."""
    box = (58, 14, 198, 242)
    img = base_tile(box, 34, (45, 212, 191), (59, 130, 246))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(first_font(), 108)
    d.text((128, 104), "M", font=font, fill=(255, 255, 255, 255), anchor="mm")
    underscore(d, 128, 186, 74, 16, (255, 255, 255, 255))
    return img


def variant_square_font():
    """Rounded square tile, 'M' + underscore."""
    box = (16, 16, 240, 240)
    img = base_tile(box, 52, (45, 212, 191), (59, 130, 246))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(first_font(), 122)
    d.text((128, 108), "M", font=font, fill=(255, 255, 255, 255), anchor="mm")
    underscore(d, 128, 192, 84, 18, (255, 255, 255, 255))
    return img


def variant_card_geo():
    """Slim portrait card, geometric M + underscore."""
    box = (58, 14, 198, 242)
    img = base_tile(box, 34, (45, 212, 191), (59, 130, 246))
    d = ImageDraw.Draw(img)
    geometric_m(d, 128, 104, 104, 24, (255, 255, 255, 255))
    underscore(d, 128, 186, 74, 16, (255, 255, 255, 255))
    return img


def variant_card_cursor():
    """Slim card where the M's right leg is a text cursor (editor + viewer)."""
    box = (58, 14, 198, 242)
    img = base_tile(box, 34, (45, 212, 191), (59, 130, 246))
    d = ImageDraw.Draw(img)
    geometric_m(d, 118, 104, 104, 24, (255, 255, 255, 255))
    # blinking-cursor bar as the right leg
    d.rounded_rectangle([174, 50, 192, 158], radius=9, fill=(255, 255, 255, 255))
    underscore(d, 128, 186, 74, 16, (255, 255, 255, 255))
    return img


VARIANTS = {
    "a_card_font": variant_card_font,
    "b_square_font": variant_square_font,
    "c_card_geo": variant_card_geo,
    "d_card_cursor": variant_card_cursor,
}


def main():
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    preview_only = "--preview" in sys.argv

    for name, fn in VARIANTS.items():
        img = fn()
        img.save(os.path.join(PREVIEW_DIR, f"icon_{name}.png"))
        # small-size proof sheet: 16 / 24 / 32 / 48 on white and dark
        sheet = Image.new("RGBA", (240, 72), (255, 255, 255, 255))
        dark = Image.new("RGBA", (120, 72), (32, 36, 44, 255))
        sheet.alpha_composite(dark, (120, 0))
        x = 12
        for s in (16, 24, 32, 48):
            thumb = img.resize((s, s), Image.LANCZOS)
            sheet.alpha_composite(thumb, (x, (72 - s) // 2))
            sheet.alpha_composite(thumb, (120 + x, (72 - s) // 2))
            x += s + 16
        sheet.save(os.path.join(PREVIEW_DIR, f"sheet_{name}.png"))

    if preview_only:
        print("previews written to", PREVIEW_DIR)
        return

    chosen = VARIANTS["a_card_font"]()
    ico_path = os.path.join(OUT_DIR, "SlimMD.ico")
    chosen.save(
        ico_path,
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print("wrote", ico_path)


if __name__ == "__main__":
    main()
