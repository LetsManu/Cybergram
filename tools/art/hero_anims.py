"""Keyframe clips for the rigged heroes (procedural authoring, project-owned).

Conventions (Blender space): X = character right, Y = forward, Z = up. A rotation
`(axis, deg)` is expressed in the rest axes of the armature and applied about the
bone head, relative to the parent's posed frame. +X swings a hanging limb forward
and leans an upright bone back; knees bend with -X.

Clip set (names are the contract with RiggedHeroModel.gd):
  loops : idle, walk, run, run_back, strafe_l, strafe_r, crouch_idle, crouch_walk,
          aim_up, aim_mid, aim_down
  shots : jump, shoot, hit, reload, cast_0, cast_1, cast_2, cast_3, death
"""
import math

import bpy
from mathutils import Matrix, Vector

AX = {"x": Vector((1, 0, 0)), "y": Vector((0, 1, 0)), "z": Vector((0, 0, 1))}
PITCH = {"aim_up": 70.0, "aim_mid": 0.0, "aim_down": -70.0}


def _k(h):
    return h.d["height"] / 1.85


def weapon_rest(h):
    """Armature-space weapon matrix at the mid aim pose (origin = right grip, +Y = barrel)."""
    st = h.d["stance"]
    k = _k(h)
    g = Vector(st["grip_r"]) * k
    return Matrix.Translation(g) @ _rot(st.get("weapon_rot", []))


def _rot(spec):
    R = Matrix.Identity(4)
    for ax, deg in spec:
        R = Matrix.Rotation(math.radians(deg), 4, AX[ax] if isinstance(ax, str) else Vector(ax)) @ R
    return R


class Poser:
    def __init__(self, h):
        self.h = h
        self.rig = h.rig
        self.pb = self.rig.pose.bones
        self.B = {b.name: b.matrix_local.to_3x3() for b in self.rig.data.bones}
        self.len = {b.name: b.length for b in self.rig.data.bones}
        self.k = _k(h)

    def reset(self):
        for pb in self.pb:
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)
            pb.scale = (1, 1, 1)

    def rot(self, bone, spec):
        R = _rot(spec).to_3x3()
        B = self.B[bone]
        self.pb[bone].rotation_quaternion = (B.inverted() @ R @ B).to_quaternion()

    def hips(self, offset):
        self.pb["Hips"].location = self.B["Hips"].inverted() @ Vector(offset)

    @staticmethod
    def update():
        bpy.context.view_layer.update()

    def M(self, bone):
        return self.pb[bone].matrix.copy()

    def set_M(self, bone, M):
        self.pb[bone].matrix = M
        self.update()

    def aim_bone(self, bone, direction):
        M = self.M(bone)
        head = M.translation.copy()
        cur = (M.to_3x3() @ Vector((0, 1, 0))).normalized()
        q = cur.rotation_difference(direction.normalized())
        self.set_M(bone, Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head) @ M)

    def ik(self, side, target, pole, hand_y=None, hand_n=None):
        up, lo, hand = "UpperArm_" + side, "LowerArm_" + side, "Hand_" + side
        S = self.M(up).translation
        l1, l2 = self.len[up], self.len[lo]
        to = target - S
        d = max(0.05, min(to.length, (l1 + l2) * 0.999))
        dr = to.normalized()
        ca = max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)))
        pole = Vector(pole).normalized()
        bend = pole - dr * pole.dot(dr)
        bend = bend.normalized() if bend.length > 1e-4 else Vector((0, 0, -1))
        elbow = S + dr * ca * l1 + bend * math.sqrt(1 - ca * ca) * l1
        self.aim_bone(up, elbow - S)
        self.aim_bone(lo, S + dr * d - self.M(lo).translation)
        if hand_y is not None:
            self.orient_hand(side, Vector(hand_y), Vector(hand_n))

    def orient_hand(self, side, yd, nd):
        bone = "Hand_" + side
        M = self.M(bone)
        n_loc = self.B[bone].inverted() @ self.h.palm[side]
        yc = M.to_3x3() @ Vector((0, 1, 0))
        nc = M.to_3x3() @ n_loc
        R = _frame(yd, nd) @ _frame(yc, nc).transposed()
        head = M.translation.copy()
        self.set_M(bone, Matrix.Translation(head) @ R.to_4x4() @ Matrix.Translation(-head) @ M)

    def key(self, frame):
        for pb in self.pb:
            pb.keyframe_insert("rotation_quaternion", frame=frame)
        self.pb["Hips"].keyframe_insert("location", frame=frame)


