from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont


OUT = Path("brand/assets/logo-wordmark-sheet-02.png")
LOGO = Path("brand/assets/logo-winner-triangular-loop-isolated.png")

FONTS = {
    "SF": "/System/Library/Fonts/SFNS.ttf",
    "Optima": "/System/Library/Fonts/Optima.ttc",
    "Avenir": "/System/Library/Fonts/Avenir.ttc",
    "Avenir Next": "/System/Library/Fonts/Avenir Next.ttc",
    "Seravek": "/System/Library/Fonts/Supplemental/Seravek.ttc",
    "Helvetica Neue": "/System/Library/Fonts/HelveticaNeue.ttc",
}


def load_font(path, size):
    try:
        return ImageFont.truetype(path, size=size)
    except Exception:
        return ImageFont.truetype(FONTS["SF"], size=size)


def bg(size):
    w, h = size
    im = Image.new("RGBA", size, (15, 17, 21, 255))
    px = im.load()
    for y in range(h):
        for x in range(w):
            warm = max(0, 1 - (((x - w * 0.18) / (w * 0.44)) ** 2 + ((y - h * 0.08) / (h * 0.38)) ** 2))
            cool = max(0, 1 - (((x - w * 0.88) / (w * 0.34)) ** 2 + ((y - h * 0.88) / (h * 0.42)) ** 2))
            px[x, y] = (
                15 + int(warm * 26),
                17 + int(warm * 14) + int(cool * 7),
                21 + int(cool * 20),
                255,
            )
    return im


def contain(img, max_size):
    scale = min(max_size[0] / img.width, max_size[1] / img.height)
    return img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)


def draw_logo(canvas, logo, x, y, size):
    mark = contain(logo, (size, size))
    shadow = Image.new("RGBA", mark.size, (0, 0, 0, 0))
    shadow.putalpha(mark.getchannel("A").filter(ImageFilter.GaussianBlur(18)).point(lambda v: int(v * 0.48)))
    canvas.alpha_composite(shadow, (x, y + 12))
    canvas.alpha_composite(mark, (x, y))


def draw_tracked(d, xy, text, font_obj, fill, tracking=0, stroke_width=0):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, fill=fill, font=font_obj, stroke_width=stroke_width, stroke_fill=fill)
        bbox = d.textbbox((x, y), ch, font=font_obj, stroke_width=stroke_width)
        x += bbox[2] - bbox[0] + tracking


def draw_row(canvas, row, name, font_name, subtitle, size=94, tracking=-2, stroke=0):
    d = ImageDraw.Draw(canvas)
    x = 94
    y = 210 + row * 178
    d.rounded_rectangle((64, y - 44, 1536, y + 112), radius=24, fill=(28, 31, 36, 155), outline=(246, 239, 228, 24), width=1)
    logo = Image.open(LOGO).convert("RGBA")
    draw_logo(canvas, logo, x, y - 20, 112)
    word_x = x + 150
    f = load_font(FONTS[font_name], size)
    draw_tracked(d, (word_x, y - 18), "Cider", f, (246, 239, 228, 255), tracking=tracking, stroke_width=stroke)
    d.text((word_x + 2, y + 80), subtitle, fill=(244, 164, 43, 210), font=load_font(FONTS["SF"], 24))
    d.text((1280, y + 34), name, fill=(246, 239, 228, 105), font=load_font(FONTS["SF"], 24))


def main():
    canvas = bg((1600, 1350))
    d = ImageDraw.Draw(canvas)
    d.text((66, 62), "Cider Wordmark Pass 02", fill=(246, 239, 228, 255), font=load_font(FONTS["SF"], 58))
    d.text((68, 126), "Optima with more weight, Avenir with less bulk, plus nearby options.", fill=(246, 239, 228, 135), font=load_font(FONTS["SF"], 26))

    rows = [
        ("A. Optima +1", "Optima", "Optima feel, lightly strengthened.", 96, -3, 1),
        ("B. Optima +2", "Optima", "Same elegance, more presence.", 96, -3, 2),
        ("C. Optima Tight", "Optima", "A little larger and tighter.", 102, -6, 1),
        ("D. Avenir Light-ish", "Avenir", "Avenir direction, less chunky than before.", 90, -2, 0),
        ("E. Seravek", "Seravek", "Soft modern sans, between Avenir and SF.", 92, -2, 0),
        ("F. Helvetica Neue", "Helvetica Neue", "Neutral fallback, cleaner than SF.", 92, -2, 0),
    ]
    for i, row in enumerate(rows):
        draw_row(canvas, i, *row)

    canvas.convert("RGB").save(OUT)
    print(OUT)


if __name__ == "__main__":
    main()
