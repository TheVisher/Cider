from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont


LOGO = Path("brand/assets/logo-winner-triangular-loop-isolated-softclean.png")
OUT_DIR = Path("brand/assets")
FONT_OPTIMA = "/System/Library/Fonts/Optima.ttc"
FONT_SF = "/System/Library/Fonts/SFNS.ttf"


def font(path, size):
    return ImageFont.truetype(path, size=size)


def bg(size):
    w, h = size
    im = Image.new("RGBA", size, (15, 17, 21, 255))
    px = im.load()
    for y in range(h):
        for x in range(w):
            warm = max(0, 1 - (((x - w * 0.30) / (w * 0.50)) ** 2 + ((y - h * 0.20) / (h * 0.58)) ** 2))
            cool = max(0, 1 - (((x - w * 0.88) / (w * 0.35)) ** 2 + ((y - h * 0.88) / (h * 0.46)) ** 2))
            px[x, y] = (
                15 + int(warm * 30),
                17 + int(warm * 16) + int(cool * 7),
                21 + int(cool * 21),
                255,
            )
    return im


def contain(img, max_size):
    scale = min(max_size[0] / img.width, max_size[1] / img.height)
    return img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)


def add_mark(canvas, logo, xy, max_size, shadow=0.48):
    mark = contain(logo, max_size)
    alpha = mark.getchannel("A").filter(ImageFilter.GaussianBlur(22)).point(lambda v: int(v * shadow))
    sh = Image.new("RGBA", mark.size, (0, 0, 0, 0))
    sh.putalpha(alpha)
    canvas.alpha_composite(sh, (xy[0], xy[1] + 16))
    canvas.alpha_composite(mark, xy)
    return mark.size


def draw_tracked(draw, xy, text, font_obj, fill, tracking=-2, stroke=1):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font_obj, fill=fill, stroke_width=stroke, stroke_fill=fill)
        bbox = draw.textbbox((x, y), ch, font=font_obj, stroke_width=stroke)
        x += bbox[2] - bbox[0] + tracking


def banner():
    canvas = bg((2400, 900))
    d = ImageDraw.Draw(canvas)
    for yoff, alpha in [(690, 52), (730, 28)]:
        pts = []
        import math
        for x in range(0, 2401, 60):
            y = yoff + int(34 * math.sin((x / 2400) * 8.2))
            pts.append((x, y))
        d.line(pts, fill=(244, 164, 43, alpha), width=3)
    logo = Image.open(LOGO).convert("RGBA")
    add_mark(canvas, logo, (660, 270), (330, 330))
    draw_tracked(d, (1030, 302), "Cider", font(FONT_OPTIMA, 154), (246, 239, 228, 255), tracking=-5, stroke=1)
    d.text((1038, 492), "Double-tap Option. Capture. Organize. Done.", font=font(FONT_SF, 42), fill=(246, 239, 228, 215))
    canvas.save(OUT_DIR / "brand-context-optima-banner.png")


def header():
    canvas = bg((1600, 420))
    d = ImageDraw.Draw(canvas)
    logo = Image.open(LOGO).convert("RGBA")
    add_mark(canvas, logo, (150, 126), (168, 168))
    draw_tracked(d, (350, 130), "Cider", font(FONT_OPTIMA, 104), (246, 239, 228, 255), tracking=-4, stroke=1)
    d.text((356, 252), "Your Mac's living knowledge vault", font=font(FONT_SF, 34), fill=(246, 239, 228, 150))
    canvas.save(OUT_DIR / "brand-context-optima-header.png")


def sheet():
    banner_im = Image.open(OUT_DIR / "brand-context-optima-banner.png").resize((900, 338), Image.LANCZOS)
    header_im = Image.open(OUT_DIR / "brand-context-optima-header.png").resize((900, 236), Image.LANCZOS)
    avatar = Image.open(OUT_DIR / "logo-winner-avatar-preview.png").resize((380, 380), Image.LANCZOS)
    canvas = bg((1400, 960))
    d = ImageDraw.Draw(canvas)
    d.text((70, 56), "Optima +1 Context Test", font=font(FONT_SF, 54), fill=(246, 239, 228, 255))
    d.text((72, 118), "Locked mark with the best current wordmark candidate.", font=font(FONT_SF, 25), fill=(246, 239, 228, 140))
    canvas.alpha_composite(avatar.convert("RGBA"), (90, 230))
    canvas.alpha_composite(header_im.convert("RGBA"), (460, 218))
    canvas.alpha_composite(banner_im.convert("RGBA"), (460, 516))
    canvas.save(OUT_DIR / "brand-context-optima-sheet.png")


def main():
    banner()
    header()
    sheet()
    print(OUT_DIR / "brand-context-optima-sheet.png")
    print(OUT_DIR / "brand-context-optima-banner.png")
    print(OUT_DIR / "brand-context-optima-header.png")


if __name__ == "__main__":
    main()