def _frame(y, n):
    y = y.normalized()
    n = (n - y * y.dot(n)).normalized()
    x = y.cross(n)
    return Matrix((x, y, n)).transposed()


def _new_action(rig, name):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    return act


# ---------------------------------------------------------------- body poses
def legs(p, ph, amp, knee, side_amp=0.0, crouch=0.0, back=False):
    """Gait at phase `ph` (rad). amp/knee in degrees; side_amp for strafes."""
    s = -1.0 if back else 1.0
    for i, side in enumerate(("L", "R")):
        sg = 1.0 if i == 0 else -1.0
        sw = math.sin(ph) * sg
        lift = max(0.0, math.cos(ph + (0.0 if i == 0 else math.pi)))
        thigh = 50 * crouch + s * sw * amp
        shin = -(85 * crouch) - lift * knee - 6
        if side_amp:
            p.rot("UpperLeg_" + side, [("x", 50 * crouch + lift * knee * 0.35), ("y", sw * side_amp)])
        else:
            p.rot("UpperLeg_" + side, [("x", thigh), ("y", -sg * 3)])
        p.rot("LowerLeg_" + side, [("x", shin)])
        p.rot("Foot_" + side, [("x", -(thigh + shin) * 0.6 if not side_amp else 35 * crouch)])


def torso(p, lean=0.0, twist=0.0, bob=0.0, breathe=0.0, roll=0.0):
    p.rot("Spine", [("x", -lean * 0.5 + breathe), ("z", twist * 0.5), ("y", roll)])
    p.rot("Chest", [("x", -lean * 0.5 + breathe * 0.5), ("z", twist * 0.5)])
    p.hips((0, 0, bob))


def loco_clip(h, name, frames, fn):
    p = Poser(h)
    _new_action(h.rig, name)
    for f in range(frames + 1):
        p.reset()
        fn(p, 2 * math.pi * f / frames, f)
        p.update()
        p.key(f)


# ---------------------------------------------------------------- upper body
def upper_pose(h, p, pitch=0.0, weapon_extra=None, left=None, chest=(), hold_left=True, frame_cb=None):
    """Aim pose: torso twist + pitch share, weapon on its pivot, IK both hands.
    `left` = (target, y, n) armature-space override for the free left hand."""
    st = h.d["stance"]
    k = p.k
    p.rot("UpperChest", [("z", st.get("twist", 0.0)), ("x", pitch * 0.3)] + list(chest))
    p.rot("Neck", [("z", -st.get("twist", 0.0) * 0.6), ("x", pitch * 0.2)])
    p.rot("Head", [("z", -st.get("twist", 0.0) * 0.4), ("x", pitch * 0.25)])
    p.rot("Clavicle_L", [("z", st.get("clav_l", 0.0))])
    p.update()
    piv = Vector(st["pivot"]) * k
    W = Matrix.Translation(piv) @ Matrix.Rotation(math.radians(pitch), 4, "X") @ Matrix.Translation(-piv) @ h.weapon_rest
    if weapon_extra is not None:
        W = W @ weapon_extra
    p.set_M("Weapon", W)
    Wm = p.M("Weapon")
    R3 = Wm.to_3x3()
    p.ik("R", Wm.translation.copy(), st["pole_r"], R3 @ Vector(st["hand_r_y"]), R3 @ Vector(st["hand_r_n"]))
    if left is not None:
        tgt, yd, nd = left
        p.ik("L", tgt, st["pole_l"], yd, nd)
    elif st.get("two_handed", True):
        p.ik("L", Wm @ Vector(st["grip_l"]), st["pole_l"], R3 @ Vector(st["hand_l_y"]), R3 @ Vector(st["hand_l_n"]))
    else:
        rest = st["left_free"]
        p.ik("L", Vector(rest[0]) * k, st["pole_l"], Vector(rest[1]), Vector(rest[2]))


