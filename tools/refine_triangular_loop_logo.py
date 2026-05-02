from pathlib import Path
from PIL import Image, ImageEnhance, ImageFilter, ImageOps


SRC = Path("brand/assets/logo-imagegen-three-c-loop-sheet-03.png")
OUT = Path("brand/assets/logo-triangular-loop-refinement-sheet-05.png")


def crop_source():
    sheet = Image.open(SRC).convert("RGBA")
    # Bottom-left mark from the sheet: the one the user liked.
    crop = sheet.crop((95, 540, 520, 965))
    return crop


def remove_dark_background(img):
    img = img.convert("RGBA")
    px = img.load()
    width, height = img.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = px[x, y]
            brightness = max(r, g, b)
            orange_bias = max(0, r - b) + max(0, g - b) * 0.4
            keep = max(0, brightness - 18) * 1.2 + orange_bias * 0.6
            alpha = int(max(0, min(255, keep)))
            if brightness < 34:
                alpha = 0
            px[x, y] = (r, g, b, alpha)
    alpha = img.getchannel("A").filter(ImageFilter.GaussianBlur(0.7))
    img.putalpha(alpha)
    bbox = alpha.point(lambda v: 255 if v > 12 else 0).getbbox()
    if bbox:
        pad = 22
        bbox = (
            max(0, bbox[0] - pad),
            max(0, bbox[1] - pad),
            min(width, bbox[2] + pad),
            min(height, bbox[3] + pad),
        )
        img = img.crop(bbox)
    return img


def fit(img, size=270):
    scale = size / max(img.size)
    return img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)


def tint(img, r_gain=1.0, g_gain=1.0, b_gain=1.0, contrast=1.0, saturation=1.0, sharpness=1.0):
    rgb = Image.new("RGBA", img.size, (0, 0, 0, 0))
    px = img.load()
    out = rgb.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            out[x, y] = (
                min(255, round(r * r_gain)),
                min(255, round(g * g_gain)),
                min(255, round(b * b_gain)),
                a,
            )
    rgb = ImageEnhance.Contrast(rgb).enhance(contrast)
    rgb = ImageEnhance.Color(rgb).enhance(saturation)
    rgb = ImageEnhance.Sharpness(rgb).enhance(sharpness)
    return rgb


def add_shadow(canvas, logo, xy):
    shadow = Image.new("RGBA", logo.size, (0, 0, 0, 0))
    shadow.putalpha(logo.getchannel("A").filter(ImageFilter.GaussianBlur(18)))
    shadow = ImageOps.colorize(shadow.getchannel("A"), (0, 0, 0), (0, 0, 0)).convert("RGBA")
    shadow.putalpha(logo.getchannel("A").filter(ImageFilter.GaussianBlur(18)).point(lambda v: int(v * 0.55)))
    canvas.alpha_composite(shadow, (xy[0], xy[1] + 22))
    canvas.alpha_composite(logo, xy)


def make_tile(mark, label):
    tile = Image.new("RGBA", (560, 440), (24, 27, 32, 220))
    border = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    # subtle glow behind the mark
    glow = Image.new("RGBA", tile.size, (244, 164, 43, 0))
    gp = glow.load()
    cx, cy = 280, 225
    for y in range(tile.height):
        for x in range(tile.width):
            d = ((x - cx) ** 2 / (260 ** 2) + (y - cy) ** 2 / (190 ** 2))
            if d < 1:
                gp[x, y] = (244, 164, 43, int((1 - d) * 32))
    tile.alpha_composite(glow)
    logo = fit(mark, 285)
    xy = ((tile.width - logo.width) // 2, 94 + (285 - logo.height) // 2)
    add_shadow(tile, logo, xy)
    return tile


def main():
    base = remove_dark_background(crop_source())
    base.save("brand/assets/logo-triangular-loop-source-cutout.png")
    variants = [
        tint(base, contrast=1.05, saturation=1.03, sharpness=1.10),
        tint(base.rotate(-4, resample=Image.Resampling.BICUBIC, expand=True), r_gain=1.04, g_gain=0.98, b_gain=0.92, contrast=1.10, saturation=1.08, sharpness=1.12),
        tint(base.rotate(3, resample=Image.Resampling.BICUBIC, expand=True), r_gain=1.02, g_gain=1.03, b_gain=0.96, contrast=1.08, saturation=1.00, sharpness=1.20),
        tint(base, r_gain=1.08, g_gain=0.94, b_gain=0.88, contrast=1.16, saturation=1.14, sharpness=1.16),
    ]

    sheet = Image.new("RGBA", (1400, 1050), (15, 17, 21, 255))
    for y in range(sheet.height):
        for x in range(sheet.width):
            # warm ambient vignette
            d = ((x - 230) ** 2 / (520 ** 2) + (y - 100) ** 2 / (360 ** 2))
            if d < 1:
                r, g, b, a = sheet.getpixel((x, y))
                sheet.putpixel((x, y), (min(255, r + int((1 - d) * 22)), min(255, g + int((1 - d) * 12)), b, a))

    positions = [(90, 120), (750, 120), (90, 580), (750, 580)]
    for variant, pos in zip(variants, positions):
        tile = make_tile(variant, "")
        sheet.alpha_composite(tile, pos)
    sheet.convert("RGB").save(OUT)
    print(OUT)
    print("brand/assets/logo-triangular-loop-source-cutout.png")


if __name__ == "__main__":
    main()
