"""CMU mocap -> game rig retargeting for the locomotion layer (W13).

The data used in this project was obtained from mocap.cs.cmu.edu. The database
was created with funding from NSF EIA-0196217. (BVH conversion: Bruce Hahne /
cgspeed; mirror: github.com/una-dinosauria/cmu-mocap.)

Direction-based retarget: per frame, every game bone is swung (minimal rotation)
so it points the way the matching CMU segment points; the hips take the full
source pelvis frame; horizontal root travel is removed (in-place clips, the game
moves the body) and the hip height is scaled by the leg-length ratio. Cycles are
cut between two equal stride phases with linear drift correction (seamless loop);
legs are exaggerated slightly for the toon style. Upper-body clips (aim, shoot,
reload, casts) stay scripted and are layered on top by the AnimationTree filter.
"""
import math
import os

import numpy as np
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
CMU = os.path.join(HERE, ".cache", "cmu")

# clip -> (trial, kind, notes). kind: cycle | segment | reverse_cycle
CLIPS = {
    "idle": ("40_10", "segment", "wait for bus: 3 s calm stretch, drift-corrected loop"),
    "walk": ("16_15", "cycle", "walk"),
    "run": ("16_35", "cycle", "run/jog"),
    "run_back": ("16_15", "reverse_cycle", "walk cycle played in reverse"),
    "jump": ("16_01", "jump", "jump: take-off to just before landing"),
    "death": ("90_16", "fall", "fall on face: collapse to rest"),
}
# game bone -> (CMU joint, CMU child joint)
MAP = {
    "Spine": ("LowerBack", "Spine"), "Chest": ("Spine", "Spine1"), "UpperChest": ("Spine1", "Neck"),
    "Neck": ("Neck", "Head"), "Head": ("Head", "Head_End"),
}
for _s, _c in (("L", "Left"), ("R", "Right")):
    MAP.update({
        "UpperLeg_" + _s: (_c + "UpLeg", _c + "Leg"), "LowerLeg_" + _s: (_c + "Leg", _c + "Foot"),
        "Foot_" + _s: (_c + "Foot", _c + "ToeBase"),
        "Clavicle_" + _s: (_c + "Shoulder", _c + "Arm"), "UpperArm_" + _s: (_c + "Arm", _c + "ForeArm"),
        "LowerArm_" + _s: (_c + "ForeArm", _c + "Hand"),
    })
ORDER = ["Spine", "Chest", "UpperChest", "Neck", "Head", "UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R",
         "LowerLeg_R", "Foot_R", "Clavicle_L", "UpperArm_L", "LowerArm_L", "Clavicle_R", "UpperArm_R", "LowerArm_R"]
EXAGGERATE = {"UpperLeg_L": 1.15, "UpperLeg_R": 1.15, "LowerLeg_L": 1.1, "LowerLeg_R": 1.1}


class Bvh:
    def __init__(self, path):
        self.names, self.parent, self.offset, self.chans = [], [], [], []
        lines = open(path).read().split("\n")
        stack, i = [], 0
        while not lines[i].strip().startswith("MOTION"):
            t = lines[i].split()
            if t and t[0] in ("ROOT", "JOINT", "End"):
                name = t[1] if t[0] != "End" else self.names[stack[-1]] + "_End"
                self.names.append(name)
                self.parent.append(stack[-1] if stack else -1)
                self.chans.append([])
                self.offset.append(None)
                stack.append(len(self.names) - 1)
            elif t and t[0] == "OFFSET":
                self.offset[stack[-1]] = np.array([float(x) for x in t[1:4]])
            elif t and t[0] == "CHANNELS":
                self.chans[stack[-1]] = t[2:]
            elif t and t[0] == "}":
                stack.pop()
            i += 1
        self.frame_time = float(lines[i + 2].split()[-1])
        data = [l.split() for l in lines[i + 3:] if l.strip()]
        self.motion = np.array(data, dtype=np.float64)
        self.index = {n: k for k, n in enumerate(self.names)}

    def positions(self):
        """World joint positions, shape (frames, joints, 3)."""
        F = len(self.motion)
        G = [None] * len(self.names)
        P = np.zeros((F, len(self.names), 3))
        col = 0
        for j, name in enumerate(self.names):
            R = np.tile(np.eye(3), (F, 1, 1))
            t = np.tile(self.offset[j], (F, 1))
            for c in self.chans[j]:
                v = self.motion[:, col]
                col += 1
                if c.endswith("position"):
                    t[:, "XYZ".index(c[0])] += v
                else:
                    R = R @ _rot(c[0], np.radians(v))
            p = self.parent[j]
            if p < 0:
                G[j] = (R, t)
            else:
                Rp, tp = G[p]
                G[j] = (Rp @ R, tp + np.einsum("fij,fj->fi", Rp, t))
            P[:, j] = G[j][1]
        return P

    def rest(self):
        P = np.zeros((len(self.names), 3))
        for j in range(len(self.names)):
            p = self.parent[j]
            P[j] = self.offset[j] + (P[p] if p >= 0 else 0)
        return P


