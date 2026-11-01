"""Rebuild the A (male) / C (female) survivor bodies as soft, clay-like chibi models.

Run from the project root:  python tools/build_human_models.py
Pure Python 3 standard library; no Blender needed.

* Reads the current assets/characters/humans/<gender>.glb and keeps its hair
  meshes untouched (they are fitted to the head and were refined separately by
  tools/refine_human_hair.py).
* Regenerates everything else: head details, jacket/shirt, sleeves, hands,
  trousers and boots, following the A/C reference (rounded clay forms, open
  field jacket with collar and pockets for A, collared shirt for C).
* Mesh names keep the "<Bone>__<part>" convention used by human_visual.gd and
  material names keep the appearance parts (hair/skin/shirt/pants) so the
  in-game colour pickers still work.
"""
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/characters/humans"

# ----------------------------------------------------------------- materials
# Linear-space base colours. hair/skin/shirt/pants are recoloured at runtime.
MATERIALS = {
    "male": {
        "skin": (0.72, 0.46, 0.29), "hair": (0.12, 0.064, 0.032),
        "shirt": (0.23, 0.28, 0.14), "pants": (0.46, 0.39, 0.27),
        "boots": (0.10, 0.062, 0.040), "sole": (0.035, 0.03, 0.028),
        "inner": (0.05, 0.05, 0.048), "eyes": (0.018, 0.015, 0.014),
        "shine": (0.9, 0.9, 0.9), "mouth": (0.32, 0.10, 0.065),
        "buttons": (0.06, 0.07, 0.06), "cheek": (0.85, 0.38, 0.30),
    },
    "female": {
        "skin": (0.72, 0.46, 0.29), "hair": (0.055, 0.042, 0.038),
        "shirt": (0.20, 0.29, 0.34), "pants": (0.11, 0.12, 0.13),
        "boots": (0.10, 0.062, 0.040), "sole": (0.035, 0.03, 0.028),
        "inner": (0.05, 0.05, 0.048), "eyes": (0.018, 0.015, 0.014),
        "shine": (0.9, 0.9, 0.9), "mouth": (0.32, 0.10, 0.065),
        "buttons": (0.07, 0.09, 0.10), "cheek": (0.85, 0.38, 0.30),
    },
}
ROUGHNESS = {"shine": 0.25, "eyes": 0.3, "buttons": 0.5}


