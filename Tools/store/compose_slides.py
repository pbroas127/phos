# Builds 1284x2778 App Store slides: two line headline over a warm gradient, screenshot inside a phone frame.
# Usage: python compose_slides.py <folder with raw simulator screenshots>
import json, pathlib, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = pathlib.Path(__file__).parent
M = json.loads((HERE / "metadata.json").read_text(encoding="utf-8"))
SRC = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else HERE / "shots")
OUT = HERE / "slides"
OUT.mkdir(exist_ok=True)

W, H = 1284, 2778
INK = (34, 29, 23)
GOLD = (168, 122, 34)
FONT_DIR = pathlib.Path("C:/Windows/Fonts")


def font(name, size):
    for n in name:
        p = FONT_DIR / n
        if p.exists():
            return ImageFont.truetype(str(p), size)
    return ImageFont.load_default()


def background():
    top, bottom = (251, 249, 244), (238, 222, 190)
    bg = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(bg)
    for y in range(H):
        t = (y / H) ** 1.4
        d.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).ellipse([W * 0.1, H * 0.55, W * 0.9, H * 1.15], fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    return Image.composite(Image.new("RGB", (W, H), (233, 196, 120)), bg, glow)


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius, fill=255)
    out = Image.new("RGBA", img.size)
    out.paste(img, (0, 0), mask)
    return out


def slide(shot_path, line1, line2):
    canvas = background().convert("RGBA")
    d = ImageDraw.Draw(canvas)
    f = font(["georgiab.ttf", "timesbd.ttf"], 96)
    for i, (text, color) in enumerate([(line1, INK), (line2, GOLD)]):
        w = d.textlength(text, font=f)
        d.text(((W - w) / 2, 150 + i * 122), text, font=f, fill=color)

    shot = Image.open(shot_path).convert("RGB")
    screen_w = 1000
    screen_h = int(shot.height * screen_w / shot.width)
    shot = shot.resize((screen_w, screen_h), Image.LANCZOS)
    bezel = 26
    phone_w, phone_h = screen_w + bezel * 2, screen_h + bezel * 2
    x, y = (W - phone_w) // 2, 470

    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x + 10, y + 40, x + phone_w - 10, y + phone_h + 40], 150, fill=(60, 40, 10, 90))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(50)))

    body = Image.new("RGBA", (phone_w, phone_h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(body)
    bd.rounded_rectangle([0, 0, phone_w - 1, phone_h - 1], 150, fill=(28, 26, 24, 255))
    bd.rounded_rectangle([3, 3, phone_w - 4, phone_h - 4], 147, outline=(90, 84, 76, 255), width=3)
    canvas.alpha_composite(body, (x, y))
    canvas.alpha_composite(rounded(shot, 124), (x + bezel, y + bezel))
    return canvas.convert("RGB")


if __name__ == "__main__":
    for s in M["slides"]:
        src = SRC / f"{s['shot']}.png"
        if not src.exists():
            print("missing", src)
            continue
        slide(src, s["line1"], s["line2"]).save(OUT / s["file"], optimize=True)
        print("wrote", s["file"])