def upper_clip(h, name, frames, fn):
    p = Poser(h)
    _new_action(h.rig, name)
    for f in range(frames + 1):
        p.reset()
        fn(p, f / max(frames, 1), f)
        p.update()
        p.key(f)


def _env(t, a, b):
    """0 -> 1 -> 0 bump over [a, b] (smoothstep in, out)."""
    if t <= a or t >= b:
        return 0.0
    x = (t - a) / (b - a)
    return math.sin(math.pi * x) ** 2 * 1.0 if x < 1 else 0.0


def _lerp_keys(keys, t):
    """keys: [(t, value tuple)] -> smooth interpolation."""
    if t <= keys[0][0]:
        return Vector(keys[0][1])
    for (t0, a), (t1, b) in zip(keys, keys[1:]):
        if t <= t1:
            x = (t - t0) / max(t1 - t0, 1e-6)
            x = x * x * (3 - 2 * x)
            return Vector(a).lerp(Vector(b), x)
    return Vector(keys[-1][1])


GESTURES = {
    # left-hand paths in metres (scaled by height), (pos, fingers dir, palm normal)
    "throw": [(0.0, None), (0.25, ((-0.25, -0.15, 1.75), (0, -0.3, 1), (1, 0, 0))),
              (0.55, ((-0.15, 0.55, 1.45), (0, 1, 0.2), (0, 0, -1))), (1.0, None)],
    "inject": [(0.0, None), (0.3, ((0.12, 0.30, 1.18), (1, 0.2, 0), (0, 0, -1))),
               (0.7, ((0.12, 0.28, 1.16), (1, 0.2, 0), (0, 0, -1))), (1.0, None)],
    "thrust": [(0.0, None), (0.3, ((-0.10, 0.62, 1.40), (0, 1, 0.1), (0, 0.2, 1))),
               (0.6, ((-0.10, 0.64, 1.42), (0, 1, 0.1), (0, 0.2, 1))), (1.0, None)],
    "raise": [(0.0, None), (0.35, ((-0.22, 0.15, 2.05), (0, 0, 1), (0, 1, 0))),
              (0.7, ((-0.22, 0.15, 2.05), (0, 0, 1), (0, 1, 0))), (1.0, None)],
    "sweep": [(0.0, None), (0.25, ((0.10, 0.45, 1.35), (1, 0.4, 0), (0, 1, 0))),
              (0.65, ((-0.55, 0.35, 1.40), (-1, 0.4, 0), (0, 1, 0))), (1.0, None)],
    "plant": [(0.0, None), (0.35, ((-0.20, 0.45, 0.85), (0, 0.3, -1), (0, 0, -1))),
              (0.65, ((-0.20, 0.45, 0.82), (0, 0.3, -1), (0, 0, -1))), (1.0, None)],
}


def cast_clip(h, name, gesture, frames=24, chest=()):
    st = h.d["stance"]
    keys = GESTURES[gesture]
    rest_left = st.get("left_free")

    def fn(p, t, f):
        lower = _env(t, 0.0, 1.0)
        extra = Matrix.Rotation(math.radians(-25 * lower), 4, "X")
        # Find the bracketing keys; None = the stance hand position.
        pts = []
        for kt, val in keys:
            if val is None:
                pts.append((kt, None))
            else:
                pts.append((kt, val))
        left = None
        known = [(kt, v) for kt, v in pts if v is not None]
        if known and known[0][0] <= t <= known[-1][0] or (known and _env(t, 0.0, 1.0) > 0.0):
            w = min(1.0, _env(t, 0.0, 1.0) * 1.6)
            pos = _lerp_keys([(kt, v[0]) for kt, v in known], t) * p.k
            yd = _lerp_keys([(kt, v[1]) for kt, v in known], t)
            nd = _lerp_keys([(kt, v[2]) for kt, v in known], t)
            if w < 1.0:
                p.reset()
                upper_pose(h, p, 0.0, extra)
                base = p.M("Hand_L").translation.copy()
                pos = base.lerp(pos, w)
            left = (pos, yd, nd)
        p.reset()
        ch = [(a, d * lower) for a, d in chest]
        upper_pose(h, p, 0.0, extra, left=left, chest=ch)

    upper_clip(h, name, frames, fn)


