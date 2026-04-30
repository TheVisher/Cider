from pathlib import Path
from PIL import Image, ImageDraw, ImageFont


OUT = Path("brand/assets/logo-wordmark-sheet-01.png")
LOGO = Path("brand/assets/logo-winner-triangular-loop-isolated.png")


FONTS = {
    "SF Pro Display": "/System/Library/Fonts/SFNS.ttf",
    "SF Rounded": "/System/Library/Fonts/SFNSRounded.ttf",
    "Avenir Next": "/System/Library/Fonts/Avenir Next.ttc",
    "New York": "/System/Library/Fonts/NewYork.ttf",
    "Optima": "/System/Library/Fonts/Optima.ttc",
    "Futura": "/System/Library/Fonts/Supplemental/Futura.ttc",
}


def load_font(path, size):
    try:
        return ImageFont.truetype(path, size=size)
    except Exception:
        return ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size=size)


def bg(size):
    w, h = size
    im = Image.new("RGBA", size, (15, 17, 21, 255))
    px = im.load()
    for y in range(h):
        for x in range(w):
            warm = max(0, 1 - (((x - w * 0.18) / (w * 0.44)) ** 2 + ((y - h * 0.08) / (h * 0.38)) ** 2))
            cool = max(0, 1 - (((x - w * 0.88) / (w * 0.34)) ** 2 + ((y - h * 0.88) / (h * 0.42)) ** 2))
            r = 15 + int(warm * 26)
            g = 17 + int(warm * 14) + int(cool * 7)
            b = 21 + int(cool * 20)
            px[x, y] = (r, g, b, 255)
    return im


def contain(img, max_size):
    scale = min(max_size[0] / img.width, max_size[1] / img.height)
    return img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)


def add_shadow(canvas, logo, xy):
    alpha = logo.getchannel("A").filter(ImageFilter.GaussianBlur(16)).point(lambda v: int(v * 0.42))


def draw_logo(canvas, logo, x, y, size):
    mark = contain(logo, (size, size))
    shadow = Image.new("RGBA", mark.size, (0, 0, 0, 0))
    shadow.putalpha(mark.getchannel("A").filter(ImageFilter.GaussianBlur(18)).point(lambda v: int(v * 0.48)))
    canvas.alpha_composite(shadow, (x, y + 12))
    canvas.alpha_composite(mark, (x, y))
    return mark.size


def draw_row(canvas, row, name, font_path, subtitle, size=92, tracking=0):
    d = ImageDraw.Draw(canvas)
    x = 94
    y = 210 + row * 178
    d.rounded_rectangle((64, y - 44, 1536, y + 112), radius=24, fill=(28, 31, 36, 155), outline=(246, 239, 228, 24), width=1)
    logo = Image.open(LOGO).convert("RGBA")
    draw_logo(canvas, logo, x, y - 20, 112)
    word_x = x + 150
    f = load_font(font_path, size)
    fill = (246, 239, 228, 255)
    if tracking == 0:
        d.text((word_x, y - 18), "Cider", fill=fill, font=f)
    else:
        cx = word_x
        for ch in "Cider":
            d.text((cx, y - 18), ch, fill=fill, font=f)
            bbox = d.textbbox((cx, y - 18), ch, font=f)
            cx += bbox[2] - bbox[0] + tracking
    d.text((word_x + 2, y + 80), subtitle, fill=(244, 164, 43, 210), font=load_font(FONTS["SF Pro Display"], 24))
    d.text((1280, y + 34), name, fill=(246, 239, 228, 105), font=load_font(FONTS["SF Pro Display"], 24))


def main():
    canvas = bg((1600, 1350))
    d = ImageDraw.Draw(canvas)
    d.text((66, 62), "Cider Wordmark Pass", fill=(246, 239, 228, 255), font=load_font(FONTS["SF Pro Display"], 58))
    d.text((68, 126), "Same locked logo mark. Different word treatments beside it.", fill=(246, 239, 228, 135), font=load_font(FONTS["SF Pro Display"], 26))
    rows = [
        ("A. SF Rounded", FONTS["SF Rounded"], "Clean Mac, friendlier than default.", 94, -2),
        ("B. Avenir Next", FONTS["Avenir Next"], "Balanced, modern, slightly warmer.", 92, -1),
        ("C. New York", FONTS["New York"], "Premium serif, more editorial.", 94, -3),
        ("D. Optima", FONTS["Optima"], "Humanist, distinctive without yelling.", 92, -2),
        ("E. Futura", FONTS["Futura"], "Geometric, bolder product feel.", 90, 1),
        ("F. SF Pro", FONTS["SF Pro Display"], "Baseline default, included for comparison.", 92, -2),
    ]
    for i, row in enumerate(rows):
        draw_row(canvas, i, *row)
    canvas.convert("RGB").save(OUT)
    print(OUT)


if __name__ == "__main__":
    from PIL import ImageFilter
    main()
