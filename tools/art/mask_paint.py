"""Painted mask / helmet detail for the W16 gen pipeline (W16-HERO-B).

Used from a hero's `paint["detail"]` hook (hero_paint.composite calls it with a ctx
dict before the painted light). Every helper works on the bake pixels of one colour
block (a "region": e.g. Vesper's porcelain), in a normalised front projection of
that block: u = -1..1 across (hero's right = +u), v = -1..1 bottom to top.

ctx keys used: P (object-space position per pixel), N (normal), base (flat colour,
edited in place), emit, spec (added to the mask G), noink (no colour-border ink),
aoe (AO, bevel edge, pointiness), cov (island coverage), k (height / 1.85).

All randomness is seeded: the same def paints the same texture every build.
"""
import numpy as np


def rgb(hex_str):
    """'#RRGGBB' -> float RGB, stored as-is (same convention as build_hero.srgb)."""
    h = hex_str.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


class Region:
    """Pixels of one colour block (all colours in `hexes`), optionally limited to z >= zmin
    and to front-facing normals (ny >= front). Holds the normalised u, v of each pixel."""

    def __init__(self, ctx, hexes, zmin=None, zmax=None, front=None, tol=0.02, box=None, proj="xz", xmin=None):
        base = ctx["base"]
        sel = ctx["cov"] > 0.5
        near = np.zeros(sel.shape, dtype=bool)
        for hx in hexes:
            near |= np.abs(base - rgb(hx)[None, None]).max(-1) < tol
        sel &= near
        P = ctx["P"]
        if zmin is not None:
            sel &= P[..., 2] >= zmin
        if zmax is not None:
            sel &= P[..., 2] <= zmax
        if front is not None:
            sel &= ctx["N"][..., 1] >= front
        if xmin is not None:  # side projections: one side only (sign of xmin picks it)
            sel &= (P[..., 0] * np.sign(xmin)) >= abs(xmin)
        self.ctx = ctx
        self.ij = np.nonzero(sel)
        self.p = P[self.ij]
        self.n = ctx["N"][self.ij]
        a = 0 if proj == "xz" else 1  # "yz": side view, u = +1 at the front
        if len(self.p) == 0:
            self.box, self.cx, self.hx, self.cz, self.hz = (0, 1, 0, 1), 0.5, 0.5, 0.5, 0.5
            self.u = self.v = np.zeros(0)
            return
        if box is None:
            lo, hi = np.percentile(self.p, 0.5, axis=0), np.percentile(self.p, 99.5, axis=0)
            box = (lo[a], hi[a], lo[2], hi[2])
        self.box = box
        x0, x1, z0, z1 = box
        self.cx, self.hx = (x0 + x1) / 2, max((x1 - x0) / 2, 1e-4)
        self.cz, self.hz = (z0 + z1) / 2, max((z1 - z0) / 2, 1e-4)
        self.u = (self.p[:, a] - self.cx) / self.hx
        self.v = (self.p[:, 2] - self.cz) / self.hz

    def __len__(self):
        return len(self.u)

    def uv_of(self, x, z):
        return (x - self.cx) / self.hx, (z - self.cz) / self.hz

    # -------------------------------------------------------------- painting
    def paint(self, w, color, spec=None, noink=None, emit=None):
        """Blends `color` into the base where weight w (per region pixel, 0..1) is set."""
        if len(self) == 0:
            return
        w = np.clip(w, 0, 1).astype(np.float32)
        b = self.ctx["base"]
        cur = b[self.ij]
        b[self.ij] = cur * (1 - w[:, None]) + np.asarray(color, dtype=np.float32)[None] * w[:, None]
        if spec is not None:
            s = self.ctx["spec"]
            s[self.ij] = np.maximum(s[self.ij] * (1 - w), spec * w)
        if noink is not None:
            ni = self.ctx["noink"]
            ni[self.ij] = np.maximum(ni[self.ij], noink * w)
        if emit is not None:
            e = self.ctx["emit"]
            e[self.ij] = np.maximum(e[self.ij], emit * w)

    def sheen(self, value):
        """Glossy finish: a constant spec level over the region (the shader's hard band)."""
        s = self.ctx["spec"]
        s[self.ij] = np.maximum(s[self.ij], value)

    def line(self, pts, width, aa=None):
        """Weight of a polyline in (u, v), `width` in u units (anti-aliased)."""
        d = polyline_dist(self.u, self.v * self.hz / self.hx, [(a, b * self.hz / self.hx) for a, b in pts])
        aa = aa if aa is not None else width * 0.35
        return np.clip((width / 2 - d) / max(aa, 1e-5) + 0.5, 0, 1)

    def blob(self, u0, v0, ru, rv, rot=0.0, sharp=0.15):
        """Soft-edged ellipse (diamond if rot=45 and sharp is small)."""
        c, s = np.cos(np.radians(rot)), np.sin(np.radians(rot))
        du, dv = self.u - u0, (self.v - v0) * self.hz / self.hx
        a, b = du * c + dv * s, -du * s + dv * c
        r = np.sqrt((a / ru) ** 2 + (b / (rv * self.hz / self.hx)) ** 2)
        return np.clip((1 - r) / sharp, 0, 1)

    def diamond(self, u0, v0, ru, rv, sharp=0.12):
        du, dv = np.abs(self.u - u0) / ru, np.abs(self.v - v0) / rv
        return np.clip((1 - (du + dv)) / sharp, 0, 1)

    def edge(self):
        """Convex-edge factor (bevel pass) per region pixel."""
        aoe = self.ctx["aoe"][self.ij]
        e = np.clip((aoe[:, 1] - 0.05) / 0.18, 0, 1)
        cvx = np.clip((aoe[:, 2] - 0.5) * 6 + 0.5, 0, 1)
        return e * cvx

    def noise(self, freq, seed=0):
        return _vnoise(self.p * freq / max(self.ctx["k"], 1e-3) + seed * 17.31)

    def edge_wear(self, color, amount=1.0, freq=60.0, seed=1, spec=None):
        """Chipped paint on the convex edges, broken up by noise."""
        n = self.noise(freq, seed)
        w = np.clip((self.edge() * 1.4 + (n - 0.55) * 2.2) * amount, 0, 1)
        w = np.where(w > 0.5, 1.0, w * 0.4)
        self.paint(w, color, spec=spec, noink=1.0)

    def scratches(self, color, count=24, length=0.18, width=0.012, seed=3, strength=0.6, area=None):
        """Short straight scuffs at random places (u, v in `area` = (u0, u1, v0, v1))."""
        rng = np.random.default_rng(seed)
        u0, u1, v0, v1 = area or (-0.95, 0.95, -0.95, 0.95)
        w = np.zeros(len(self), dtype=np.float32)
        for _ in range(count):
            a = np.array([rng.uniform(u0, u1), rng.uniform(v0, v1)])
            ang = rng.uniform(-0.9, 0.9) + (np.pi if rng.random() < 0.5 else 0.0)
            L = length * rng.uniform(0.4, 1.0)
            b = a + L * np.array([np.cos(ang), np.sin(ang)])
            mid = (a + b) / 2 + rng.normal(0, L * 0.06, 2)
            w = np.maximum(w, self.line([tuple(a), tuple(mid), tuple(b)], width * rng.uniform(0.6, 1.0)))
        self.paint(w * strength, color, noink=1.0)


