#!/usr/bin/env python3
"""Tiles evidence PNGs into one sheet: contact_sheet.py out.png cols crop_w in1.png in2.png ...
Each input is centre-cropped to crop_w x 720 and labelled with its file name."""
import os
import sys

from PIL import Image, ImageDraw

out, cols, cw = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
ims = [Image.open(p).convert("RGB") for p in sys.argv[4:]]
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (cols * cw, rows * 720), "#0B1015")
for i, (p, im) in enumerate(zip(sys.argv[4:], ims)):
    x0 = (im.width - cw) // 2
    tile = im.crop((x0, 0, x0 + cw, 720))
    ImageDraw.Draw(tile).text((8, 8), os.path.basename(p)[:-4], fill="#ECE6D6")
    sheet.paste(tile, ((i % cols) * cw, (i // cols) * 720))
sheet.save(out)
