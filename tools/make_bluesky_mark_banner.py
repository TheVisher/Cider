from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


LOGO = Path("brand/assets/logo-winner-triangular-loop-isolated-softclean.png")
OUT = Path("brand/assets/social-banner-bluesky-mark-v3-right.png")


def make_background(size):
    w, h = size
    im = Image.new("RGBA", size, (14, 17, 22, 255))
    px = im.load()
    for y in range(h):
        for x in range(w):
            warm = max(
                0,
                1
                - (
                    ((x - w * 0.78) / (w * 0.62)) ** 2
                    + ((y - h * 0.30) / (h * 0.82)) ** 2
                ),
            )
            amber = max(
                0,
                1
                - (
                    ((x - w * 0.74) / (w * 0.56)) ** 2
                    + ((y - h * 0.42) / (h * 0.76)) ** 2
                ),
            )
            cool = max(
                0,
                1
                - (
                    ((x - w * 0.08) / (w * 0.36)) ** 2
                    + ((y - h * 0.82) / (h * 0.48)) ** 2
                ),
            )
            px[x, y] = (
                14 + int(warm * 30) + int(amber * 12),
                17 + int(warm * 16) + int(amber * 8) + int(cool * 4),
                22 + int(cool * 20),
                255,
            )
    return im


def contain(img, max_size):
    scale = min(max_size[0] / img.width, max_size[1] / img.height)
    return img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)


def tint_alpha(img, opacity):
    mark = img.copy()
    alpha = mark.getchannel("A").point(lambda v: int(v * opacity))
    mark.putalpha(alpha)
    return mark


def add_soft_vignette(canvas):
    w, h = canvas.size
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    mask = Image.new("L", canvas.size, 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((-w * 0.10, -h * 0.65, w * 1.08, h * 1.30), fill=210)
    mask = mask.filter(ImageFilter.GaussianBlur(150))
    inverted = mask.point(lambda v: 120 - min(120, int(v * 0.55)))
    overlay.putalpha(inverted)
    canvas.alpha_composite(overlay)


def main():
    canvas = make_background((3000, 1000))
    logo = Image.open(LOGO).convert("RGBA")

    giant = contain(logo, (1220, 1220))
    giant = tint_alpha(giant, 0.27)
    giant_shadow = giant.getchannel("A").filter(ImageFilter.GaussianBlur(42)).point(lambda v: int(v * 0.45))
    shadow = Image.new("RGBA", giant.size, (0, 0, 0, 0))
    shadow.putalpha(giant_shadow)

    pos = (2200, 0)
    canvas.alpha_composite(shadow, (pos[0] + 42, pos[1] + 54))
    canvas.alpha_composite(giant, pos)

    # A tiny warm bloom keeps the right side from feeling empty without adding copy.
    bloom = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    bloom_mask = Image.new("L", canvas.size, 0)
    d = ImageDraw.Draw(bloom_mask)
    d.ellipse((-600, 20, 1450, 1080), fill=92)
    bloom_mask = bloom_mask.filter(ImageFilter.GaussianBlur(170))
    bloom.putalpha(bloom_mask)
    tint = Image.new("RGBA", canvas.size, (95, 56, 23, 0))
    tint.putalpha(bloom_mask.point(lambda v: int(v * 0.45)))
    canvas.alpha_composite(tint)

    add_soft_vignette(canvas)
    canvas.convert("RGB").save(OUT, quality=95)
    print(OUT)


if __name__ == "__main__":
    main()
