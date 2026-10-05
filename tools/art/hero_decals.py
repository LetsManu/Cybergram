"""Painted helmet / mask detail for the W16 gen heroes (hero_paint `paint.post` hook).

Every function works on the composite context `c` that hero_paint.composite hands to
`paint.post`: object-space position `P` and normal `N` per texel (rest pose, metres,
X right, Y front, Z up), the flat colour blocks `base`, the painted albedo `alb`, the
mask channels `spec` (G) and `emit` (B), and the edge / convexity passes.

  region()     texels of given palette colours inside a height / box range
  wear()       chipped edge wear on convex edges (lighter metal under the paint)
  scratches()  thin wandering scratch lines, sparse clusters
  decal()      a planar-projected stencil (number, chevron, tally, pixel face)
  gloss()      spec (mask G) for glossy versus matte areas
Stencils are drawn with the shape helpers below (no font dependency).
"""
import numpy as np

from hero_hd import _fbm


def rgb(hexs):
    from build_hero import srgb
    return np.array(srgb(hexs)[:3], dtype=np.float32)


def region(c, colours, zmin=None, zmax=None, box=None, tol=0.02):
    """1.0 where the flat colour block is one of `colours` (hex, linear match) and the texel
    sits in [zmin, zmax] (metres) and inside `box` ((lo xyz), (hi xyz)) if given."""
    m = np.zeros(c["base"].shape[:2], dtype=bool)
    for h in colours:
        m |= np.all(np.abs(c["base"] - rgb(h)[None, None]) < tol, axis=-1)
    P = c["P"]
    if zmin is not None:
        m &= P[..., 2] >= zmin
    if zmax is not None:
        m &= P[..., 2] <= zmax
    if box is not None:
        lo, hi = np.array(box[0]), np.array(box[1])
        m &= np.all((P >= lo) & (P <= hi), axis=-1)
    return (m & c["inside"]).astype(np.float32)


def bounds(c, m):
    """Object-space bounding box (lo, hi) of the texels in mask `m`."""
    P = c["P"][m > 0.5]
    if len(P) == 0:
        return np.zeros(3), np.zeros(3)
    return np.percentile(P, 1, axis=0), np.percentile(P, 99, axis=0)


def wear(c, m, colour, amount=0.8, scale=70.0, seed=3.0):
    """Paint chips on convex edges: bare `colour` breaking through where an edge noise
    crosses a threshold (so the wear is broken, never a uniform outline)."""
    n = _fbm(c["P"] * scale + seed, 3)
    chip = np.clip((c["edge"] * c["convex"] * 1.6 + (n - 0.5) * 1.4 - 0.55) * 4.0, 0, 1) * m * amount
    col = rgb(colour)[None, None] * (0.75 + 0.35 * c["lit"][..., None])
    c["alb"] = c["alb"] * (1 - chip[..., None]) + col * chip[..., None]
    c["spec"] = np.maximum(c["spec"], chip * 0.7)
    return chip


def scratches(c, m, colour, density=0.35, scale=26.0, width=0.012, seed=7.0, strength=0.75):
    """Thin scratches: the zero contour of a stretched noise field, kept in sparse clusters."""
    P = c["P"]
    q = np.stack([P[..., 0] * 0.8 + P[..., 2] * 0.6, P[..., 1], P[..., 2] * 0.8 - P[..., 0] * 0.6], -1)
    f = _fbm(q * np.array([scale, scale, scale * 0.25]) + seed, 2)
    line = np.clip(1.0 - np.abs(f - 0.5) / width, 0, 1)
    cl = _fbm(P * 6.0 + seed * 2, 2)
    keep = np.clip((cl - (1.0 - density) * 0.9) / 0.1, 0, 1)
    s = line * keep * m * strength
    col = rgb(colour)[None, None]
    c["alb"] = c["alb"] * (1 - s[..., None]) + col * s[..., None]
    return s


def decal(c, img, centre, axis, up, size, m, colour, emit=False, depth=0.05, face=0.35, spec=None):
    """Projects the 2D stencil `img` (H x W floats 0..1, row 0 at the top) along `axis`
    onto the texels in mask `m` whose normal faces the axis. `size` = (w, h) metres."""
    a = np.array(axis, dtype=np.float32)
    a /= np.linalg.norm(a)
    u_ = np.array(up, dtype=np.float32)
    u_ = u_ - a * u_.dot(a)
    u_ /= np.linalg.norm(u_)
    r = np.cross(u_, a)
    d = c["P"] - np.array(centre, dtype=np.float32)[None, None]
    u = d @ r / size[0] + 0.5
    v = 0.5 - d @ u_ / size[1]
    ok = (u >= 0) & (u < 1) & (v >= 0) & (v < 1) & (np.abs(d @ a) < depth) & (c["N"] @ a > face) & (m > 0.5)
    ih, iw = img.shape
    iu = np.clip((u * iw).astype(np.int32), 0, iw - 1)
    iv = np.clip((v * ih).astype(np.int32), 0, ih - 1)
    s = np.where(ok, img[iv, iu], 0.0).astype(np.float32)
    col = rgb(colour)[None, None]
    if not emit:
        col = col * (0.8 + 0.25 * c["lit"][..., None])
    c["alb"] = c["alb"] * (1 - s[..., None]) + col * s[..., None]
    if emit:
        c["emit"] = np.maximum(c["emit"], s)
    if spec is not None:
        c["spec"] = c["spec"] * (1 - s) + spec * s
    return s