# ------------------------------------------------------------------ geometry
def v_add(a, b): return (a[0]+b[0], a[1]+b[1], a[2]+b[2])
def v_sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def v_mul(a, s): return (a[0]*s, a[1]*s, a[2]*s)
def v_dot(a, b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
def v_cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def v_len(a): return math.sqrt(v_dot(a, a))
def v_norm(a):
    length = v_len(a)
    return (0.0, 1.0, 0.0) if length < 1e-9 else v_mul(a, 1.0/length)


def rotation(rx=0.0, ry=0.0, rz=0.0):
    """XYZ euler (radians) -> function rotating a vector."""
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    def apply(p):
        x, y, z = p
        y, z = y*cx-z*sx, y*sx+z*cx
        x, z = x*cy+z*sy, -x*sy+z*cy
        x, y = x*cz-y*sz, x*sz+y*cz
        return (x, y, z)
    return apply


class Mesh:
    def __init__(self):
        self.v = []
        self.f = []

    def extend(self, other):
        base = len(self.v)
        self.v.extend(other.v)
        self.f.extend((a+base, b+base, c+base) for a, b, c in other.f)
        return self

    def transformed(self, rot=(0, 0, 0), pivot=(0, 0, 0), offset=(0, 0, 0), scale=(1, 1, 1)):
        r = rotation(*rot)
        m = Mesh()
        for p in self.v:
            local = v_sub(p, pivot)
            local = (local[0]*scale[0], local[1]*scale[1], local[2]*scale[2])
            m.v.append(v_add(v_add(r(local), pivot), offset))
        m.f = list(self.f)
        return m

    def mirrored_x(self):
        m = Mesh()
        m.v = [(-x, y, z) for x, y, z in self.v]
        m.f = [(a, c, b) for a, b, c in self.f]
        return m

    def normals(self):
        acc = [[0.0, 0.0, 0.0] for _ in self.v]
        for a, b, c in self.f:
            n = v_cross(v_sub(self.v[b], self.v[a]), v_sub(self.v[c], self.v[a]))
            for i in (a, b, c):
                acc[i][0] += n[0]; acc[i][1] += n[1]; acc[i][2] += n[2]
        return [v_norm(tuple(n)) for n in acc]


def superellipse(t, a, b, n):
    c, s = math.cos(t), math.sin(t)
    x = a*math.copysign(abs(c)**(2.0/n), c)
    z = b*math.copysign(abs(s)**(2.0/n), s)
    return x, z


def loft(sections, segments=32, cap_bottom=True, cap_top=True):
    """Sections: (center xyz, half width, half depth, exponent[, front_bulge]).

    Rings are horizontal; the front (-Z) can be pushed forward with front_bulge.
    Faces wind counter-clockwise seen from outside (glTF front faces)."""
    m = Mesh()
    for sec in sections:
        (cx, cy, cz), a, b, n = sec[:4]
        bulge = sec[4] if len(sec) > 4 else 0.0
        for i in range(segments):
            t = 2*math.pi*i/segments
            x, z = superellipse(t, a, b, n)
            if bulge and z < 0:
                z -= bulge*max(0.0, -math.sin(t))**2*max(0.0, 1-abs(x)/max(a, 1e-6))
            m.v.append((cx+x, cy, cz+z))
    rings = len(sections)
    for r in range(rings-1):
        for i in range(segments):
            a = r*segments+i
            b = r*segments+(i+1) % segments
            c = (r+1)*segments+(i+1) % segments
            d = (r+1)*segments+i
            m.f.append((a, d, c)); m.f.append((a, c, b))
    if cap_bottom:
        pole = len(m.v); m.v.append(tuple(sections[0][0]))
        for i in range(segments):
            m.f.append((pole, (i+1) % segments, i))
    if cap_top:
        pole = len(m.v); m.v.append(tuple(sections[-1][0]))
        base = (rings-1)*segments
        for i in range(segments):
            m.f.append((pole, base+i, base+(i+1) % segments))
    return m


def rounded_column(center_x, center_z, y0, y1, a, b, n=2.0, round0=0.05, round1=0.05,
                   steps=5, profile=None, segments=32, bulge=0.0):
    """A soft column whose ends are domed; profile(t)->(scale_a, scale_b, dx, dz)."""
    sections = []
    def sec(y, k):
        t = (y-y0)/max(y1-y0, 1e-6)
        sa, sb, dx, dz = profile(t) if profile else (1.0, 1.0, 0.0, 0.0)
        return ((center_x+dx, y, center_z+dz), max(a*sa*k, 1e-4), max(b*sb*k, 1e-4), n, bulge*k)
    for i in range(steps+1):
        phi = (math.pi/2)*i/steps
        sections.append(sec(y0+round0*(1-math.cos(phi)), math.sin(phi) if i else 0.02))
    middle = 8
    for i in range(1, middle):
        y = y0+round0+(y1-round1-(y0+round0))*i/middle
        sections.append(sec(y, 1.0))
    for i in range(steps, -1, -1):
        phi = (math.pi/2)*i/steps
        sections.append(sec(y1-round1*(1-math.cos(phi)), math.sin(phi) if i else 0.02))
    return loft(sections, segments)


def ellipsoid(center, radii, segments=28, rings=16):
    m = Mesh()
    cx, cy, cz = center
    rx, ry, rz = radii
    for j in range(1, rings):
        th = math.pi*j/rings
        for i in range(segments):
            ph = 2*math.pi*i/segments
            m.v.append((cx+rx*math.sin(th)*math.cos(ph), cy+ry*math.cos(th), cz+rz*math.sin(th)*math.sin(ph)))
    top = len(m.v); m.v.append((cx, cy+ry, cz))
    bottom = len(m.v); m.v.append((cx, cy-ry, cz))
    for j in range(rings-2):
        for i in range(segments):
            a = j*segments+i; b = j*segments+(i+1) % segments
            c = (j+1)*segments+(i+1) % segments; d = (j+1)*segments+i
            m.f.append((a, b, c)); m.f.append((a, c, d))
    for i in range(segments):
        m.f.append((top, (i+1) % segments, i))
        base = (rings-2)*segments
        m.f.append((bottom, base+i, base+(i+1) % segments))
    return m


def tube(path, radius, sides=12, closed=False, flatten=1.0, up=(0, 1, 0)):
    """Sweep a circle (optionally squashed along `up`) along a polyline."""
    m = Mesh()
    count = len(path)
    radii = radius if isinstance(radius, (list, tuple)) else [radius]*count
    for k, p in enumerate(path):
        if closed:
            prev, nxt = path[k-1], path[(k+1) % count]
        else:
            prev, nxt = path[max(k-1, 0)], path[min(k+1, count-1)]
        tangent = v_norm(v_sub(nxt, prev))
        side = v_cross(tangent, up)
        if v_len(side) < 1e-6: side = v_cross(tangent, (0, 0, 1))
        side = v_norm(side)
        normal = v_norm(v_cross(side, tangent))
        for i in range(sides):
            t = 2*math.pi*i/sides
            offset = v_add(v_mul(side, math.cos(t)*radii[k]), v_mul(normal, math.sin(t)*radii[k]*flatten))
            m.v.append(v_add(p, offset))
    loops = count if closed else count-1
    for k in range(loops):
        k2 = (k+1) % count
        for i in range(sides):
            a = k*sides+i; b = k*sides+(i+1) % sides
            c = k2*sides+(i+1) % sides; d = k2*sides+i
            m.f.append((a, b, c)); m.f.append((a, c, d))
    if not closed:
        for end, flip in ((0, True), (count-1, False)):
            pole = len(m.v); m.v.append(path[end])
            for i in range(sides):
                a, b = end*sides+i, end*sides+(i+1) % sides
                m.f.append((pole, b, a) if flip else (pole, a, b))
    return m


def ring_path(center, a, b, n=2.0, steps=40, start=0.0, end=2*math.pi, y_wave=None):
    pts = []
    for i in range(steps):
        t = start+(end-start)*i/(steps if end-start >= 2*math.pi-1e-6 else steps-1)
        x, z = superellipse(t, a, b, n)
        dy = y_wave(t) if y_wave else 0.0
        pts.append((center[0]+x, center[1]+dy, center[2]+z))
    return pts


def rounded_box(center, size, radius, segments=6):
    """Box with rounded edges made from a superellipsoid (good clay look)."""
    hx, hy, hz = size[0]/2, size[1]/2, size[2]/2
    n = max(2.5, 2.0/max(radius/min(hx, hy, hz), 0.08))
    m = Mesh()
    rings, segs = 14, 28
    def se(angle, e):
        c = math.cos(angle)
        return math.copysign(abs(c)**(2.0/e), c)
    def ss(angle, e):
        s = math.sin(angle)
        return math.copysign(abs(s)**(2.0/e), s)
    for j in range(1, rings):
        th = math.pi*j/rings
        for i in range(segs):
            ph = 2*math.pi*i/segs
            m.v.append((center[0]+hx*ss(th, n)*se(ph, n), center[1]+hy*se(th, n), center[2]+hz*ss(th, n)*ss(ph, n)))
    top = len(m.v); m.v.append((center[0], center[1]+hy, center[2]))
    bottom = len(m.v); m.v.append((center[0], center[1]-hy, center[2]))
    for j in range(rings-2):
        for i in range(segs):
            a = j*segs+i; b = j*segs+(i+1) % segs
            c = (j+1)*segs+(i+1) % segs; d = (j+1)*segs+i
            m.f.append((a, b, c)); m.f.append((a, c, d))
    for i in range(segs):
        m.f.append((top, (i+1) % segs, i))
        base = (rings-2)*segs
        m.f.append((bottom, base+i, base+(i+1) % segs))
    return m


# ------------------------------------------------------------------- the body
def build_parts(gender):
    """Return [(node name, material, Mesh)] in rig model space (y up, face -Z)."""
    female = gender == "female"
    parts = []
    def add(bone, name, material, mesh):
        parts.append((bone+"__"+name, material, mesh))

    # Head: the face shell is unchanged so the existing hair still fits.
    add("Head", "face", "skin", ellipsoid((0, 1.285, -0.035), (0.325, 0.305, 0.275), 36, 22))
    ear = ellipsoid((0, 0, 0), (0.06, 0.082, 0.045), 18, 10)
    ear.extend(ellipsoid((0, 0, -0.012), (0.03, 0.045, 0.02), 12, 8))
    for side, suffix in ((-1, ""), (1, ".001")):
        add("Head", "ear"+suffix, "skin", ear.transformed(rot=(0, side*0.35, 0), offset=(side*0.328, 1.262, -0.02)))
    add("Spine", "neck", "skin", rounded_column(0, -0.005, 0.9, 1.06, 0.085, 0.08, 2.0, 0.02, 0.02, 3, segments=20))
    eye_y, eye_x = (1.302, 0.135)
    for side, suffix in ((-1, ""), (1, ".001")):
        # Tall glossy bean eyes with a sparkle, like the clay reference.
        add("Head", "eye"+suffix, "eyes", ellipsoid((side*eye_x, eye_y, -0.287), (0.027, 0.04, 0.014), 18, 12)
            .transformed(rot=(-0.12, side*-0.38, 0), pivot=(side*eye_x, eye_y, -0.287)))
        add("Head", "eye_shine"+suffix, "shine", ellipsoid((side*eye_x+0.009, eye_y+0.017, -0.3), (0.0085, 0.0095, 0.004), 10, 6))
        brow_pts = [(side*(eye_x-0.034), eye_y+0.075, -0.3), (side*eye_x, eye_y+0.087, -0.302), (side*(eye_x+0.036), eye_y+0.078, -0.294)]
        add("Head", "brow"+suffix, "hair", tube(brow_pts, [0.009, 0.0115, 0.008], 8, flatten=0.55))
        add("Head", "cheek"+suffix, "cheek", ellipsoid((side*0.2, 1.205, -0.265), (0.045, 0.026, 0.01), 14, 8)
            .transformed(rot=(0, side*-0.62, 0), pivot=(side*0.2, 1.205, -0.265)))
    add("Head", "nose", "skin", ellipsoid((0, 1.248, -0.318), (0.034, 0.03, 0.028), 16, 10))
    smile = [(-0.045, 1.195, -0.306), (-0.022, 1.181, -0.313), (0, 1.177, -0.315), (0.022, 1.181, -0.313), (0.045, 1.195, -0.306)]
    add("Head", "smile", "mouth", tube(smile, 0.0065, 8))

    # Torso: a soft lofted jacket (A) or shirt (C) instead of a box.
    width = 0.27 if female else 0.295
    depth = 0.19 if female else 0.205
    def torso_profile(t):
        # t: 0 hem .. 1 shoulders. Slight flare at hem, rounded shoulders.
        sa = 1.0 + 0.05*(1-t)**2 - 0.55*max(0.0, t-0.62)**1.6
        sb = 1.0 - 0.35*max(0.0, t-0.6)**1.5
        return (sa, sb, 0.0, 0.01*t)
    hem_y = 0.5 if not female else 0.52
    add("Hips", "jacket", "shirt", rounded_column(0, 0.03, hem_y, 1.0, width, depth, 2.3, 0.035, 0.12, 7,
                                                  profile=torso_profile, segments=40, bulge=0.012))
    if female:
        # Button shirt: hem band, placket, pointed collar.
        add("Hips", "hem", "shirt", tube(ring_path((0, hem_y+0.016, 0.03), width*1.03, depth*1.04, 2.4, 48), 0.016, 10, closed=True))
        placket = [(0, 0.54, -0.218), (0, 0.72, -0.226), (0, 0.9, -0.214)]
        add("Hips", "placket", "shirt", tube(placket, 0.022, 8, flatten=0.35, up=(0, 0, -1)))
        for i, y in enumerate((0.88, 0.77, 0.66)):
            add("Hips", "button"+("" if i == 0 else ".%03d" % i), "buttons", ellipsoid((0, y, -0.232), (0.015, 0.015, 0.008), 12, 8))
        collar = Mesh()
        flap = rounded_box((0, 0, 0), (0.11, 0.085, 0.022), 0.012)
        for side in (-1, 1):
            collar.extend(flap.transformed(rot=(0.35, side*0.55, side*0.75), offset=(side*0.07, 0.975, -0.135)))
        collar.extend(tube(ring_path((0, 0.975, 0.0), 0.115, 0.11, 2.0, 28, math.radians(-60), math.radians(240)), 0.026, 10, flatten=1.4))
        add("Spine", "collar", "shirt", collar)
    else:
        # Field jacket: open front over a dark tee, stand-up collar, chest pockets.
        add("Hips", "hem", "shirt", tube(ring_path((0, hem_y+0.018, 0.03), width*1.035, depth*1.05, 2.4, 48), 0.02, 10, closed=True))
        inner = rounded_column(0, -0.12, 0.7, 0.99, 0.085, 0.07, 2.4, 0.03, 0.05, 4, segments=20,
                               profile=lambda t: (0.25+0.75*t**0.7, 1.0, 0.0, 0.0))
        add("Hips", "undershirt", "inner", inner)
        for side in (-1, 1):
            lapel = [(side*0.03, 0.55, -0.226), (side*0.032, 0.68, -0.234), (side*0.07, 0.84, -0.224), (side*0.105, 0.96, -0.185)]
            add("Hips", "lapel"+("" if side < 0 else ".001"), "shirt", tube(lapel, [0.022, 0.024, 0.024, 0.02], 10, flatten=0.4, up=(0, 0, -1)))
            pocket = rounded_box((0, 0, 0), (0.11, 0.1, 0.03), 0.012).transformed(rot=(0.06, 0, 0), offset=(side*0.17, 0.79, -0.218))
            flap = rounded_box((0, 0, 0), (0.12, 0.035, 0.034), 0.01).transformed(rot=(0.06, 0, 0), offset=(side*0.17, 0.85, -0.226))
            add("Hips", "pocket"+("" if side < 0 else ".001"), "shirt", pocket.extend(flap))
            add("Hips", "button"+("" if side < 0 else ".001"), "buttons", ellipsoid((side*0.17, 0.845, -0.246), (0.012, 0.012, 0.006), 10, 6))
        collar = tube(ring_path((0, 0.985, 0.005), 0.13, 0.125, 2.0, 30, math.radians(-50), math.radians(230)), 0.038, 10, flatten=1.25)
        add("Spine", "collar", "shirt", collar)

    # Arms: tapered sleeves from the shoulder, rolled cuff, mitten hands.
    sleeve_r = 0.095 if female else 0.108
    for side, bone in ((-1, "WingL"), (1, "WingR")):
        shoulder = (side*(0.25 if female else 0.265), 0.9, -0.01)
        elbow = (side*(0.315 if female else 0.33), 0.78, -0.03)
        wrist = (side*0.322, 0.685, -0.06)
        path = []
        radii = []
        for i in range(9):
            t = i/8
            if t < 0.5:
                u = t/0.5; p = tuple(shoulder[k]+(elbow[k]-shoulder[k])*u for k in range(3))
            else:
                u = (t-0.5)/0.5; p = tuple(elbow[k]+(wrist[k]-elbow[k])*u for k in range(3))
            path.append(p)
            radii.append(sleeve_r*(1.0-0.16*t))
        sleeve = tube(path, radii, 18, up=(0, 0, 1))
        sleeve.extend(ellipsoid(shoulder, (sleeve_r*0.98, sleeve_r*0.9, sleeve_r*0.98), 20, 12))
        cuff_center = (wrist[0], wrist[1]+0.012, wrist[2])
        cuff = tube(ring_path((0, 0, 0), sleeve_r*0.8, sleeve_r*0.8, 2.0, 24), 0.014, 8, closed=True).transformed(offset=cuff_center, rot=(0.25, 0, -side*0.12))
        sleeve.extend(cuff)
        add(bone, "sleeve", "shirt", sleeve)
        palm = ellipsoid((0, 0, 0), (0.068, 0.078, 0.07), 20, 12)
        thumb = ellipsoid((0, 0, 0), (0.027, 0.042, 0.027), 12, 8).transformed(rot=(0.5, 0, -side*0.5), offset=(-side*0.045, 0.012, -0.035))
        hand = palm.extend(thumb).transformed(offset=(side*0.322, 0.628, -0.072))
        add(bone, "hand", "skin", hand)

    # Legs: soft trousers with rolled cuffs; chunky rounded boots with soles.
    leg_a = 0.112 if female else 0.122
    for side, bone in ((-1, "FootL"), (1, "FootR")):
        x = side*0.135
        def leg_profile(t):
            return (1.0+0.06*t, 1.0+0.05*t, side*-0.012*t, 0.02*t)
        trouser = rounded_column(x, 0.02, 0.17, 0.56, leg_a, leg_a*0.98, 2.2, 0.02, 0.05, 4, profile=leg_profile, segments=24)
        cuff = tube(ring_path((x, 0.215, 0.02), leg_a*0.95, leg_a*0.93, 2.2, 28), 0.016, 8, closed=True)
        trouser.extend(cuff)
        add(bone, "trouser", "pants", trouser)
        boot = rounded_box((x, 0.1, -0.04), (0.215, 0.17, 0.32), 0.07)
        boot.extend(rounded_box((x, 0.2, 0.02), (0.2, 0.08, 0.2), 0.05))
        add(bone, "boot", "boots", boot)
        add(bone, "sole", "sole", rounded_box((x, 0.024, -0.042), (0.228, 0.05, 0.335), 0.02))
    # Hip block keeps the waist closed when legs swing under the jacket hem.
    add("Hips", "seat", "pants", rounded_column(0, 0.035, 0.44, 0.6, 0.23 if female else 0.245, 0.15, 2.4, 0.06, 0.02, 4, segments=32))
    return parts


# ---------------------------------------------------------------- glTF output
class Glb:
    def __init__(self):
        self.json = {"asset": {"version": "2.0", "generator": "tools/build_human_models.py"},
                     "scene": 0, "scenes": [{"nodes": []}], "nodes": [], "meshes": [],
                     "materials": [], "accessors": [], "bufferViews": [], "buffers": []}
        self.bin = bytearray()
        self.material_index = {}

    def _view(self, data, target=None):
        while len(self.bin) % 4: self.bin.append(0)
        view = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)}
        if target: view["target"] = target
        self.bin.extend(data)
        self.json["bufferViews"].append(view)
        return len(self.json["bufferViews"])-1

    def material(self, name, color, roughness=0.85):
        if name not in self.material_index:
            self.json["materials"].append({"name": name, "pbrMetallicRoughness": {
                "baseColorFactor": [color[0], color[1], color[2], 1.0], "metallicFactor": 0.0, "roughnessFactor": roughness}})
            self.material_index[name] = len(self.json["materials"])-1
        return self.material_index[name]

    def add_mesh(self, name, material, mesh):
        normals = mesh.normals()
        pos = struct.pack("<%df" % (len(mesh.v)*3), *[c for p in mesh.v for c in p])
        nor = struct.pack("<%df" % (len(normals)*3), *[c for n in normals for c in n])
        idx = struct.pack("<%dI" % (len(mesh.f)*3), *[i for f in mesh.f for i in f])
        mins = [min(p[k] for p in mesh.v) for k in range(3)]
        maxs = [max(p[k] for p in mesh.v) for k in range(3)]
        acc = self.json["accessors"]
        acc.append({"bufferView": self._view(pos, 34962), "componentType": 5126, "count": len(mesh.v), "type": "VEC3", "min": mins, "max": maxs})
        acc.append({"bufferView": self._view(nor, 34962), "componentType": 5126, "count": len(normals), "type": "VEC3"})
        acc.append({"bufferView": self._view(idx, 34963), "componentType": 5125, "count": len(mesh.f)*3, "type": "SCALAR"})
        n = len(acc)
        self._node(name, {"name": name, "primitives": [{"attributes": {"POSITION": n-3, "NORMAL": n-2}, "indices": n-1, "material": material}]})

    def add_raw(self, name, material, attributes, indices):
        """attributes: {semantic: (accessor dict, bytes)}; indices same."""
        prim = {"attributes": {}, "material": material}
        acc = self.json["accessors"]
        for semantic, (accessor, data) in attributes.items():
            entry = {k: v for k, v in accessor.items() if k not in ("bufferView", "byteOffset")}
            entry["bufferView"] = self._view(data, 34962)
            acc.append(entry); prim["attributes"][semantic] = len(acc)-1
        if indices:
            accessor, data = indices
            entry = {k: v for k, v in accessor.items() if k not in ("bufferView", "byteOffset")}
            entry["bufferView"] = self._view(data, 34963)
            acc.append(entry); prim["indices"] = len(acc)-1
        self._node(name, {"name": name, "primitives": [prim]})

    def _node(self, name, mesh):
        self.json["meshes"].append(mesh)
        self.json["nodes"].append({"name": name, "mesh": len(self.json["meshes"])-1})
        self.json["scenes"][0]["nodes"].append(len(self.json["nodes"])-1)

    def write(self, path):
        while len(self.bin) % 4: self.bin.append(0)
        self.json["buffers"] = [{"byteLength": len(self.bin)}]
        text = json.dumps(self.json, separators=(",", ":")).encode()
        while len(text) % 4: text += b" "
        total = 12+8+len(text)+8+len(self.bin)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, total))
            f.write(struct.pack("<II", len(text), 0x4E4F534A)); f.write(text)
            f.write(struct.pack("<II", len(self.bin), 0x004E4942)); f.write(self.bin)


