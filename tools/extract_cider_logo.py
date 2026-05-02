from collections import deque
from colorsys import rgb_to_hsv
from pathlib import Path
from PIL import Image, ImageFilter


SRC = Path("brand/assets/icon-1024.png")


def connected_components(mask, width, height, min_alpha=1):
    data = mask.load()
    seen = bytearray(width * height)
    comps = []
    for y in range(height):
        for x in range(width):
            idx = y * width + x
            if seen[idx] or data[x, y] < min_alpha:
                continue
            q = deque([(x, y)])
            seen[idx] = 1
            pts = []
            while q:
                cx, cy = q.popleft()
                pts.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if nx < 0 or nx >= width or ny < 0 or ny >= height:
                        continue
                    nidx = ny * width + nx
                    if seen[nidx] or data[nx, ny] < min_alpha:
                        continue
                    seen[nidx] = 1
                    q.append((nx, ny))
            comps.append(pts)
    comps.sort(key=len, reverse=True)
    return comps


def make_cutout(name, saturation_floor, value_floor, include_dark_shadow):
    src = Image.open(SRC).convert("RGBA")
    width, height = src.size
    px = src.load()
    seed = Image.new("L", (width, height), 0)
    spx = seed.load()

    for y in range(height):
        for x in range(width):
            r, g, b, _ = px[x, y]
            hue, sat, val = rgb_to_hsv(r / 255, g / 255, b / 255)
            hue *= 360
            is_orange = 10 <= hue <= 62
            is_body = is_orange and sat >= saturation_floor and val >= value_floor
            is_shadow = include_dark_shadow and is_orange and sat >= 0.48 and val >= 0.13
            if is_body or is_shadow:
                spx[x, y] = 255

    comps = connected_components(seed, width, height)
    keep = Image.new("L", (width, height), 0)
    kpx = keep.load()
    for comp in comps[:3]:
        if len(comp) < 600:
            continue
        for x, y in comp:
            kpx[x, y] = 255

    # Lightly grow and soften the matte so antialiased edges survive.
    keep = keep.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(0.55))

    out = src.copy()
    out.putalpha(keep)
    bbox = keep.point(lambda v: 255 if v > 8 else 0).getbbox()
    if bbox:
        pad = 16
        bbox = (
            max(0, bbox[0] - pad),
            max(0, bbox[1] - pad),
            min(width, bbox[2] + pad),
            min(height, bbox[3] + pad),
        )
        out = out.crop(bbox)

    path = Path(f"brand/assets/{name}.png")
    out.save(path)
    return path


def checker_preview(cutout_path):
    logo = Image.open(cutout_path).convert("RGBA")
    scale = 360 / max(logo.size)
    logo = logo.resize((round(logo.width * scale), round(logo.height * scale)), Image.LANCZOS)
    canvas = Image.new("RGBA", (520, 420), (15, 17, 21, 255))
    for y in range(0, canvas.height, 32):
        for x in range(0, canvas.width, 32):
            c = (34, 36, 42, 255) if (x // 32 + y // 32) % 2 else (22, 24, 29, 255)
            canvas.paste(c, (x, y, x + 32, y + 32))
    canvas.alpha_composite(logo, ((canvas.width - logo.width) // 2, (canvas.height - logo.height) // 2))
    preview = cutout_path.with_name(cutout_path.stem + "-preview.png")
    canvas.convert("RGB").save(preview)
    return preview


def main():
    variants = [
        ("logo-c-extracted-soft", 0.43, 0.20, True),
        ("logo-c-extracted-tight", 0.52, 0.24, True),
        ("logo-c-extracted-clean", 0.58, 0.30, False),
    ]
    previews = []
    for args in variants:
        cutout = make_cutout(*args)
        preview = checker_preview(cutout)
        previews.append((cutout, preview))
        print(cutout)
        print(preview)

    sheet = Image.new("RGB", (520 * len(previews), 420), (15, 17, 21))
    for i, (_, preview) in enumerate(previews):
        sheet.paste(Image.open(preview).convert("RGB"), (520 * i, 0))
    sheet.save("brand/assets/logo-c-extraction-contact-sheet.png")
    print("brand/assets/logo-c-extraction-contact-sheet.png")


if __name__ == "__main__":
    main()
