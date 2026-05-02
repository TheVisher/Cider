from pathlib import Path
from PIL import Image, ImageFilter


SRC = Path("brand/assets/logo-winner-triangular-loop-isolated.png")
OUT = Path("brand/assets/logo-winner-triangular-loop-isolated-softclean.png")


def main():
    src = Image.open(SRC).convert("RGBA")
    r, g, b, a = src.split()

    # Keep the original generated colors. Only remove the broad, low-alpha background box.
    hard = a.point(lambda v: 255 if v >= 118 else 0)
    silhouette = hard.filter(ImageFilter.MaxFilter(17)).filter(ImageFilter.GaussianBlur(5.0))
    silhouette = silhouette.point(lambda v: 255 if v > 10 else 0)

    out_alpha = Image.new("L", src.size, 0)
    ap = a.load()
    sp = silhouette.load()
    op = out_alpha.load()
    for y in range(src.height):
        for x in range(src.width):
            if sp[x, y]:
                op[x, y] = ap[x, y]

    # Fade the bottom baked floor shadow only, but keep object edges/highlights intact.
    op = out_alpha.load()
    for y in range(src.height):
        for x in range(src.width):
            if y > src.height * 0.86:
                op[x, y] = int(op[x, y] * 0.25)

    src.putalpha(out_alpha)
    bbox = out_alpha.point(lambda v: 255 if v > 2 else 0).getbbox()
    if bbox:
        pad = 20
        bbox = (
            max(0, bbox[0] - pad),
            max(0, bbox[1] - pad),
            min(src.width, bbox[2] + pad),
            min(src.height, bbox[3] + pad),
        )
        src = src.crop(bbox)
    src.save(OUT)
    print(OUT)


if __name__ == "__main__":
    main()