def crack(start, end, seed, steps=7, jitter=0.12, branches=2, blen=0.35):
    """Jagged crack polyline(s) from start to end in (u, v); returns a list of polylines."""
    rng = np.random.default_rng(seed)
    a, b = np.array(start, dtype=float), np.array(end, dtype=float)
    d = b - a
    nrm = np.array([-d[1], d[0]]) / max(np.linalg.norm(d), 1e-6)
    pts = [a]
    for i in range(1, steps):
        t = i / steps
        pts.append(a + d * t + nrm * rng.uniform(-jitter, jitter) * np.linalg.norm(d) * 0.6)
    pts.append(b)
    out = [[tuple(p) for p in pts]]
    for _ in range(branches):
        i = int(rng.integers(1, steps - 1))
        p = pts[i]
        side = 1 if rng.random() < 0.5 else -1
        q = p + (d / max(np.linalg.norm(d), 1e-6) * 0.5 + nrm * side) * blen * rng.uniform(0.6, 1.0)
        mid = (p + q) / 2 + nrm * rng.uniform(-0.04, 0.04)
        out.append([tuple(p), tuple(mid), tuple(q)])
    return out


def polyline_dist(x, y, pts):
    d = np.full(x.shape, np.inf, dtype=np.float32)
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        ex, ey = bx - ax, by - ay
        L2 = ex * ex + ey * ey
        t = np.clip(((x - ax) * ex + (y - ay) * ey) / max(L2, 1e-12), 0, 1)
        d = np.minimum(d, np.hypot(x - ax - t * ex, y - ay - t * ey))
    return d


def _vnoise(P):
    """Smooth value noise in 3D (deterministic hash)."""
    i = np.floor(P)
    f = P - i
    f = f * f * (3 - 2 * f)

    def hsh(c):
        h = np.sin(c[..., 0] * 127.1 + c[..., 1] * 311.7 + c[..., 2] * 74.7) * 43758.5453
        return h - np.floor(h)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * \
                    (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * hsh(i + np.array([dx, dy, dz]))
    return out
