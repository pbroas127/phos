# Cuts medal sprite sheets into clean transparent PNGs for App/Trophies.xcassets.
# Usage: python slice_trophies.py SHEET name1 name2 ... (names in reading order, left to right, top to bottom)
#    or: python slice_trophies.py --plan (cuts every sheet listed in trophy_sheets/plan.json that exists)
import json
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG = ROOT / "App" / "Trophies.xcassets"
SHEETS = ROOT / "Tools" / "brand" / "trophy_sheets"
PREVIEW = ROOT / "Tools" / "brand" / "trophy_previews"
SIZE = 600  # output canvas in pixels, square


def runs(flags, min_len):
    """Start and end of each run of True values at least min_len long."""
    out, start = [], None
    for i, f in enumerate(list(flags) + [False]):
        if f and start is None:
            start = i
        elif not f and start is not None:
            if i - start >= min_len:
                out.append((start, i))
            start = None
    return out


def pil_mask(arr):
    return Image.fromarray((arr * 255).astype(np.uint8))


def cut(sheet_path, names):
    im = Image.open(sheet_path).convert("RGB")
    rgb = np.asarray(im).astype(np.float32)
    ink = 255 - rgb.min(axis=2)
    solid = ink > 28
    # Opening removes specks and faint noise so the white gaps read as empty.
    solid = np.asarray(pil_mask(solid).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))) > 127
    min_len = im.width // 10
    boxes = []
    for y0, y1 in runs(solid.any(axis=1), min_len):
        for x0, x1 in runs(solid[y0:y1].any(axis=0), min_len):
            band = solid[y0:y1, x0:x1]
            ys = np.where(band.any(axis=1))[0]
            boxes.append((y0 + ys[0], y0 + ys[-1] + 1, x0, x1))
    if len(boxes) != len(names):
        raise SystemExit(f"{sheet_path}: found {len(boxes)} medals, expected {len(names)}")

    CATALOG.mkdir(parents=True, exist_ok=True)
    (CATALOG / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    PREVIEW.mkdir(parents=True, exist_ok=True)
    for name, (y0, y1, x0, x1) in zip(names, boxes):
        pad = 8
        y0, y1 = max(0, y0 - pad), min(im.height, y1 + pad)
        x0, x1 = max(0, x0 - pad), min(im.width, x1 + pad)
        crop = rgb[y0:y1, x0:x1]
        core = solid[y0:y1, x0:x1]
        # Fill holes: flood the outside from a corner, anything not reached belongs to the medal.
        flood = pil_mask(core).convert("L")
        ImageDraw.floodfill(flood, (0, 0), 128)
        mask = np.asarray(flood) != 128
        grown = np.asarray(pil_mask(mask).filter(ImageFilter.MaxFilter(5))) > 127
        inner = np.asarray(pil_mask(mask).filter(ImageFilter.MinFilter(5))) > 127
        soft = np.clip((255 - crop.min(axis=2)) / 40.0, 0, 1)
        alpha = np.where(mask, 1.0, np.where(grown, soft, 0.0))
        alpha = np.asarray(pil_mask(alpha).filter(ImageFilter.GaussianBlur(0.7))) / 255.0
        alpha = np.where(inner, 1.0, alpha)
        # Un-mix edge pixels from the white background so there is no light halo on dark screens.
        a = np.maximum(alpha, 1e-3)[..., None]
        color = np.clip((crop - (1 - a) * 255) / a, 0, 255)
        medal = Image.fromarray(np.dstack([color, alpha * 255]).astype(np.uint8), "RGBA")
        side = max(medal.width, medal.height)
        square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        square.paste(medal, ((side - medal.width) // 2, (side - medal.height) // 2))
        square = square.resize((SIZE, SIZE), Image.LANCZOS)
        folder = CATALOG / f"trophy_{name}.imageset"
        folder.mkdir(parents=True, exist_ok=True)
        square.save(folder / f"trophy_{name}.png", optimize=True)
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"idiom": "universal", "filename": f"trophy_{name}.png"}],
            "info": {"author": "xcode", "version": 1}
        }, indent=2))
    # Contact sheet on light and dark grounds to check the edges.
    thumbs = [Image.open(CATALOG / f"trophy_{n}.imageset" / f"trophy_{n}.png") for n in names]
    sheet = Image.new("RGB", (len(thumbs) * 160, 320), (251, 249, 244))
    sheet.paste((21, 18, 14), (0, 160, len(thumbs) * 160, 320))
    for i, t in enumerate(thumbs):
        small = t.resize((150, 150), Image.LANCZOS)
        sheet.paste(small, (i * 160 + 5, 5), small)
        sheet.paste(small, (i * 160 + 5, 165), small)
    sheet.save(PREVIEW / f"{pathlib.Path(sheet_path).stem}.png")
    print(pathlib.Path(sheet_path).name, "ok", len(names))


if __name__ == "__main__":
    if sys.argv[1:] == ["--plan"]:
        plan = json.loads((SHEETS / "plan.json").read_text())
        for sheet, names in plan.items():
            path = next((p for p in SHEETS.glob(f"{sheet}.*") if p.suffix.lower() in (".jpg", ".png")), None)
            if path:
                cut(path, names)
    else:
        cut(sys.argv[1], sys.argv[2:])