def _rot(axis, a):
    c, s = np.cos(a), np.sin(a)
    o, z = np.ones_like(a), np.zeros_like(a)
    if axis == "X":
        m = [[o, z, z], [z, c, -s], [z, s, c]]
    elif axis == "Y":
        m = [[c, z, s], [z, o, z], [-s, z, c]]
    else:
        m = [[c, -s, z], [s, c, z], [z, z, o]]
    return np.moveaxis(np.array(m), (0, 1), (-2, -1))


def _resample(P, a, b, n):
    """n frames over source frames [a, b] (inclusive end), linear."""
    out = []
    for i in range(n + 1):
        x = a + (b - a) * i / n
        f = int(math.floor(x))
        t = x - f
        f2 = min(f + 1, len(P) - 1)
        out.append(P[f] * (1 - t) + P[f2] * t)
    return np.array(out)


class Clip:
    """Source joint positions for one game clip, already cut, aligned and in-place."""

    def __init__(self, name, step):
        trial, kind, _ = CLIPS[name]
        bvh = Bvh(os.path.join(CMU, trial + ".bvh"))
        self.bvh = bvh
        ix = bvh.index
        P = bvh.positions()
        rest = bvh.rest()
        self.leg_len = np.linalg.norm(rest[ix["LeftUpLeg"]] - rest[ix["LeftFoot"]]) + np.linalg.norm(
            rest[ix["LeftUpLeg"]] - rest[ix["LeftLeg"]]) * 0
        self.leg_len = np.linalg.norm(rest[ix["LeftUpLeg"]] - rest[ix["LeftLeg"]]) + np.linalg.norm(
            rest[ix["LeftLeg"]] - rest[ix["LeftFoot"]])
        self.rest_hip_h = rest[ix["Hips"]][1] - min(rest[ix["LeftFoot"]][1], rest[ix["RightFoot"]][1])
        fps_src = 1.0 / bvh.frame_time
        hop = fps_src / 30.0
        root = P[:, ix["Hips"]].copy()
        if kind in ("cycle", "reverse_cycle"):
            left = P[:, ix["LeftUpLeg"]] - P[:, ix["RightUpLeg"]]
            fwd = np.cross(left, np.array([0, 1.0, 0]))
            fwd /= np.linalg.norm(fwd, axis=1, keepdims=True)
            sig = np.einsum("fi,fi->f", P[:, ix["LeftFoot"]] - P[:, ix["RightFoot"]], fwd)
            s0 = sig - sig.mean()
            lags = range(int(0.4 * fps_src), min(int(1.8 * fps_src), len(s0) // 2 + int(0.4 * fps_src)))
            ac = [np.dot(s0[:-L], s0[L:]) / (len(s0) - L) for L in lags]
            period = list(lags)[int(np.argmax(ac))]
            top = [i for i in range(3, len(sig) - 3) if sig[i] == sig[i - 3:i + 4].max() and sig[i] > 0.5 * sig.max()]
            top.sort(key=lambda i: abs(i - len(sig) // 2))
            a = top[0]
            b = a + period if a + period < len(sig) - 2 else a - period
            lo_, hi_ = max(0, b - 8), min(len(sig), b + 9)
            b = lo_ + int(np.argmax(sig[lo_:hi_]))
            a, b = min(a, b), max(a, b)
        elif kind == "segment":
            speed = np.linalg.norm(np.diff(root[:, [0, 2]], axis=0), axis=1)
            win = int(3.0 * fps_src)
            cs = np.convolve(speed, np.ones(win), "valid")
            a = int(np.argmin(cs[: len(cs) // 2])) + 1
            b = a + win
        elif kind == "jump":
            ground = min(P[:, ix["LeftToeBase"], 1].min(), P[:, ix["RightToeBase"], 1].min())
            low = np.minimum(P[:, ix["LeftToeBase"], 1], P[:, ix["RightToeBase"], 1]) - ground
            off = np.where(low > 0.8)[0]
            a = max(0, off[0] - int(0.15 * fps_src))
            b = off[-1]
        else:  # fall
            h = root[:, 1]
            drop = np.where(h < h[:60].mean() - 0.15 * (h[:60].mean() - h.min()))[0]
            a = max(0, drop[0] - int(0.25 * fps_src))
            settle = np.where(h < h.min() + 0.05 * (h[:60].mean() - h.min()))[0]
            b = min(len(h) - 1, settle[0] + int(0.6 * fps_src))
        n = max(2, int(round((b - a) / hop / step)))
        Q = _resample(P, a, b, n)
        # Alignment: mean pelvis heading -> Blender +Y, Y up -> +Z.
        lft = (Q[:, ix["LeftUpLeg"]] - Q[:, ix["RightUpLeg"]]).mean(axis=0)
        lft[1] = 0
        lft /= np.linalg.norm(lft)
        up = np.array([0, 1.0, 0])
        fw = np.cross(lft, up)
        Bs = np.stack([lft, up, fw], axis=1)
        Bt = np.array([[-1.0, 0, 0], [0, 0, 1], [0, 1, 0]]).T
        A = Bt @ Bs.T
        r0 = Q[:, ix["Hips"]].copy()
        if kind in ("cycle", "reverse_cycle", "segment"):
            # Remove travel (keep sway): subtract the linear root path; drift-correct the loop.
            t = np.linspace(0, 1, len(Q))[:, None]
            lin = r0[0] * (1 - t) + r0[-1] * t
            travel = lin.copy()
            travel[:, 1] = 0
            Q = Q - travel[:, None, :]
            rel = Q - Q[:, ix["Hips"]][:, None, :]
            drift = rel[-1] - rel[0]
            Q = Q - (t[:, :, None] * drift[None])
            self.speed = float(np.linalg.norm((r0[-1] - r0[0])[[0, 2]])) / (len(Q) - 1) * 30.0 * step
        else:
            Q = Q - np.array([r0[0][0], 0, r0[0][2]])[None, None, :]
            self.speed = 0.0
        if kind == "reverse_cycle":
            Q = Q[::-1]
        if kind == "jump":
            ground = min(P[:, ix["LeftToeBase"], 1].min(), P[:, ix["RightToeBase"], 1].min())
        else:
            ground = min(Q[:, ix["LeftFoot"], 1].min(), Q[:, ix["RightFoot"], 1].min()) - (
                rest[ix["LeftFoot"]][1] - min(rest[ix["LeftToeBase"]][1], rest[ix["LeftFoot"]][1]))
        self.kind = kind
        self.ix = ix
        self.Q = np.einsum("ij,fkj->fki", A, Q)
        self.ground_z = (A @ np.array([0, ground, 0]))[2]
        self.trial = trial
        self.loop = kind in ("cycle", "reverse_cycle", "segment")

    def frames(self):
        return len(self.Q)

    def pos(self, f, joint):
        if joint.endswith("_End") and joint not in self.ix:
            joint = joint[:-4]
        return Vector(self.Q[f, self.ix[joint]])


def retarget(h, poser, clip, f, scale, hips_rest_z, after=None):
    """Poses the game rig at clip frame f (Poser from hero_anims)."""
    p = poser
    p.reset()
    p.update()
    Q = clip
    # Hips: full pelvis frame + scaled height (in-place).
    lft = (Q.pos(f, "LeftUpLeg") - Q.pos(f, "RightUpLeg")).normalized()
    up = (Q.pos(f, "Spine1") - Q.pos(f, "Hips"))
    up = (up - lft * up.dot(lft)).normalized()
    fw = lft.cross(up)
    Fs = Matrix((-lft, fw, up)).transposed()  # columns: right(+X), fwd(+Y), up(+Z)
    hips = Q.pos(f, "Hips")
    dz = (hips.z - Q.ground_z) * scale - hips_rest_z
    if Q.kind in ("cycle", "reverse_cycle", "segment", "jump"):
        dz = min(dz, 0.02) if Q.kind != "jump" else min(dz, 0.0)
        dxy = Vector((hips.x * scale, hips.y * scale, 0)) if Q.kind != "jump" else Vector((0, 0, 0))
    else:
        dxy = Vector((hips.x * scale, hips.y * scale, 0))
    M = p.M("Hips")
    head = M.translation.copy()
    R = Fs.to_4x4()
    p.set_M("Hips", Matrix.Translation(head + dxy + Vector((0, 0, dz))) @ R @ Matrix.Translation(-head) @ M)
    for bone in ORDER:
        j0, j1 = MAP[bone]
        d = Q.pos(f, j1) - Q.pos(f, j0)
        if d.length < 1e-6:
            continue
        d.normalize()
        k = EXAGGERATE.get(bone, 1.0)
        if k != 1.0:
            down = Vector((0, 0, -1))
            d = (down + (d - down) * k).normalized()
        p.aim_bone(bone, d)
    if after is not None:
        after(p)
    p.update()
    p.key(f)
