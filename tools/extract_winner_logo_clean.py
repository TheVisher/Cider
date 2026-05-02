from collections import deque
from colorsys import rgb_to_hsv
from pathlib import Path
from PIL import Image, ImageFilter


SRC = Path("brand/assets/logo-imagegen-three-c-loop-sheet-03.png")
OUT = Path("brand/assets/logo-winner-triangular-loop-isolated-clean.png")


def components(mask):
    w, h = mask.size
    px = mask.load()
    seen = bytearray(w * h)
    found = []
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if seen[i] or px[x, y] == 0:
                continue
            q = deque([(x, y)])
            seen[i] = 1
            pts = []
            while q:
                cx, cy = q.popleft()
                pts.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h:
                        ni = ny * w + nx
                        if not seen[ni] and px[nx, ny]:
                            seen[ni] = 1
                            q.append((nx, ny))
            found.append(pts)
    found.sort(key=len, reverse=True)
    return found


def main():
    sheet = Image.open(SRC).convert("RGBA")
    crop = sheet.crop((65, 525, 535, 965))
    w, h = crop.size
    src_px = crop.load()

    seed = Image.new("L", (w, h), 0)
    seed_px = seed.load()
    alpha = Image.new("L", (w, h), 0)
    alpha_px = alpha.load()

    for y in range(h):
        for x in range(w):
            r, g, b, _ = src_px[x, y]
            hue, sat, val = rgb_to_hsv(r / 255, g / 255, b / 255)
            hue *= 360
            is_warm = 12 <= hue <= 62
            # The dark fold is still warm and saturated; the background haze is dimmer and less saturated.
            is_ribbon = is_warm and sat > 0.34 and val > 0.16
            is_hot_edge = r > 130 and g > 52 and b < 70
            if is_ribbon or is_hot_edge:
                seed_px[x, y] = 255
                a = int(min(255, max(0, (sat - 0.28) / 0.44 * 255)))
                if val > 0.42 and sat > 0.42:
                    a = max(a, 235)
                if val < 0.24:
                    a = min(a, 155)
                alpha_px[x, y] = a

    keep = Image.new("L", (w, h), 0)
    keep_px = keep.load()
    for comp in components(seed)[:2]:
        if len(comp) < 1200:
            continue
        for x, y in comp:
            keep_px[x, y] = 255

    # Grow the component just enough to preserve anti-aliased edges, then intersect with the alpha estimate.
    keep = keep.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(0.45))
    combined = Image.new("L", (w, h), 0)
    kp = keep.load()
    ap = alpha.load()
    cp = combined.load()
    for y in range(h):
        for x in range(w):
            cp[x, y] = min(kp[x, y], ap[x, y])

    # Remove faint ambient haze and gray baked-background remnants that cause visible boxes.
    cp = combined.load()
    for y in range(h):
        for x in range(w):
            r, g, b, _ = src_px[x, y]
            hue, sat, val = rgb_to_hsv(r / 255, g / 255, b / 255)
            hue *= 360
            warm_edge = 10 <= hue <= 65 and sat > 0.25 and val > 0.13
            hot_body = r > 116 and g > 46 and b < 78
            if not (warm_edge or hot_body):
                cp[x, y] = 0
    combined = combined.point(lambda v: 0 if v < 34 else min(255, int((v - 34) * 1.22)))
    out = crop.copy()
    out.putalpha(combined)
    bbox = combined.point(lambda v: 255 if v > 8 else 0).getbbox()
    if bbox:
        pad = 18
        bbox = (
            max(0, bbox[0] - pad),
            max(0, bbox[1] - pad),
            min(w, bbox[2] + pad),
            min(h, bbox[3] + pad),
        )
        out = out.crop(bbox)
    out.save(OUT)
    print(OUT)


if __name__ == "__main__":
    main()
