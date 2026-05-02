from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


SRC = Path("brand/assets/logo-imagegen-three-c-loop-sheet-03.png")
OUT_DIR = Path("brand/assets")
FONT = "/System/Library/Fonts/SFNS.ttf"


def font(size):
    return ImageFont.truetype(FONT, size=size)


def crop_winner():
    sheet = Image.open(SRC).convert("RGBA")
    # Bottom-left cell of the 2x3 image-gen sheet, with padding trimmed by alpha later.
    return sheet.crop((65, 525, 535, 965))


def cut_dark_background(img):
    img = img.convert("RGBA")
    px = img.load()
    width, height = img.size
    alpha = Image.new("L", (width, height), 0)
    apx = alpha.load()
    for y in range(height):
        for x in range(width):
            r, g, b, _ = px[x, y]
            brightness = max(r, g, b)
            orange = max(0, r - b) + max(0, g - b) * 0.35
            warm = max(0, r - 22) * 0.25 + orange * 0.85
            a = int(min(255, max(0, warm)))
            if brightness < 42:
                a = 0
            if r > 120 and g > 50 and b < 70:
                a = max(a, 230)
            apx[x, y] = a
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.9))
    img.putalpha(alpha)
    bbox = alpha.point(lambda v: 255 if v > 10 else 0).getbbox()
    if bbox:
        pad = 24
        bbox = (
            max(0, bbox[0] - pad),
            max(0, bbox[1] - pad),
            min(width, bbox[2] + pad),
            min(height, bbox[3] + pad),
        )
        img = img.crop(bbox)
    img = ImageEnhance.Contrast(img).enhance(1.04)
    img = ImageEnhance.Color(img).enhance(1.02)
    return img


def cover_fit(img, size):
    scale = max(size[0] / img.width, size[1] / img.height)
    resized = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    left = (resized.width - size[0]) // 2
    top = (resized.height - size[1]) // 2
    return resized.crop((left, top, left + size[0], top + size[1]))


def contain_fit(img, max_size):
    scale = min(max_size[0] / img.width, max_size[1] / img.height)
    return img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)


def bg(size):
    w, h = size
    im = Image.new("RGBA", size, (15, 17, 21, 255))
    px = im.load()
    for y in range(h):
        for x in range(w):
            warm = max(0, 1 - (((x - w * 0.28) / (w * 0.48)) ** 2 + ((y - h * 0.18) / (h * 0.58)) ** 2))
            cool = max(0, 1 - (((x - w * 0.86) / (w * 0.36)) ** 2 + ((y - h * 0.88) / (h * 0.44)) ** 2))
            r = 15 + int(warm * 28)
            g = 17 + int(warm * 15) + int(cool * 8)
            b = 21 + int(cool * 22)
            px[x, y] = (r, g, b, 255)
    return im


def add_shadow(canvas, logo, xy, blur=28, opacity=0.45, y_offset=22):
    a = logo.getchannel("A").filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * opacity))
    shadow = Image.new("RGBA", logo.size, (0, 0, 0, 0))
    shadow.putalpha(a)
    canvas.alpha_composite(shadow, (xy[0], xy[1] + y_offset))
    canvas.alpha_composite(logo, xy)


def make_avatar(logo):
    size = 1024
    canvas = bg((size, size))
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle((84, 84, size - 84, size - 84), radius=188, fill=(28, 31, 36, 198), outline=(246, 239, 228, 32), width=3)
    mark = contain_fit(logo, (650, 650))
    xy = ((size - mark.width) // 2, (size - mark.height) // 2 - 8)
    add_shadow(canvas, mark, xy, blur=34, opacity=0.55, y_offset=28)
    canvas.save(OUT_DIR / "logo-winner-avatar-preview.png")


def make_header(logo):
    canvas = bg((1600, 420))
    d = ImageDraw.Draw(canvas)
    mark = contain_fit(logo, (160, 160))
    add_shadow(canvas, mark, (150, 130), blur=24, opacity=0.46, y_offset=16)
    d.text((342, 142), "Cider", fill=(246, 239, 228, 255), font=font(92))
    d.text((348, 252), "Your Mac's living knowledge vault", fill=(246, 239, 228, 150), font=font(34))
    canvas.save(OUT_DIR / "logo-winner-header-preview.png")


def make_banner(logo):
    canvas = bg((2400, 900))
    d = ImageDraw.Draw(canvas)
    for yoff, alpha in [(690, 50), (728, 28)]:
        pts = []
        for x in range(0, 2401, 60):
            y = yoff + int(34 * __import__("math").sin((x / 2400) * 8.2))
            pts.append((x, y))
        d.line(pts, fill=(244, 164, 43, alpha), width=3)
    mark = contain_fit(logo, (310, 310))
    add_shadow(canvas, mark, (675, 280), blur=32, opacity=0.50, y_offset=24)
    d.text((1018, 312), "Cider", fill=(246, 239, 228, 255), font=font(146))
    d.text((1026, 490), "Double-tap Option. Capture. Organize. Done.", fill=(246, 239, 228, 210), font=font(42))
    canvas.save(OUT_DIR / "logo-winner-social-banner-preview.png")


def make_contact_sheet():
    avatar = Image.open(OUT_DIR / "logo-winner-avatar-preview.png").resize((380, 380), Image.LANCZOS)
    header = Image.open(OUT_DIR / "logo-winner-header-preview.png").resize((900, 236), Image.LANCZOS)
    banner = Image.open(OUT_DIR / "logo-winner-social-banner-preview.png").resize((900, 338), Image.LANCZOS)
    canvas = bg((1400, 960))
    d = ImageDraw.Draw(canvas)
    d.text((70, 56), "Cider Logo Context Test", fill=(246, 239, 228, 255), font=font(54))
    d.text((72, 118), "Winner mark tested as avatar, header lockup, and social banner.", fill=(246, 239, 228, 140), font=font(25))
    canvas.alpha_composite(avatar.convert("RGBA"), (90, 230))
    canvas.alpha_composite(header.convert("RGBA"), (460, 218))
    canvas.alpha_composite(banner.convert("RGBA"), (460, 516))
    canvas.save(OUT_DIR / "logo-winner-context-sheet.png")


def main():
    isolated = cut_dark_background(crop_winner())
    isolated.save(OUT_DIR / "logo-winner-triangular-loop-isolated-softclean.png")
    make_avatar(isolated)
    make_header(isolated)
    make_banner(isolated)
    make_contact_sheet()
    for name in [
        "logo-winner-triangular-loop-isolated-softclean.png",
        "logo-winner-avatar-preview.png",
        "logo-winner-header-preview.png",
        "logo-winner-social-banner-preview.png",
        "logo-winner-context-sheet.png",
    ]:
        print(OUT_DIR / name)


if __name__ == "__main__":
    main()