COMPONENT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPE_COUNT = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_hair(path):
    """Return [(node name, translation, attributes, indices)] for every hair node."""
    data = path.read_bytes()
    length = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20+length])
    binary = data[20+length+8:]
    def accessor_bytes(index):
        acc = doc["accessors"][index]
        view = doc["bufferViews"][acc["bufferView"]]
        size = COMPONENT_SIZE[acc["componentType"]]*TYPE_COUNT[acc["type"]]
        start = view.get("byteOffset", 0)+acc.get("byteOffset", 0)
        stride = view.get("byteStride", size)
        if stride == size:
            return acc, binary[start:start+size*acc["count"]]
        return acc, b"".join(binary[start+i*stride:start+i*stride+size] for i in range(acc["count"]))
    hair = []
    for node in doc["nodes"]:
        if "__hair" not in node.get("name", "") or "mesh" not in node: continue
        if node.get("rotation") or node.get("scale"):
            sys.exit("Hair node %s has a rotation/scale; re-export it baked first." % node["name"])
        for prim in doc["meshes"][node["mesh"]]["primitives"]:
            attrs = {k: accessor_bytes(v) for k, v in prim["attributes"].items() if k in ("POSITION", "NORMAL", "TEXCOORD_0")}
            indices = accessor_bytes(prim["indices"]) if "indices" in prim else None
            hair.append((node["name"], node.get("translation"), attrs, indices))
    return hair


