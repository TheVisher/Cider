from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


LOGO = Path("brand/assets/logo-winner-triangular-loop-isolated-softclean.png")
OUT = Path("brand/assets/readme-banner-v2.png")
FONT_OPTIMA = "/System/Library/Fonts/Optima.ttc"
FONT_SF = "/System/Library/Fonts/SFNS.ttf"


def font(path, size):
    return ImageFont.truetype(path, size=size)


def make_background(size):
    w, h = size
    im = Image.new("RGBA", size, (13, 16, 21, 255))
    px = im.load()
    for y in range(h):
        for x in range(w):
            warm = max(
                0,
                1
                - (
                    ((x - w * 0.52) / (w * 0.66)) ** 2
                    + ((y - h * 0.28) / (h * 0.86)) ** 2
                ),
            )
            amber = max(
                0,
                1
                - (
                    ((x - w * 0.22) / (w * 0.46)) ** 2
                    + ((y - h * 0.46) / (h * 0.72)) ** 2
                ),
            )
            cool = max(
                0,
                1
                - (
                    ((x - w * 0.96) / (w * 0.36)) ** 2
                    + ((y - h * 0.78) / (h * 0.54)) ** 2
                ),
            )
            px[x, y] = (
                13 + int(warm * 28) + int(amber * 18),
                16 + int(warm * 15) + int(amber * 9) + int(cool * 4),
                21 + int(cool * 18),
                255,
            )
    return im


def contain(img, max_size):
    scale = min(max_size[0] / img.width, max_size[1] / img.height)
    return img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)


def set_opacity(img, opacity):
    out = img.copy()
    out.putalpha(out.getchannel("A").point(lambda v: int(v * opacity)))
    return out


def add_mark(canvas, logo, xy, max_size, opacity=1.0, shadow=True):
    mark = contain(logo, max_size)
    if opacity < 1:
        mark = set_opacity(mark, opacity)

    if shadow:
        alpha = mark.getchannel("A").filter(ImageFilter.GaussianBlur(18)).point(lambda v: int(v * 0.45))
        shadow_im = Image.new("RGBA", mark.size, (0, 0, 0, 0))
        shadow_im.putalpha(alpha)
        canvas.alpha_composite(shadow_im, (xy[0] + 14, xy[1] + 18))

    canvas.alpha_composite(mark, xy)
    return mark.size


def draw_tracked(draw, xy, text, font_obj, fill, tracking=-2, stroke=1):
    x, y = xy
    for char in text:
        draw.text((x, y), char, font=font_obj, fill=fill, stroke_width=stroke, stroke_fill=fill)
        bbox = draw.textbbox((x, y), char, font=font_obj, stroke_width=stroke)
        x += bbox[2] - bbox[0] + tracking


def main():
    canvas = make_background((1600, 400))
    logo = Image.open(LOGO).convert("RGBA")
    d = ImageDraw.Draw(canvas)

    # Large quiet mark for brand texture on the far right.
    add_mark(canvas, logo, (1240, -48), (520, 520), opacity=0.20, shadow=True)

    # Main lockup, close to the current GitHub layout but calmer.
    add_mark(canvas, logo, (235, 86), (220, 220), opacity=1.0, shadow=True)
    draw_tracked(d, (500, 98), "Cider", font(FONT_OPTIMA, 118), (248, 241, 230, 255), tracking=-5, stroke=1)
    d.text((508, 232), "macOS", font=font(FONT_SF, 46), fill=(248, 241, 230, 174))

    # Soft bottom shade keeps the image grounded in GitHub dark mode.
    shade = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    mask = Image.new("L", canvas.size, 0)
    md = ImageDraw.Draw(mask)
    md.rectangle((0, 260, 1600, 400), fill=95)
    mask = mask.filter(ImageFilter.GaussianBlur(70))
    shade.putalpha(mask)
    canvas.alpha_composite(shade)

    canvas.convert("RGB").save(OUT, quality=95)
    print(OUT)


if __name__ == "__main__":
    main()
