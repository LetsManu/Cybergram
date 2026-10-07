#!/usr/bin/env python3
"""Look-dev contact sheets (docs/lookdev.md).

Reads <dir>/<view>_<variant>.png for every view and variant, writes
<dir>/sheet_<view>.jpg (variants side by side, labelled) and <dir>/overview.jpg
(views as rows, variants as columns).

    python3 tools/art/lookdev_sheet.py production/qa/evidence/lookdev
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

VIEWS = ["fp-lane-center", "fp-spawn-a", "base-a", "uplink-close", "armory-close", "hero-ref", "shadow-spawn"]
VARIANTS = [("current", "Current"), ("A", "A  Neon Night"), ("B", "B  Golden Hour Cyber"), ("C", "C  Clean Stylized")]


def font(size):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def tile(path, w, h, label, f):
    if os.path.exists(path):
        im = Image.open(path).convert("RGB").resize((w, h), Image.LANCZOS)
    else:
        im = Image.new("RGB", (w, h), (40, 40, 40))
        label += " (missing)"
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, w, f.size + 12], fill=(0, 0, 0))
    d.text((8, 5), label, fill=(255, 255, 255), font=f)
    return im


def main(root):
    w, h = 960, 540
    f = font(26)
    for v in VIEWS:
        sheet = Image.new("RGB", (w * len(VARIANTS), h))
        for i, (key, name) in enumerate(VARIANTS):
            sheet.paste(tile(os.path.join(root, "%s_%s.png" % (v, key)), w, h, "%s  |  %s" % (name, v), f), (i * w, 0))
        sheet.save(os.path.join(root, "sheet_%s.jpg" % v), quality=85)
    ow, oh = 480, 270
    fs = font(16)
    over = Image.new("RGB", (ow * len(VARIANTS), oh * len(VIEWS)))
    for r, v in enumerate(VIEWS):
        for c, (key, name) in enumerate(VARIANTS):
            over.paste(tile(os.path.join(root, "%s_%s.png" % (v, key)), ow, oh, "%s | %s" % (name, v), fs), (c * ow, r * oh))
    over.save(os.path.join(root, "overview.jpg"), quality=88)
    print("sheets ->", root)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "production/qa/evidence/lookdev")