def flatten(c, m, amount=0.5):
    """Blends the painted albedo on `m` toward a clean two-band version of the flat colour
    (lit / shadow from the painted key only), removing AO and hatch blotches."""
    clean = c["base"] * (0.78 + 0.26 * c["lit"][..., None])
    a = (m * amount)[..., None]
    c["alb"] = c["alb"] * (1 - a) + clean * a


def gloss(c, m, value):
    """Sets mask G (spec / glint band) on `m`: glossy visors and lenses versus matte paint."""
    c["spec"] = c["spec"] * (1 - m) + value * m


# ---------------------------------------------------------------- stencil shapes
def canvas(w, h):
    return np.zeros((h, w), dtype=np.float32)


def rect(img, x0, y0, x1, y1, v=1.0):
    h, w = img.shape
    img[max(0, int(y0 * h)):int(y1 * h), max(0, int(x0 * w)):int(x1 * w)] = v
    return img


def poly(img, pts, v=1.0):
    """Fills a convex or concave polygon given in 0..1 canvas coordinates."""
    from PIL import Image, ImageDraw
    h, w = img.shape
    im = Image.new("L", (w, h), 0)
    ImageDraw.Draw(im).polygon([(x * w, y * h) for x, y in pts], fill=255)
    img[:] = np.maximum(img, np.asarray(im, dtype=np.float32) / 255.0 * v)
    return img


SEG = {"0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg", "6": "acdefg", "7": "abc",
       "8": "abcdefg", "9": "abcdfg"}


def digits(text, w=96, h=64, gap=0.08):
    """Stencil digits (seven-segment, with the stencil bridges cut)."""
    img = canvas(w, h)
    n = len(text)
    cw = 1.0 / n
    t = 0.16  # stroke
    for i, ch in enumerate(text):
        x0 = i * cw + cw * gap
        x1 = (i + 1) * cw - cw * gap
        tx = t * (x1 - x0) * 1.6
        ty = t * 0.6
        segs = {"a": (x0, 0, x1, ty), "d": (x0, 1 - ty, x1, 1), "g": (x0, 0.5 - ty / 2, x1, 0.5 + ty / 2),
                "f": (x0, 0, x0 + tx, 0.5), "b": (x1 - tx, 0, x1, 0.5), "e": (x0, 0.5, x0 + tx, 1),
                "c": (x1 - tx, 0.5, x1, 1)}
        for s in SEG.get(ch, ""):
            rect(img, *segs[s])
        bx = (x0 + x1) / 2  # stencil bridges
        rect(img, bx - 0.012, 0, bx + 0.012, 1, 0.0)
    return img


def chevron(w=64, h=48, t=0.3, n=1):
    img = canvas(w, h)
    for i in range(n):
        y = i * 0.34
        poly(img, [(0, y + t), (0.5, y), (1, y + t), (1, y + t + 0.22), (0.5, y + 0.22), (0, y + t + 0.22)])
    return img


def tally(n=5, w=96, h=48):
    img = canvas(w, h)
    for i in range(min(n, 4)):
        x = 0.08 + i * 0.2
        rect(img, x, 0.05, x + 0.07, 0.95)
    if n >= 5:
        poly(img, [(0.0, 0.8), (0.9, 0.12), (0.96, 0.25), (0.06, 0.93)])
    return img


def stripes(n=3, w=64, h=64, t=0.18):
    """Diagonal hazard stripes."""
    img = canvas(w, h)
    for i in range(-n, n + 1):
        x = i / n
        poly(img, [(x, 1), (x + t, 1), (x + t + 1, 0), (x + 1, 0)])
    return img


def pixel_face(rows):
    """A pixel-art face from strings ('#' = lit pixel), with a 1-pixel dark gap between
    pixels so the LED grid reads."""
    h, w = len(rows), len(rows[0])
    s = 8
    img = canvas(w * s, h * s)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch == "#":
                img[y * s + 1:(y + 1) * s - 1, x * s + 1:(x + 1) * s - 1] = 1.0
    return img


def holes(nx=4, ny=3, w=96, h=64, r=0.32):
    """A grid of round breathing holes."""
    img = canvas(w, h)
    yy, xx = np.mgrid[0:h, 0:w]
    for i in range(nx):
        for j in range(ny):
            cx, cy = (i + 0.5) / nx * w, (j + 0.5) / ny * h
            rr = r * min(w / nx, h / ny)
            img[(xx - cx) ** 2 + (yy - cy) ** 2 < rr * rr] = 1.0
    return img


def dent(w=64, h=48):
    """A dent: dark crescent (the shadowed lip) under a soft dark core."""
    img = canvas(w, h)
    yy, xx = np.mgrid[0:h, 0:w]
    u, v = (xx / w - 0.5) * 2, (yy / h - 0.5) * 2
    d = u * u + v * v
    img[d < 1.0] = 0.35
    img[(d < 1.0) & (d > 0.55) & (v > 0.0)] = 0.9
    return img