def build(gender):
    path = OUT/(gender+".glb")
    hair = read_hair(path)
    if not hair:
        sys.exit("No hair meshes found in %s; restore it with tools/refine_human_hair.py first." % path)
    glb = Glb()
    colors = MATERIALS[gender]
    for node_name, material, mesh in build_parts(gender):
        glb.add_mesh(node_name, glb.material(material, colors[material], ROUGHNESS.get(material, 0.85)), mesh)
    hair_material = glb.material("hair", colors["hair"])
    for name, translation, attrs, indices in hair:
        if translation and any(abs(t) > 1e-9 for t in translation):
            # Bake node offsets so every hair lock sits in rig model space.
            acc, data = attrs["POSITION"]
            values = list(struct.unpack("<%df" % (acc["count"]*3), data))
            for i in range(0, len(values), 3):
                values[i] += translation[0]; values[i+1] += translation[1]; values[i+2] += translation[2]
            acc = dict(acc); acc["min"] = [m+t for m, t in zip(acc["min"], translation)]; acc["max"] = [m+t for m, t in zip(acc["max"], translation)]
            attrs = dict(attrs); attrs["POSITION"] = (acc, struct.pack("<%df" % len(values), *values))
        glb.add_raw(name, hair_material, attrs, indices)
    glb.write(path)
    print("HUMAN_MODEL", gender, len(glb.json["nodes"]), "nodes", path.stat().st_size, "bytes")


if __name__ == "__main__":
    for gender in ("male", "female"):
        build(gender)
    manifest = {"generator": "tools/build_human_models.py (hair: tools/refine_human_hair.py)", "files": {}}
    for name in ("male.glb", "female.glb"):
        p = OUT/name
        manifest["files"][name] = {"bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
    (OUT/"asset_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