def mocap_clips(h):
    """CMU mocap locomotion (tools/art/mocap.py); returns {clip: (trial, speed m/s)}."""
    import mocap
    p0 = Poser(h)
    p0.reset()
    upper_pose(h, p0, 0.0)
    off = p0.M("Hand_R").inverted() @ p0.M("Weapon")
    leg = (h.jh("UpperLeg_L") - h.jh("LowerLeg_L")).length + (h.jh("LowerLeg_L") - h.jh("Foot_L")).length
    hips_rest = h.jh("Hips").z
    info = {}
    for name in mocap.CLIPS:
        clip = mocap.Clip(name, 1)
        scale = leg / clip.leg_len
        p = Poser(h)
        _new_action(h.rig, name)
        after = (lambda q: q.set_M("Weapon", q.M("Hand_R") @ off)) if name == "death" else None
        for f in range(clip.frames()):
            mocap.retarget(h, p, clip, f, scale, hips_rest - h.jh("Foot_L").z * 0.0, after)
        h.rig.animation_data.action = None
        info[name] = {"trial": clip.trial, "speed": round(clip.speed * scale, 3), "frames": clip.frames()}
    return info


def author_all(h, use_mocap=True):
    st = h.d["stance"]
    mocap_info = mocap_clips(h) if use_mocap else {}
    skip = set(mocap_info)

    def loco_clip_m(h, name, frames, fn):
        if name not in skip:
            loco_clip(h, name, frames, fn)
    sty = h.d.get("gait", {})
    run_amp = sty.get("run_amp", 38)
    lean = sty.get("lean", 8)

    def idle(p, ph, f):
        legs(p, 0, 0, 0)
        p.rot("UpperLeg_L", [("y", 4), ("z", -6)])
        p.rot("UpperLeg_R", [("y", -4), ("z", 8)])
        torso(p, lean=2, bob=math.sin(ph) * 0.006 * p.k, breathe=math.sin(ph) * 1.2)
    loco_clip_m(h, "idle", 60, idle)
    loco_clip_m(h, "walk", 32, lambda p, ph, f: (legs(p, ph, 24, 30),
                                               torso(p, lean=3, twist=math.sin(ph) * 5, bob=-abs(math.cos(ph)) * 0.02 * p.k)))
    loco_clip_m(h, "run", 20, lambda p, ph, f: (legs(p, ph, run_amp, 70),
                                              torso(p, lean=lean, twist=math.sin(ph) * 8, bob=-abs(math.cos(ph)) * 0.045 * p.k)))
    loco_clip_m(h, "run_back", 22, lambda p, ph, f: (legs(p, ph, 26, 45, back=True),
                                                   torso(p, lean=-3, bob=-abs(math.cos(ph)) * 0.03 * p.k)))
    loco_clip_m(h, "strafe_l", 22, lambda p, ph, f: (legs(p, ph, 0, 45, side_amp=18),
                                                   torso(p, lean=4, roll=math.sin(ph) * 3, bob=-abs(math.cos(ph)) * 0.03 * p.k)))
    loco_clip_m(h, "strafe_r", 22, lambda p, ph, f: (legs(p, ph + math.pi, 0, 45, side_amp=18),
                                                   torso(p, lean=4, roll=-math.sin(ph) * 3, bob=-abs(math.cos(ph)) * 0.03 * p.k)))
    loco_clip_m(h, "crouch_idle", 40, lambda p, ph, f: (legs(p, 0, 0, 0, crouch=1.0),
                                                      torso(p, lean=14, bob=-0.36 * p.k + math.sin(ph) * 0.004)))
    loco_clip_m(h, "crouch_walk", 30, lambda p, ph, f: (legs(p, ph, 18, 25, crouch=1.0),
                                                      torso(p, lean=16, bob=-0.36 * p.k - abs(math.cos(ph)) * 0.015)))

    def jump(p, ph, f):
        t = f / 14.0
        tuck = min(1.0, t * 2.0)
        for side, a, kn in (("L", 45, -75), ("R", 20, -40)):
            p.rot("UpperLeg_" + side, [("x", a * tuck)])
            p.rot("LowerLeg_" + side, [("x", kn * tuck)])
            p.rot("Foot_" + side, [("x", 25 * tuck)])
        torso(p, lean=6 * tuck, bob=0.05 * tuck * p.k)
    loco_clip_m(h, "jump", 14, jump)

    for name, pitch in PITCH.items():
        upper_clip(h, name, 1, lambda p, t, f, pitch=pitch: upper_pose(h, p, pitch))

    def shoot(p, t, f):
        kick = math.exp(-t * 5.0) * (1.0 if f > 0 else 0.0)
        p.rot("Chest", [("x", 4 * kick), ("z", 2 * kick)])
    upper_clip(h, "shoot", 6, shoot)

    def hit(p, t, f):
        e = math.sin(math.pi * t)
        p.rot("Chest", [("x", 14 * e), ("z", -8 * e), ("y", 6 * e)])
    upper_clip(h, "hit", 9, hit)

    mag = Vector(st["mag"])

    def reload(p, t, f):
        tilt = _env(t, 0.0, 1.0)
        extra = Matrix.Rotation(math.radians(-20 * tilt), 4, "X") @ Matrix.Rotation(math.radians(28 * tilt), 4, "Y")
        upper_pose(h, p, 0.0, extra)
        Wm = p.M("Weapon")
        R3 = Wm.to_3x3()
        at_mag = Wm @ mag
        belt = Vector(st.get("belt", (-0.18, 0.12, 1.0))) * p.k
        keys = [(0.0, p.M("Hand_L").translation.copy()), (0.2, at_mag), (0.38, at_mag + R3 @ Vector((0, 0, -0.12))),
                (0.5, belt), (0.68, at_mag + R3 @ Vector((0, 0, -0.1))), (0.8, at_mag), (1.0, p.M("Hand_L").translation.copy())]
        pos = _lerp_keys([(kt, tuple(v)) for kt, v in keys], t)
        p.ik("L", pos, st["pole_l"], R3 @ Vector((0.3, 0.3, 1)), R3 @ Vector((1, 0, 0)))
    upper_clip(h, "reload", 40, reload)

    for i, (gesture, chest) in enumerate(h.d["casts"]):
        cast_clip(h, "cast_%d" % i, gesture, 24 if i < 3 else 36, chest)

    # Death: buckle and fall backward; the weapon stays in the right hand.
    p0 = Poser(h)
    p0.reset()
    upper_pose(h, p0, 0.0)
    off = p0.M("Hand_R").inverted() @ p0.M("Weapon")

    def death(p, t, f):
        e = min(1.0, t * 1.25)
        fall = e * e
        p.hips((0, -0.25 * fall * p.k, -0.82 * fall * p.k * min(1.0, e * 1.3)))
        p.rot("Hips", [("x", 80 * fall)])
        buck = math.sin(min(1.0, e * 2.0) * math.pi * 0.5)
        for side, a in (("L", 1.0), ("R", 0.6)):
            p.rot("UpperLeg_" + side, [("x", (30 * buck - 20 * fall) * a), ("z", 8 * a)])
            p.rot("LowerLeg_" + side, [("x", -60 * buck * a + 40 * fall * a)])
        p.rot("Spine", [("x", 10 * fall)])
        p.rot("UpperChest", [("x", 15 * fall), ("y", -10 * fall)])
        p.rot("Head", [("x", 25 * fall), ("z", 30 * fall)])
        p.update()
        chest = p.M("UpperChest")
        k = p.k
        p.ik("R", chest @ Vector((0.45, 0.2, 0.1)) * 1.0 if False else chest.to_3x3() @ Vector((0.42 * k, 0.15 * k, 0.15 * k)) + chest.translation,
             (1, 0, -1))
        p.ik("L", chest.to_3x3() @ Vector((-0.45 * k, 0.1 * k, 0.25 * k)) + chest.translation, (-1, 0, -1))
        p.set_M("Weapon", p.M("Hand_R") @ off)
    if "death" not in skip:
        upper_clip(h, "death", 36, death)
    h.rig.animation_data.action = None
    Poser(h).reset()
    return mocap_info
