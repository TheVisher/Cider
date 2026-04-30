from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


LOGO = Path("brand/assets/logo-winner-triangular-loop-isolated-softclean.png")
OUT = Path("brand/assets/social-banner-discord-mark-v2-right.png")


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
                    ((x - w * 0.78) / (w * 0.65)) ** 2
                    + ((y - h * 0.36) / (h * 0.82)) ** 2
                ),
            )
            amber = max(
                0,
                1
                - (
                    ((x - w * 0.58) / (w * 0.58)) ** 2
                    + ((y - h * 0.46) / (h * 0.82)) ** 2
                ),
            )
            cool = max(
                0,
                1
                - (
                    ((x - w * 0.08) / (w * 0.38)) ** 2
                    + ((y - h * 0.84) / (h * 0.50)) ** 2
                ),
            )
            px[x, y] = (
                14 + int(warm * 30) + int(amber * 10),
                17 + int(warm * 15) + int(amber * 8) + int(cool * 4),
                22 + int(cool * 20),
                255,
            )
    return im


def contain(img, max_size):
    scale = min(max_size[0] / img.width, max_size[1] / img.height)
    return img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)


def faded(img, opacity):
    out = img.copy()
    out.putalpha(out.getchannel("A").point(lambda v: int(v * opacity)))
    return out


def main():
    canvas = make_background((1920, 1080))
    logo = Image.open(LOGO).convert("RGBA")
    giant = contain(logo, (860, 860))
    giant = faded(giant, 0.27)

    shadow_alpha = giant.getchannel("A").filter(ImageFilter.GaussianBlur(38)).point(lambda v: int(v * 0.48))
    shadow = Image.new("RGBA", giant.size, (0, 0, 0, 0))
    shadow.putalpha(shadow_alpha)

    pos = (1390, 120)
    canvas.alpha_composite(shadow, (pos[0] + 28, pos[1] + 42))
    canvas.alpha_composite(giant, pos)

    vignette = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    mask = Image.new("L", canvas.size, 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((-200, -260, 2140, 1340), fill=210)
    mask = mask.filter(ImageFilter.GaussianBlur(140))
    vignette.putalpha(mask.point(lambda v: 110 - min(110, int(v * 0.5))))
    canvas.alpha_composite(vignette)

    canvas.convert("RGB").save(OUT, quality=95)
    print(OUT)


if __name__ == "__main__":
    main()
