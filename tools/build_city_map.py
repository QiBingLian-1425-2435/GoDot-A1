"""Generate the abandoned-city exploration map ("city").

Run from the project root:  python tools/build_city_map.py
Pure Python 3 standard library (no Blender needed). Writes external assets:

  assets/worlds/city/city.glb          flat-shaded, vertex-coloured low-poly meshes,
                                       one node per 64 m tile ("Tile_x_z") plus "Outskirts_*"
  assets/worlds/city/city_layout.json  colliders, air walls, spawn/extraction points, bounds
  assets/worlds/city/asset_manifest.json

The style follows the low-poly post-apocalyptic town look: a 4x4 grid of blocks
(downtown towers, brick shop rows, houses with yards, a gas station, a military
checkpoint, a bus depot, a construction site...), abandoned vehicles, debris and
overgrowth, all enclosed by invisible walls behind a forest belt and mountains.
The .glb opens in Blender for hand editing; re-running this script overwrites it.
"""
import hashlib
import json
import math
import random
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/worlds/city"
SEED = 20261101

# ---------------------------------------------------------------- layout grid
PITCH = 64.0            # block + road
ROAD = 12.0             # asphalt width
WALK = 3.0              # sidewalk width
ROADS = [12.0 + PITCH*k for k in range(5)]          # road centre lines (x and -z)
CITY_MIN, CITY_MAX = 0.0, 280.0
WALL_MIN, WALL_MAX = -3.0, 283.0                     # air walls (x / -z)
TILE = 64.0

# ----------------------------------------------------------------- palette
def hexc(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i+2], 16)/255.0 for i in (0, 2, 4))

C = {k: hexc(v) for k, v in {
    "asphalt": "55575a", "asphalt2": "605f5e", "lane_w": "d9d6c8", "lane_y": "d8b54a",
    "walk": "9d998f", "curb": "807d77", "grass": "8b9550", "grass2": "979d58", "dirt": "967c62",
    "moss": "7d8549", "moss_d": "6a7046", "crack": "2e2f33", "rubble": "8b8378", "rubble2": "6d665d",
    "brick": "9a5a43", "brick2": "8a4c3a", "beige": "c9b48f", "cream": "ddd0b0", "grey": "9fa3a2",
    "concrete": "a9a59b", "teal": "6f9a95", "blue": "6c86a0", "green_b": "7f9a6e", "pink": "c89a8f",
    "yellow_b": "d9b44a", "trim": "e6dfcb", "trim_d": "6a5f55", "roof": "8f8b84", "roof2": "a39e94",
    "roof_red": "9a4b3c", "roof_brown": "6e5440", "roof_teal": "4f6e6c", "roof_grey": "6c6f72",
    "glass": "3f5867", "glass2": "50707f", "frame": "e9e4d6", "door": "5b4436", "metal": "7b8285",
    "dark": "2f3234", "rust": "8b5a3a", "awning_r": "b5473a", "awning_g": "4f8a5f", "awning_b": "3f6f9a",
    "awning_y": "d9a83c", "sign_r": "c0443a", "sign_y": "e2bd45", "sign_b": "3f7fb5",
    "trunk": "6b4f38", "pine": "4f7a3c", "pine2": "5f8a44", "leaf": "7d9a45", "leaf2": "93a84d",
    "autumn": "d0833a", "autumn2": "c46a2e", "rock": "8d8f8c", "rock2": "777a78", "snow": "e7ece9",
    "olive": "5f6b3c", "olive2": "6e7a47", "sand": "c3a877", "tent_y": "d9b53f", "tent_w": "dcdcd4",
    "bus": "d6a83a", "white": "e2e0d8", "red": "b04a3b", "cone": "e07a2f", "wood": "9a7650",
    "water": "5f8ea0", "tire": "26282a", "chrome": "b9bec0",
}.items()}


def jitter(color, rng, amount=0.05):
    k = 1.0 + rng.uniform(-amount, amount)
    return tuple(max(0.0, min(1.0, c*k)) for c in color)


# ------------------------------------------------------------ geometry store
class Geo:
    """Flat-shaded triangle soup with per-face colours.

    Every triangle is oriented away from a reference point (the solid's centre,
    or a point below for ground decals), so winding never needs hand-checking."""
    def __init__(self):
        self.p = []
        self.c = []

    def tri(self, a, b, c, col, ref):
        u = (b[0]-a[0], b[1]-a[1], b[2]-a[2]); v = (c[0]-a[0], c[1]-a[1], c[2]-a[2])
        n = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
        if n[0]**2+n[1]**2+n[2]**2 < 1e-12: return
        m = ((a[0]+b[0]+c[0])/3-ref[0], (a[1]+b[1]+c[1])/3-ref[1], (a[2]+b[2]+c[2])/3-ref[2])
        if n[0]*m[0]+n[1]*m[1]+n[2]*m[2] < 0: b, c = c, b
        self.p.extend((a, b, c))
        self.c.extend((col, col, col))

    def quad(self, a, b, c, d, col, ref):
        self.tri(a, b, c, col, ref)
        self.tri(a, c, d, col, ref)


def rot_y(point, center, angle):
    if not angle: return point
    x, y, z = point[0]-center[0], point[1], point[2]-center[2]
    ca, sa = math.cos(angle), math.sin(angle)
    return (center[0]+x*ca+z*sa, y, center[2]-x*sa+z*ca)


class Builder:
    def __init__(self, rng):
        self.rng = rng
        self.tiles = {}
        self.colliders = []
        self.buildings = []
        self.open_buildings = []
        self.interior_kind = "office"
        self.interior_exclusion = None

    def excluded_furniture(self, center, size):
        if self.interior_exclusion is None:
            return False
        x0, z0, x1, z1 = self.interior_exclusion
        return center[0]+size[0]/2 > x0 and center[0]-size[0]/2 < x1 and center[2]+size[2]/2 > z0 and center[2]-size[2]/2 < z1

    def geo_at(self, x, z, group="Tile"):
        key = (group, int(math.floor(x/TILE)), int(math.floor(-z/TILE)))
        if key not in self.tiles: self.tiles[key] = Geo()
        return self.tiles[key]

    # -- primitives (all CCW from outside; Godot/glTF front faces)
    def box(self, center, size, col, ang=0.0, top=None, group="Tile", bottom=False, sides=None):
        if self.excluded_furniture(center, size): return
        g = self.geo_at(center[0], center[2], group)
        cx, cy, cz = center
        hx, hy, hz = size[0]/2, size[1]/2, size[2]/2
        v = [(cx+sx*hx, cy+sy*hy, cz+sz*hz) for sx, sy, sz in
             [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
        v = [rot_y(p, center, ang) for p in v]
        side = sides or col
        g.quad(v[1], v[0], v[3], v[2], side, center)        # -z
        g.quad(v[4], v[5], v[6], v[7], side, center)        # +z
        g.quad(v[0], v[4], v[7], v[3], side, center)        # -x
        g.quad(v[5], v[1], v[2], v[6], side, center)        # +x
        g.quad(v[3], v[7], v[6], v[2], top or col, center)  # top
        if bottom: g.quad(v[0], v[1], v[5], v[4], col, center)

    def flat(self, x0, z0, x1, z1, y, col, group="Tile"):
        """Axis-aligned horizontal rectangle (x0<x1, z0<z1)."""
        g = self.geo_at((x0+x1)/2, (z0+z1)/2, group)
        g.quad((x0, y, z0), (x0, y, z1), (x1, y, z1), (x1, y, z0), col, ((x0+x1)/2, y-1, (z0+z1)/2))

    def poly(self, pts, y, col, group="Tile"):
        """Convex horizontal polygon from (x, z) points."""
        cx = sum(p[0] for p in pts)/len(pts); cz = sum(p[1] for p in pts)/len(pts)
        g = self.geo_at(cx, cz, group)
        for i in range(len(pts)):
            a, b = pts[i], pts[(i+1) % len(pts)]
            # winding chosen so the face points up
            g.tri((cx, y, cz), (b[0], y, b[1]), (a[0], y, a[1]), col, (cx, y-1, cz))

    def prism(self, center, size, col, ang=0.0, roof_col=None, overhang=0.4, group="Tile", gable_col=None):
        """Gable roof whose ridge runs along local x."""
        g = self.geo_at(center[0], center[2], group)
        cx, cy, cz = center
        hx, hy, hz = size[0]/2+overhang, size[1], size[2]/2+overhang
        r = roof_col or col
        a = [(cx-hx, cy, cz-hz), (cx+hx, cy, cz-hz), (cx+hx, cy, cz+hz), (cx-hx, cy, cz+hz),
             (cx-hx, cy+hy, cz), (cx+hx, cy+hy, cz)]
        a = [rot_y(p, center, ang) for p in a]
        ref = (cx, cy+hy*0.3, cz)
        g.quad(a[1], a[0], a[4], a[5], r, ref)       # -z slope
        g.quad(a[3], a[2], a[5], a[4], r, ref)       # +z slope
        gc = gable_col or col
        g.tri(a[0], a[3], a[4], gc, ref)
        g.tri(a[2], a[1], a[5], gc, ref)
        g.quad(a[0], a[1], a[2], a[3], r, (cx, cy+5, cz))       # underside faces down

    def cylinder(self, center, radius, height, col, n=8, top=None, group="Tile", r_top=None):
        g = self.geo_at(center[0], center[2], group)
        cx, cy, cz = center
        rt = radius if r_top is None else r_top
        ring0 = [(cx+radius*math.cos(2*math.pi*i/n), cy, cz+radius*math.sin(2*math.pi*i/n)) for i in range(n)]
        ring1 = [(cx+rt*math.cos(2*math.pi*i/n), cy+height, cz+rt*math.sin(2*math.pi*i/n)) for i in range(n)]
        ref = (cx, cy+height*0.4, cz)
        for i in range(n):
            j = (i+1) % n
            g.quad(ring0[j], ring0[i], ring1[i], ring1[j], col, ref)
            if rt > 0.001:
                g.tri((cx, cy+height, cz), ring1[j], ring1[i], top or col, (cx, cy, cz))

    def blob(self, center, radius, col, rng, squash=1.0, n=7, rings=4, group="Tile", noise=0.18, dark=None):
        """Low-poly faceted sphere (tree crowns, bushes, rocks)."""
        g = self.geo_at(center[0], center[2], group)
        cx, cy, cz = center
        pts = []
        for j in range(rings+1):
            th = math.pi*j/rings
            row = []
            for i in range(n):
                ph = 2*math.pi*(i+0.5*(j % 2))/n
                k = 1.0+rng.uniform(-noise, noise) if 0 < j < rings else 1.0
                row.append((cx+radius*k*math.sin(th)*math.cos(ph), cy+radius*squash*math.cos(th), cz+radius*k*math.sin(th)*math.sin(ph)))
            pts.append(row)
        for j in range(rings):
            for i in range(n):
                a, b2 = pts[j][i], pts[j][(i+1) % n]
                c, d = pts[j+1][(i+1) % n], pts[j+1][i]
                shade = col if (dark is None or j < rings//2+1) else dark
                face = jitter(shade, rng, 0.06)
                g.quad(a, b2, c, d, face, center)

    def collide(self, center, size, ang=0.0, kind="solid"):
        if self.excluded_furniture(center, size): return
        self.colliders.append({"c": [round(v, 3) for v in center], "s": [round(v, 3) for v in size],
                               "r": round(ang, 4), "k": kind})


# ------------------------------------------------------------ props
def car(b, x, z, ang, rng, col=None, wreck=False):
    col = jitter(col or rng.choice([C["red"], C["blue"], C["teal"], C["beige"], C["white"], C["green_b"], C["yellow_b"], C["rust"]]), rng, 0.08)
    if wreck: col = jitter(C["rust"], rng, 0.1)
    base = (x, 0.55, z)
    b.box(base, (4.2, 0.7, 1.9), col, ang)
    b.box((x, 1.12, z), (2.3, 0.55, 1.7), jitter(C["glass"], rng, 0.05), ang, top=col)
    b.box((x, 1.42, z), (2.2, 0.06, 1.62), col, ang)
    for dx in (-1.35, 1.35):
        for dz in (-0.95, 0.95):
            p = rot_y((x+dx, 0.33, z+dz), base, ang)
            b.box(p, (0.66, 0.66, 0.26), C["tire"], ang)
    b.collide((x, 0.75, z), (4.3, 1.5, 2.0), ang)


def van(b, x, z, ang, rng, col=None):
    col = jitter(col or rng.choice([C["white"], C["beige"], C["grey"]]), rng, 0.06)
    b.box((x, 1.2, z), (5.2, 2.0, 2.1), col, ang)
    b.box(rot_y((x-2.1, 1.65, z), (x, 0, z), ang), (0.9, 0.7, 1.95), C["glass"], ang)
    for dx in (-1.7, 1.7):
        for dz in (-1.0, 1.0):
            b.box(rot_y((x+dx, 0.35, z+dz), (x, 0, z), ang), (0.7, 0.7, 0.25), C["tire"], ang)
    b.box(rot_y((x+0.6, 1.3, z-1.07), (x, 0, z), ang), (1.6, 0.5, 0.04), C["sign_r"], ang)
    b.collide((x, 1.1, z), (5.3, 2.2, 2.2), ang)


def bus(b, x, z, ang, rng):
    col = jitter(C["bus"], rng, 0.05)
    b.box((x, 1.65, z), (11.0, 2.7, 2.6), col, ang, top=jitter(C["white"], rng, 0.04))
    for i in range(7):
        for side in (-1, 1):
            p = rot_y((x-4.2+i*1.4, 2.2, z+side*1.31), (x, 0, z), ang)
            b.box(p, (1.1, 0.8, 0.05), C["glass"], ang)
    b.box(rot_y((x-5.52, 2.1, z), (x, 0, z), ang), (0.05, 1.1, 2.2), C["glass"], ang)
    for dx in (-3.8, 3.6):
        for dz in (-1.2, 1.2):
            b.box(rot_y((x+dx, 0.45, z+dz), (x, 0, z), ang), (0.9, 0.9, 0.3), C["tire"], ang)
    b.collide((x, 1.5, z), (11.2, 3.0, 2.8), ang)


def truck(b, x, z, ang, rng):
    o = jitter(C["olive"], rng, 0.05)
    c = (x, 0, z)
    b.box(rot_y((x+2.6, 1.45, z), c, ang), (2.0, 1.9, 2.3), o, ang)
    b.box(rot_y((x+3.0, 1.85, z), c, ang), (0.9, 0.6, 2.2), C["glass"], ang)
    b.box(rot_y((x-1.0, 1.1, z), c, ang), (5.0, 0.5, 2.4), jitter(C["olive2"], rng), ang)
    b.prism(rot_y((x-1.0, 1.35, z), c, ang), (5.0, 1.4, 2.4), o, ang, roof_col=jitter(C["olive2"], rng), overhang=0.05)
    for dx in (-2.4, -0.8, 2.6):
        for dz in (-1.15, 1.15):
            b.box(rot_y((x+dx, 0.5, z+dz), c, ang), (1.0, 1.0, 0.35), C["tire"], ang)
    b.collide((x+0.2, 1.4, z), (7.4, 2.8, 2.6), ang)


def pine(b, x, z, rng, scale=1.0, group="Tile", collide=True):
    s = scale*rng.uniform(0.85, 1.25)
    b.cylinder((x, 0, z), 0.25*s, 1.6*s, C["trunk"], n=5, group=group)
    col = jitter(rng.choice([C["pine"], C["pine2"]]), rng, 0.06)
    for i, (r, h) in enumerate([(2.2, 3.0), (1.7, 2.6), (1.1, 2.2)]):
        b.cylinder((x, (1.2+i*1.5)*s, z), r*s, h*s, jitter(col, rng, 0.05), n=7, r_top=0.0, group=group)
    if collide: b.collide((x, 1.5, z), (0.7, 3.0, 0.7))


def round_tree(b, x, z, rng, autumn=False, scale=1.0, group="Tile", collide=True):
    s = scale*rng.uniform(0.8, 1.2)
    b.cylinder((x, 0, z), 0.22*s, 2.2*s, C["trunk"], n=5, group=group)
    base = rng.choice([C["autumn"], C["autumn2"]]) if autumn else rng.choice([C["leaf"], C["leaf2"]])
    b.blob((x, 3.4*s, z), 1.9*s, jitter(base, rng, 0.05), rng, squash=0.85, group=group)
    b.blob((x+0.9*s, 2.9*s, z+0.4*s), 1.2*s, jitter(base, rng, 0.07), rng, group=group)
    if collide: b.collide((x, 1.5, z), (0.6, 3.0, 0.6))


def dead_tree(b, x, z, rng):
    b.cylinder((x, 0, z), 0.2, 3.2, C["trunk"], n=5, r_top=0.08)
    for k in range(3):
        a = rng.uniform(0, 2*math.pi)
        b.box((x+math.cos(a)*0.6, 2.4+k*0.35, z+math.sin(a)*0.6), (1.3, 0.12, 0.12), C["trunk"], a)
    b.collide((x, 1.5, z), (0.5, 3.0, 0.5))


def lamp(b, x, z, ang):
    b.cylinder((x, 0, z), 0.09, 5.0, C["metal"], n=6)
    arm = rot_y((x+0.8, 5.0, z), (x, 0, z), ang)
    b.box(arm, (1.7, 0.1, 0.12), C["metal"], ang)
    head = rot_y((x+1.55, 4.9, z), (x, 0, z), ang)
    b.box(head, (0.55, 0.16, 0.3), C["dark"], ang)
    b.collide((x, 1.2, z), (0.25, 2.4, 0.25), kind="post")


def barrier(b, x, z, ang, rng):
    col = jitter(rng.choice([C["concrete"], C["concrete"], C["white"]]), rng, 0.05)
    b.box((x, 0.18, z), (2.0, 0.36, 0.7), col, ang)
    b.box((x, 0.62, z), (2.0, 0.55, 0.32), col, ang)
    b.collide((x, 0.5, z), (2.0, 1.0, 0.7), ang, kind="low")


def sandbags(b, x, z, length, ang, rng, rows=3):
    n = max(1, int(length/0.9))
    for r in range(rows):
        for i in range(n - (r % 2)):
            off = -length/2+0.45+i*0.9+(0.45 if r % 2 else 0)
            p = rot_y((x+off, 0.16+r*0.3, z), (x, 0, z), ang)
            b.box(p, (0.86, 0.3, 0.55), jitter(C["sand"], rng, 0.07), ang)
    b.collide((x, 0.5, z), (length, 1.0, 0.7), ang, kind="low")


def cone(b, x, z):
    b.box((x, 0.03, z), (0.45, 0.06, 0.45), C["cone"])
    b.cylinder((x, 0.06, z), 0.18, 0.6, C["cone"], n=6, r_top=0.03)


def rubble(b, x, z, rng, size=1.0):
    for _ in range(int(5*size)+3):
        r = rng.uniform(0.25, 0.7)*size
        b.blob((x+rng.uniform(-1.4, 1.4)*size, r*0.4, z+rng.uniform(-1.4, 1.4)*size), r,
               rng.choice([C["rubble"], C["rubble2"], C["concrete"]]), rng, squash=0.6, n=5, rings=3, noise=0.3)
    for _ in range(3):
        b.box((x+rng.uniform(-1.5, 1.5)*size, 0.15, z+rng.uniform(-1.5, 1.5)*size),
              (rng.uniform(0.6, 1.6), 0.12, 0.15), C["wood"], rng.uniform(0, 3))


def crack(b, x, z, rng, length=6.0):
    a = rng.uniform(0, math.pi)
    px, pz = x, z
    for _ in range(int(length/1.2)):
        a += rng.uniform(-0.7, 0.7)
        nx, nz = px+math.cos(a)*1.2, pz+math.sin(a)*1.2
        w = 0.16
        dx, dz = -math.sin(a)*w, math.cos(a)*w
        g = b.geo_at(px, pz)
        y = 0.012
        g.quad((px-dx, y, pz-dz), (px+dx, y, pz+dz), (nx+dx, y, nz+dz), (nx-dx, y, nz-dz), C["crack"], (px, -1, pz))
        px, pz = nx, nz


def patch(b, x, z, rng, radius=2.5, col=None, y=0.015):
    """Soft irregular overgrowth / dirt / stain decal."""
    n = 12
    radii = [radius*rng.uniform(0.7, 1.05) for _ in range(n)]
    radii = [(radii[i-1]+2*radii[i]+radii[(i+1) % n])/4 for i in range(n)]
    pts = [(x+math.cos(2*math.pi*i/n)*radii[i], z+math.sin(2*math.pi*i/n)*radii[i]) for i in range(n)]
    b.poly(pts, y, jitter(col or C["moss"], rng, 0.05))


def bench(b, x, z, ang):
    b.box((x, 0.45, z), (1.8, 0.08, 0.5), C["wood"], ang)
    b.box(rot_y((x, 0.75, z+0.25), (x, 0, z), ang), (1.8, 0.4, 0.06), C["wood"], ang)
    for dx in (-0.75, 0.75):
        b.box(rot_y((x+dx, 0.22, z), (x, 0, z), ang), (0.08, 0.44, 0.45), C["dark"], ang)


def dumpster(b, x, z, ang, rng):
    col = jitter(rng.choice([C["awning_g"], C["awning_b"], C["dark"]]), rng)
    b.box((x, 0.65, z), (2.0, 1.3, 1.2), col, ang)
    b.box((x, 1.33, z), (2.05, 0.08, 1.25), C["dark"], ang)
    b.collide((x, 0.7, z), (2.0, 1.4, 1.2), ang, kind="low")


def fence(b, x0, z0, x1, z1, col=None, height=1.1, solid_kind="low", picket=True):
    col = col or C["white"]
    L = math.hypot(x1-x0, z1-z0)
    ang = -math.atan2(z1-z0, x1-x0)
    mx, mz = (x0+x1)/2, (z0+z1)/2
    b.box((mx, height*0.75, mz), (L, 0.1, 0.06), col, ang)
    b.box((mx, height*0.35, mz), (L, 0.1, 0.06), col, ang)
    n = int(L/0.45) if picket else int(L/2.5)
    for i in range(n+1):
        t = i/max(n, 1)
        b.box((x0+(x1-x0)*t, height/2, z0+(z1-z0)*t), (0.1 if picket else 0.15, height, 0.08), col, ang)
    b.collide((mx, 0.6, mz), (L, 1.2, 0.3), ang, kind=solid_kind)


def chain_fence(b, x0, z0, x1, z1):
    L = math.hypot(x1-x0, z1-z0)
    ang = -math.atan2(z1-z0, x1-x0)
    mx, mz = (x0+x1)/2, (z0+z1)/2
    b.box((mx, 1.1, mz), (L, 2.0, 0.04), jitter(C["metal"], random.Random(int(x0*7+z0)), 0.02), ang)
    for i in range(int(L/3)+1):
        t = i/max(int(L/3), 1)
        b.cylinder((x0+(x1-x0)*t, 0, z0+(z1-z0)*t), 0.06, 2.2, C["metal"], n=5)
    b.collide((mx, 1.1, mz), (L, 2.2, 0.2), ang, kind="fence")


# ------------------------------------------------------------ buildings
def windows_on_face(b, rng, p0, p1, y0, floors, floor_h, normal, glass=None, every=2.6, frame=True, lit_skip=0.15, entrance=False):
    """Windows along a wall from p0 to p1 (x,z), offset outward along normal."""
    L = math.hypot(p1[0]-p0[0], p1[1]-p0[1])
    ux, uz = (p1[0]-p0[0])/L, (p1[1]-p0[1])/L
    n = max(1, int((L-1.2)/every))
    ang = -math.atan2(uz, ux)
    for f in range(floors):
        for i in range(n):
            if rng.random() < lit_skip*0.3: continue
            t = (i+0.5)/n*L
            if entrance and f == 0 and y0 == 0 and abs(t-L/2) < 1.9:
                continue
            cx = p0[0]+ux*t+normal[0]*0.06
            cz = p0[1]+uz*t+normal[1]*0.06
            y = y0+f*floor_h+floor_h*0.55
            g = jitter(glass or rng.choice([C["glass"], C["glass"], C["glass2"]]), rng, 0.07)
            if rng.random() < 0.12: g = jitter(C["dark"], rng)          # broken / boarded
            if frame:
                b.box((cx-normal[0]*0.02, y, cz-normal[1]*0.02), (1.45, 1.65, 0.1), C["frame"], ang)
            b.box((cx, y, cz), (1.2, 1.4, 0.1), g, ang)
            if rng.random() < 0.08:
                b.box((cx+normal[0]*0.05, y-0.1, cz+normal[1]*0.05), (1.3, 0.25, 0.08), C["wood"], ang+rng.uniform(-0.3, 0.3))


def storeys(b, x0, z0, x1, z1, floors, floor_h):
    """Two flights and a turning landing per storey, with matching slab openings."""
    sx, back = x0+0.35, z0+0.35
    run, landing, sw, lane = 2.2, 1.2, 2.5, 1.15
    front = back+landing+run
    routes = []
    def solid(center, size, color="concrete"):
        b.box(center,size,C[color],bottom=True)
        b.collide(center,size,kind="solid")
    for level in range(1, floors):
        y = level*floor_h
        # Slab strips leave a single rectangular stairwell open on every floor.
        for ax, az, bx, bz in [(x0,z0,sx,z1),(sx+sw,z0,x1,z1),
                               (sx,z0,sx+sw,back),(sx,front,sx+sw,z1)]:
            if bx>ax and bz>az:
                solid(((ax+bx)/2,y-.1,(az+bz)/2),(bx-ax,.2,bz-az),"trim")
        base = (level-1)*floor_h
        count = 11
        rise, tread = floor_h/(count*2), run/count
        for step in range(count):
            top = base+(step+1)*rise
            b.box((sx+lane/2,top-.08,front-(step+.5)*tread),(lane,.16,tread+.015),C["concrete"],bottom=True)
            top = base+floor_h/2+(step+1)*rise
            b.box((sx+sw-lane/2,top-.08,back+landing+(step+.5)*tread),(lane,.16,tread+.015),C["concrete"],bottom=True)
        # Continuous hidden ramps beneath the visible treads keep both directions
        # smooth and avoid the capsule catching many tiny descending edges.
        for left, start, end, bottom, top in [(sx,front,back+landing,base,base+floor_h/2),
                                             (sx+sw-lane,back+landing,front,base+floor_h/2,base+floor_h)]:
            points = [[x,y-offset,z] for x in (left,left+lane)
                      for z,y in ((start,bottom),(end,top)) for offset in (0,.2)]
            b.colliders.append({"k":"solid","points":points})
        solid((sx+sw/2,base+floor_h/2-.1,back+landing/2),(sw,.2,landing))
        # Thin central divider/handrail keeps the two flights separate.
        solid((sx+sw/2,base+floor_h/2,front-run/2),(.12,floor_h,run),"metal")
        # Guard the open left edge of the stairwell on each upper floor.
        solid((sx-.03,y+.45,back+(landing+run)/2),(.1,.9,landing+run),"metal")
        routes.append([[sx+lane/2,base+.04,front+.6],
                       [sx+lane/2,base+floor_h/2+.04,back+landing/2],
                       [sx+sw-lane/2,base+floor_h/2+.04,back+landing/2],
                       [sx+sw-lane/2,y+.04,front+.6]])
        # A small desk and storage unit on upper floors, outside the stair approach.
        solid((x1-1.2,y+.4,z1-1.3),(1.4,.8,.8),"wood")
        solid((x1-1.2,y+.85,z0+1.3),(1.1,1.7,.7),"wood")
    # Solid roof closes the top floor, rather than another traversable storey.
    y = floors*floor_h
    solid(((x0+x1)/2,y+.1,(z0+z1)/2),(x1-x0,.2,z1-z0),"roof")
    return routes, (sx-.2,back-.2,sx+sw+.3,front+1.3)


def enterable_shell(b, x0, z0, x1, z1, height, wall, front, kind, floors=1):
    """Hollow rooms, connected storeys and furniture clear of the stairwell."""
    cx, cz = (x0+x1)/2, (z0+z1)/2
    width, depth = x1-x0, z1-z0
    door_w, door_h, thick = 1.8, min(2.5, height-0.2), 0.24
    faces = {"s": ((cx, z1), width, 0), "n": ((cx, z0), width, math.pi),
             "e": ((x1, cz), depth, math.pi/2), "w": ((x0, cz), depth, -math.pi/2)}
    def wall_part(center, size, angle=0):
        b.box(center, size, wall, angle, bottom=True)
        b.collide(center, size, angle)
    for side, ((mx, mz), length, angle) in faces.items():
        if side != front:
            wall_part((mx, height/2, mz), (length, height, thick), angle)
            continue
        for sign in (-1, 1):
            offset = sign*(length+door_w)/4
            wall_part((mx+math.cos(angle)*offset, height/2, mz-math.sin(angle)*offset),
                      ((length-door_w)/2, height, thick), angle)
        wall_part((mx, (height+door_h)/2, mz), (door_w, height-door_h, thick), angle)
    # Ground physics stays flush with the district paving.
    b.flat(x0, z0, x1, z1, 0.11, C["wood"] if kind == "home" else C["trim"])
    routes, exclusion = storeys(b,x0,z0,x1,z1,floors,height/floors)
    (mx, mz), _, angle = faces[front]
    uid = "city_door_%03d" % len(b.buildings)
    b.buildings.append({"id": uid, "bounds": [x0, z0, width, depth], "kind": kind,
                        "door": [mx, 0.08, mz], "angle": angle, "width": door_w,
                        "height": door_h-0.08, "normal": [math.sin(angle), math.cos(angle)],
                        "floors": floors, "floor_height": height/floors, "stairs": routes})
    b.interior_exclusion = exclusion if floors > 1 else None
    # Furniture stays clear of the doorway and central crossing in every orientation.
    def prop(x, z, sx, sy, sz, color):
        b.box((x, 0.08+sy/2, z), (sx, sy, sz), C[color], bottom=True)
        b.collide((x, 0.08+sy/2, z), (sx, sy, sz), kind="low")
    if width < 5 or depth < 5:
        prop(x0+0.65, z0+0.65, 0.7, 0.8, 0.7, "wood")
        b.interior_exclusion = None
        return
    left, right, back, near = x0+1.3, x1-1.3, z0+1.4, z1-1.4
    if kind == "home":
        prop(left, back, 1.6, 0.45, 2.2, "wood")
        b.box((left, 0.66, back), (1.55, 0.25, 2.1), C["white"])
        b.box((left, 0.83, back-0.65), (1.1, 0.15, 0.45), C["blue"])
        prop(right, back, 1.6, 1.7, 0.7, "wood")
        prop(left, near, 1.6, 0.65, 0.9, "teal")
        b.box((left, 0.95, near+0.3), (1.6, 0.6, 0.25), C["teal"])
        prop(right, near, 1.3, 0.8, 0.8, "cream")
    elif kind == "warehouse":
        for x in (left, right):
            for z in (back, near):
                prop(x, z, 1.8, 1.2, 1.8, "wood")
                b.box((x, 1.55, z), (1.2, 0.5, 1.2), C["rust"])
    elif kind == "shop":
        for x in (left, right):
            prop(x, back, 1.6, 1.6, 0.7, "metal")
            for y in (0.45, 0.95, 1.5):
                for dx in (-0.5, 0, 0.5):
                    b.box((x+dx, y+0.1, back+0.45), (0.3, 0.3, 0.3), C["sign_y"])
        prop(left, near, 1.8, 0.9, 0.8, "wood")
        b.box((left, 1.15, near), (0.5, 0.3, 0.4), C["dark"])
        prop(right, near, 1.2, 1.8, 0.75, "glass2")
    else:
        for x in (left, right):
            for z in (back, near):
                prop(x, z, 1.5, 0.75, 0.8, "wood")
                prop(x, z+(-0.8 if z == near else 0.8), 0.55, 0.45, 0.55, "blue")
                b.box((x, 1.0, z), (0.5, 0.4, 0.12), C["dark"])
    # Larger rooms get repeated aisles rather than four props in an empty hall.
    # Leave the 4.4 m central cross free, linking every possible entrance to the centre.
    if kind != "home":
        x = x0+4
        while x < x1-3:
            z = z0+4
            while z < z1-3:
                if abs(x-cx)>2.2 and abs(z-cz)>2.2:
                    if kind == "warehouse":
                        prop(x,z,1.6,1.0,1.6,"wood")
                        b.box((x,1.4,z),(1.1,.6,1.1),C["rust"])
                    elif kind == "shop":
                        prop(x,z,1.6,1.25,.75,"metal")
                        for dx in (-.5,0,.5):
                            b.box((x+dx,1.5,z),(.3,.3,.4),C["sign_y"])
                    else:
                        prop(x,z,1.5,.75,.8,"wood")
                        prop(x,z+.9,.55,.45,.55,"blue")
                        b.box((x,1.0,z),(.5,.4,.12),C["dark"])
                z+=4
            x+=4
    b.interior_exclusion = None


def building(b, rng, x0, z0, x1, z1, floors, wall, front="s", shop=False, roof=None, sign=None, flat=True, cornice=True):
    """Box building occupying [x0,x1]x[z0,z1] (z0<z1). front: side with storefront."""
    fh = 3.3
    H = floors*fh
    cx, cz = (x0+x1)/2, (z0+z1)/2
    w, d = x1-x0, z1-z0
    wall = jitter(wall, rng, 0.05)
    enterable_shell(b, x0, z0, x1, z1, H, wall, front, "shop" if shop else b.interior_kind, floors)
    if cornice:
        b.box((cx, H+0.25, cz), (w+0.3, 0.5, d+0.3), jitter(C["trim"], rng, 0.04), top=jitter(roof or C["roof"], rng, 0.05))
        band = jitter(C["trim"], rng, 0.04)
        for px,pz,bw,bd in [(cx,z0,w+.12,.16),(cx,z1,w+.12,.16),(x0,cz,.16,d),(x1,cz,.16,d)]:
            b.box((px,fh-.1,pz),(bw,.25,bd),band)
    faces = {"s": ((x0, z1), (x1, z1), (0, 1)), "n": ((x1, z0), (x0, z0), (0, -1)),
             "e": ((x1, z1), (x1, z0), (1, 0)), "w": ((x0, z0), (x0, z1), (-1, 0))}
    for key, (p0, p1, nrm) in faces.items():
        upper_start = fh if (shop and key == front) else 0.0
        fl = floors-1 if upper_start else floors
        if fl > 0:
            windows_on_face(b, rng, p0, p1, upper_start, fl, fh, nrm, entrance=key == front)
    if shop:
        p0, p1, nrm = faces[front]
        L = math.hypot(p1[0]-p0[0], p1[1]-p0[1])
        ux, uz = (p1[0]-p0[0])/L, (p1[1]-p0[1])/L
        ang = -math.atan2(uz, ux)
        mx, mz = (p0[0]+p1[0])/2, (p0[1]+p1[1])/2
        for side in (-1, 1):
            offset = side*(L/4+0.5)
            b.box((mx+ux*offset+nrm[0]*0.15, 1.35, mz+uz*offset+nrm[1]*0.15),
                  (max(0.5, L/2-1.4), 2.0, 0.1), jitter(C["glass2"], rng), ang)
        aw = rng.choice([C["awning_r"], C["awning_g"], C["awning_b"], C["awning_y"]])
        b.box((mx+nrm[0]*0.8, 2.75, mz+nrm[1]*0.8), (L*0.85, 0.12, 1.6), jitter(aw, rng), ang)
        b.box((mx+nrm[0]*1.58, 2.55, mz+nrm[1]*1.58), (L*0.85, 0.45, 0.06), jitter(aw, rng), ang)
        if sign:
            b.box((mx+nrm[0]*0.15, H-0.9 if floors > 1 else 3.4, mz+nrm[1]*0.15), (min(L*0.6, 7.0), 1.0, 0.15), jitter(sign, rng), ang)
    else:
        p0, p1, nrm = faces[front]
        mx, mz = (p0[0]+p1[0])/2, (p0[1]+p1[1])/2
        ang = -math.atan2(p1[1]-p0[1], p1[0]-p0[0])
        # The separate runtime door supplies both the leaf and its collider.
    # rooftop parapet rim
    if flat and cornice:
        rim = jitter(C["trim"], rng, 0.04)
        for (px, pz, sx, sz) in [(cx, z0+0.1, w+0.3, 0.3), (cx, z1-0.1, w+0.3, 0.3), (x0+0.1, cz, 0.3, d+0.3), (x1-0.1, cz, 0.3, d+0.3)]:
            b.box((px, H+0.75, pz), (sx, 0.5, sz), rim)
    # rooftop clutter
    if flat:
        for _ in range(rng.randint(1, 4)):
            rx = rng.uniform(x0+1.5, x1-1.5); rz = rng.uniform(z0+1.5, z1-1.5)
            s = rng.uniform(1.0, 2.4)
            b.box((rx, H+0.5+s*0.3, rz), (s, s*0.6, s*0.8), jitter(C["metal"], rng, 0.1))
        if rng.random() < 0.35:
            patch(b, rng.uniform(x0+2, x1-2), rng.uniform(z0+2, z1-2), rng, radius=min(w, d)*0.18, y=H+0.52)
        if rng.random() < 0.25 and floors >= 3:
            tx, tz = rng.uniform(x0+2, x1-2), rng.uniform(z0+2, z1-2)
            for dx in (-0.8, 0.8):
                for dz in (-0.8, 0.8):
                    b.box((tx+dx, H+1.5, tz+dz), (0.15, 2.0, 0.15), C["wood"])
            b.cylinder((tx, H+2.5, tz), 1.3, 2.0, jitter(C["wood"], rng), n=8, top=C["roof_brown"])
    # vines
    if rng.random() < 0.5:
        p0, p1, nrm = faces[rng.choice(list(faces))]
        for _ in range(rng.randint(1, 3)):
            t = rng.uniform(0.1, 0.9)
            vx, vz = p0[0]+(p1[0]-p0[0])*t+nrm[0]*0.15, p0[1]+(p1[1]-p0[1])*t+nrm[1]*0.15
            vh = rng.uniform(2, H*0.8)
            b.box((vx, H-vh/2, vz), (0.6, vh, 0.12), jitter(C["moss"], rng, 0.1), -math.atan2(p1[1]-p0[1], p1[0]-p0[0]))
    return H


def house(b, rng, cx, cz, w, d, front="s", floors=1):
    fh = 3.0
    H = floors*fh
    wall = jitter(rng.choice([C["cream"], C["beige"], C["pink"], C["teal"], C["blue"], C["green_b"], C["grey"]]), rng)
    enterable_shell(b, cx-w/2, cz-d/2, cx+w/2, cz+d/2, H, wall, front, "home", floors)
    roof = jitter(rng.choice([C["roof_red"], C["roof_brown"], C["roof_teal"], C["roof_grey"]]), rng)
    ang = 0.0 if w >= d else math.pi/2
    pw, pd = (w, d) if w >= d else (d, w)
    b.prism((cx, H, cz), (pw, min(pd*0.45, 2.6), pd), wall, ang, roof_col=roof, overhang=0.45)
    x0, x1, z0, z1 = cx-w/2, cx+w/2, cz-d/2, cz+d/2
    faces = {"s": ((x0, z1), (x1, z1), (0, 1)), "n": ((x1, z0), (x0, z0), (0, -1)),
             "e": ((x1, z1), (x1, z0), (1, 0)), "w": ((x0, z0), (x0, z1), (-1, 0))}
    for key, (p0, p1, nrm) in faces.items():
        windows_on_face(b, rng, p0, p1, 0, floors, fh, nrm, every=3.2, entrance=key == front)
    p0, p1, nrm = faces[front]
    mx, mz = (p0[0]+p1[0])/2, (p0[1]+p1[1])/2
    fa = -math.atan2(p1[1]-p0[1], p1[0]-p0[0])
    b.box((mx+nrm[0]*1.0, 0.005, mz+nrm[1]*1.0), (3.2, 0.01, 2.0), C["wood"], fa)
    if rng.random() < 0.5:
        b.box((cx+w*0.25, H+1.0, cz), (0.6, 2.0, 0.6), C["brick2"])                     # chimney


# ------------------------------------------------------------ ground
def build_ground(b, rng):
    big0, big1 = -140.0, 420.0
    # outer grass (outside the city) - drawn in outskirts group, coarse tiles
    for gx in range(int(big0), int(big1), 40):
        for gz in range(int(big0), int(big1), 40):
            x0, x1 = gx, gx+40
            z0, z1 = -(gz+40), -gz
            inside = CITY_MIN <= x0 and x1 <= CITY_MAX+1 and CITY_MIN-1 <= -z1 and -z0 <= CITY_MAX+1
            b.flat(x0, z0, x1, z1, -0.02, jitter(C["grass"], rng, 0.05), group="Outskirts")
    # city base: grass lots per block, roads, sidewalks
    b.flat(CITY_MIN-6, -(CITY_MAX+6), CITY_MAX+6, 6, 0.0, C["asphalt"])
    for r in ROADS:
        # centre dashes along x roads (horizontal) and z roads (vertical)
        for t in range(int(CITY_MIN-4), int(CITY_MAX+4), 6):
            if any(abs(t+1.5-rr) < ROAD/2+2 for rr in ROADS): continue
            b.flat(t, -r-0.12, t+3, -r+0.12, 0.01, C["lane_y"])
            b.flat(r-0.12, -(t+3), r+0.12, -t, 0.01, C["lane_y"])
    # white edge lines along every road
    for r in ROADS:
        for side in (-1, 1):
            e = r+side*(ROAD/2-0.6)
            for t0 in [CITY_MIN-4]+[rr+ROAD/2+3 for rr in ROADS]:
                t1 = min([rr-ROAD/2-3 for rr in ROADS if rr-ROAD/2-3 > t0] + [CITY_MAX+4])
                if t1-t0 < 2: continue
                b.flat(t0, -e-0.1, t1, -e+0.1, 0.01, C["lane_w"])
                b.flat(e-0.1, -t1, e+0.1, -t0, 0.01, C["lane_w"])
    # crosswalks at each intersection
    for rx in ROADS:
        for rz in ROADS:
            for k in range(-4, 5):
                o = k*1.3
                for side in (-1, 1):
                    b.flat(rx+o-0.4, -(rz+side*(ROAD/2+1.2))-0.9, rx+o+0.4, -(rz+side*(ROAD/2+1.2))+0.9, 0.012, C["lane_w"])
                    b.flat(rx+side*(ROAD/2+1.2)-0.9, -(rz+o)-0.4, rx+side*(ROAD/2+1.2)+0.9, -(rz+o)+0.4, 0.012, C["lane_w"])
    blocks = []
    for i in range(4):
        for j in range(4):
            x0 = ROADS[i]+ROAD/2; x1 = ROADS[i+1]-ROAD/2
            z0 = ROADS[j]+ROAD/2; z1 = ROADS[j+1]-ROAD/2       # in "north distance" units
            # sidewalk ring
            b.flat(x0, -z1, x1, -z0, 0.08, jitter(C["walk"], rng, 0.03))
            for (a0, a1, c0, c1) in [(x0, x1, z0, z0+0.25), (x0, x1, z1-0.25, z1), (x0, x0+0.25, z0, z1), (x1-0.25, x1, z0, z1)]:
                b.flat(a0, -c1, a1, -c0, 0.1, C["curb"])
            blocks.append((i, j, x0+WALK, z0+WALK, x1-WALK, z1-WALK))
    # weathering on roads
    for _ in range(320):
        x = rng.uniform(CITY_MIN, CITY_MAX); z = -rng.uniform(CITY_MIN, CITY_MAX)
        if on_road(x, -z):
            crack(b, x, z, rng, rng.uniform(3, 9))
    for _ in range(420):
        x = rng.uniform(CITY_MIN, CITY_MAX); n = rng.uniform(CITY_MIN, CITY_MAX)
        if on_road(x, n) or near_walk(x, n):
            patch(b, x, -n, rng, rng.uniform(0.9, 3.0), col=rng.choice([C["moss_d"], C["moss_d"], C["moss"], C["dirt"], C["asphalt2"]]),
                  y=0.11 if near_walk(x, n) else 0.015)
    return blocks


def on_road(x, n):
    return any(abs(x-r) < ROAD/2 for r in ROADS) or any(abs(n-r) < ROAD/2 for r in ROADS)


def near_walk(x, n):
    return any(ROAD/2 <= abs(x-r) < ROAD/2+WALK for r in ROADS) or any(ROAD/2 <= abs(n-r) < ROAD/2+WALK for r in ROADS)


# ------------------------------------------------------------ block designs
def lot(b, rng, x0, n0, x1, n1, col=None):
    b.flat(x0, -n1, x1, -n0, 0.09, jitter(col or C["grass"], rng, 0.04))


def block_downtown_tower(b, rng, x0, n0, x1, n1):
    lot(b, rng, x0, n0, x1, n1, C["concrete"])
    building(b, rng, x0+2, -(n0+30), x0+24, -(n0+6), 9, C["concrete"], front="s", roof=C["roof2"])
    building(b, rng, x0+26, -(n0+38), x1-2, -(n0+22), 5, C["beige"], front="e", shop=True, sign=C["sign_r"])
    building(b, rng, x0+26, -(n0+19), x1-2, -(n0+2), 3, C["brick"], front="s", shop=True, sign=C["sign_y"])
    building(b, rng, x0+2, -(n1-1), x0+24, -(n0+33), 2, C["grey"], front="w", shop=True, sign=C["sign_b"])
    # helipad on tower roof
    H = 9*3.3+0.52
    b.cylinder((x0+13, H, -(n0+18)), 5.0, 0.05, C["dark"], n=12)
    b.flat(x0+12.2, -(n0+20.5), x0+12.8, -(n0+15.5), H+0.07, C["lane_y"])
    b.flat(x0+13.2, -(n0+20.5), x0+13.8, -(n0+15.5), H+0.07, C["lane_y"])
    b.flat(x0+12.8, -(n0+18.3), x0+13.2, -(n0+17.7), H+0.07, C["lane_y"])
    for k in range(4): dumpster(b, x0+4+k*4, -(n0+32), 0, rng) if k % 2 == 0 else None


def block_shop_row(b, rng, x0, n0, x1, n1):
    lot(b, rng, x0, n0, x1, n1, C["concrete"])
    walls = [C["brick"], C["beige"], C["brick2"], C["cream"], C["green_b"], C["grey"]]
    x = x0+1
    i = 0
    while x < x1-6:
        w = min(rng.uniform(8, 12), x1-1-x)
        building(b, rng, x, -(n0+14), x+w, -(n0+1), rng.randint(2, 4), walls[i % len(walls)], front="s",
                 shop=True, sign=rng.choice([C["sign_r"], C["sign_y"], C["sign_b"], None]))
        x += w+0.2; i += 1
    x = x0+1
    while x < x1-6:
        w = min(rng.uniform(9, 14), x1-1-x)
        building(b, rng, x, -(n1-1), x+w, -(n1-15), rng.randint(2, 3), walls[(i+2) % len(walls)], front="n",
                 shop=True, sign=rng.choice([C["sign_r"], C["sign_y"], None]))
        x += w+0.2; i += 1
    # back alley
    b.flat(x0, -(n1-15), x1, -(n0+14), 0.1, jitter(C["asphalt2"], rng))
    for k in range(3): dumpster(b, x0+6+k*12, -(n0+16), 0, rng)
    rubble(b, x0+20, -(n0+20), rng)


def block_houses(b, rng, x0, n0, x1, n1, autumn=False):
    lot(b, rng, x0, n0, x1, n1, C["grass2"])
    # two rows of houses facing the north/south streets
    for row, (nz, front) in enumerate([(n0+8, "s"), (n1-8, "n")]):
        for k in range(3):
            cx = x0+7+k*((x1-x0-14)/2)
            w = rng.uniform(7, 9); d = rng.uniform(6, 8)
            house(b, rng, cx, -nz, w, d, front=front, floors=rng.choice([1, 1, 2]))
            fz = n0+0.6 if front == "s" else n1-0.6
            fence(b, cx-6.5, -fz, cx-1.2, -fz, height=0.9)
            fence(b, cx+1.2, -fz, cx+6.5, -fz, height=0.9)
            if rng.random() < 0.7:
                round_tree(b, cx+rng.choice([-5, 5]), -(nz+(-3 if front == "n" else 3)), rng, autumn=autumn and rng.random() < 0.7)
            if rng.random() < 0.4:
                car(b, cx+5.5, -(fz+(-4 if front == "s" else 4)), math.pi/2, rng)
    # back yards: dead trees, pool, sheds
    mid = (n0+n1)/2
    b.box(((x0+x1)/2-12, 0.35, -mid), (5, 0.7, 3.4), jitter(C["concrete"], rng), top=C["water"])
    b.collide(((x0+x1)/2-12, 0.35, -mid), (5, 0.7, 3.4), kind="low")
    dead_tree(b, (x0+x1)/2+4, -mid+2, rng)
    sx = (x0+x1)/2+13
    enterable_shell(b, sx-1.5, -mid-1.25, sx+1.5, -mid+1.25, 2.4, jitter(C["wood"], rng), "s", "shed")
    b.prism(((x0+x1)/2+13, 2.4, -mid), (3, 0.9, 2.5), C["wood"], roof_col=C["roof_grey"], overhang=0.2)
    for _ in range(6):
        patch(b, rng.uniform(x0+3, x1-3), -rng.uniform(n0+3, n1-3), rng, rng.uniform(1.5, 3), col=C["dirt"], y=0.1)


def block_gas_station(b, rng, x0, n0, x1, n1):
    lot(b, rng, x0, n0, x1, n1, C["asphalt2"])
    cx, cn = (x0+x1)/2, n0+15
    b.box((cx, 5.2, -cn), (20, 0.6, 11), jitter(C["white"], rng), top=C["roof2"])
    b.box((cx, 4.85, -cn), (20.2, 0.15, 11.2), C["sign_r"])
    for dx in (-7, 7):
        for dz in (-3.5, 3.5):
            b.box((cx+dx, 2.45, -(cn+dz)), (0.45, 4.9, 0.45), C["white"])
            b.collide((cx+dx, 2.45, -(cn+dz)), (0.5, 4.9, 0.5), kind="post")
    for dx in (-4, 4):
        b.box((cx+dx, 0.15, -cn), (1.6, 0.3, 4.0), C["concrete"])
        for dz in (-1, 1):
            b.box((cx+dx, 0.95, -(cn+dz)), (0.8, 1.3, 0.6), C["sign_r"], top=C["white"])
        b.collide((cx+dx, 0.7, -cn), (1.6, 1.4, 3.0), kind="low")
    building(b, rng, x0+4, -(n1-3), x0+28, -(n1-15), 1, C["cream"], front="s", shop=True, sign=C["sign_y"])
    b.cylinder((x1-5, 0, -(n0+3)), 0.25, 9.0, C["metal"], n=6)
    b.box((x1-5, 9.5, -(n0+3)), (4.5, 2.0, 0.4), C["sign_r"], top=C["sign_y"])
    b.collide((x1-5, 2, -(n0+3)), (0.5, 4, 0.5), kind="post")
    car(b, cx-4, -(cn+5.5), 0.1, rng, wreck=True)
    car(b, x1-8, -(n1-6), 1.4, rng)
    rubble(b, cx+8, -(n1-8), rng, 0.8)


def block_parking(b, rng, x0, n0, x1, n1):
    lot(b, rng, x0, n0, x1, n1, C["asphalt2"])
    for row in range(3):
        nz = n0+7+row*13
        for k in range(10):
            x = x0+3+k*4.4
            b.flat(x-0.06, -(nz+2.6), x+0.06, -(nz-2.6), 0.1, C["lane_w"])
            if rng.random() < 0.55 and x < x1-4:
                car(b, x+2.2, -nz, math.pi/2+rng.uniform(-0.15, 0.15), rng, wreck=rng.random() < 0.25)
    chain_fence(b, x0+0.5, -(n0+0.5), x1-0.5, -(n0+0.5))
    lamp(b, x0+3, -(n1-2), 0)
    lamp(b, x1-3, -(n1-2), math.pi)


def block_plaza(b, rng, x0, n0, x1, n1):
    lot(b, rng, x0, n0, x1, n1, C["grass"])
    cx, cn = (x0+x1)/2, (n0+n1)/2
    b.flat(cx-3, -n1, cx+3, -n0, 0.1, C["walk"])
    b.flat(x0, -(cn+3), x1, -(cn-3), 0.1, C["walk"])
    b.cylinder((cx, 0.1, -cn), 10, 0.02, C["walk"], n=16)
    b.cylinder((cx, 0, -cn), 5.0, 0.8, jitter(C["concrete"], rng), n=12, top=C["water"])
    b.cylinder((cx, 0.8, -cn), 1.4, 1.4, C["concrete"], n=8)
    b.cylinder((cx, 2.2, -cn), 2.4, 0.4, C["concrete"], n=8, top=C["water"])
    b.cylinder((cx, 2.6, -cn), 0.5, 1.2, C["concrete"], n=6)
    b.collide((cx, 0.6, -cn), (9.0, 1.2, 9.0), kind="low")
    b.collide((cx, 1.8, -cn), (2.8, 3.6, 2.8))
    for k in range(8):
        a = 2*math.pi*k/8+0.39
        bench(b, cx+math.cos(a)*8, -cn+math.sin(a)*8, -a+math.pi/2)
    for qx in (-1, 1):
        for qz in (-1, 1):
            for t in range(3):
                tx = cx+qx*rng.uniform(9, 19); tz = cn+qz*rng.uniform(9, 19)
                round_tree(b, tx, -tz, rng, autumn=rng.random() < 0.35)
    # statue
    b.box((cx-14, 0.9, -(cn-13)), (2, 1.8, 2), C["concrete"])
    b.box((cx-14, 2.6, -(cn-13)), (0.8, 1.6, 0.6), C["teal"])
    b.blob((cx-14, 3.7, -(cn-13)), 0.4, C["teal"], rng, n=6, rings=3)
    b.collide((cx-14, 1.4, -(cn-13)), (2, 2.8, 2))


def block_military(b, rng, x0, n0, x1, n1):
    lot(b, rng, x0, n0, x1, n1, C["concrete"])
    # perimeter sandbags & fences with a gate on the south side
    sandbags(b, x0+9, -(n0+1), 16, 0, rng)
    sandbags(b, x1-9, -(n0+1), 16, 0, rng)
    chain_fence(b, x0+1, -(n1-1), x1-1, -(n1-1))
    chain_fence(b, x0+1, -(n0+1.5), x0+1, -(n1-1))
    chain_fence(b, x1-1, -(n0+1.5), x1-1, -(n1-1))
    for k in range(3):
        tx = x0+8+k*13
        tz = n0+14
        b.box((tx, 1.3, -tz), (8, 2.6, 6), jitter(C["tent_y"], rng))
        b.prism((tx, 2.6, -tz), (8, 1.4, 6), C["tent_y"], 0, roof_col=jitter(C["tent_y"], rng, 0.03), overhang=0.1)
        b.box((tx, 1.0, -(tz-3.02)), (2.4, 2.0, 0.05), C["dark"])
        b.collide((tx, 1.8, -tz), (8, 3.6, 6))
    for k in range(3):
        dx = x0+8+k*13; dn = n1-10
        b.blob((dx, 0.0, -dn), 4.2, jitter(C["tent_w"], rng, 0.03), rng, squash=0.75, n=10, rings=4, noise=0.02)
        b.collide((dx, 1.5, -dn), (6.6, 3.0, 6.6))
    truck(b, x1-8, -(n0+30), math.pi/2, rng)
    truck(b, x0+6, -(n0+30), math.pi/2+0.1, rng)
    for k in range(6):
        b.box((x0+18+k*1.1, 0.55, -(n0+29)), (0.9, 1.1, 0.9), jitter(C["olive2"], rng))
    b.collide((x0+21, 0.6, -(n0+29)), (6.6, 1.2, 1.0), kind="low")
    for k in range(5):
        cone(b, x0+16+k*2.5, -(n0+4))
    # supply yard: barrels, crate stacks, stretchers, inner sandbag walls
    for k in range(10):
        bx, bz = x0+4+(k % 5)*1.0, -(n0+22+(k//5)*1.0)
        b.cylinder((bx, 0, bz), 0.42, 1.0, jitter(rng.choice([C["olive"], C["awning_b"], C["yellow_b"]]), rng), n=8, top=C["dark"])
    b.collide((x0+6, 0.5, -(n0+22.5)), (5.4, 1.0, 2.2), kind="low")
    for k in range(4):
        for h in range(rng.randint(1, 3)):
            b.box((x1-14+k*2.2, 0.6+h*1.2, -(n0+22)), (2.0, 1.2, 1.6), jitter(C["olive2"] if h % 2 else C["wood"], rng))
    b.collide((x1-10.7, 1.5, -(n0+22)), (8.8, 3.0, 1.8))
    for k in range(6):
        b.box((x0+20+k*1.6, 0.3, -(n0+36)), (0.7, 0.2, 2.0), jitter(C["white"], rng, 0.05), rng.uniform(-0.15, 0.15))
    sandbags(b, (x0+x1)/2, -(n0+19), 10, 0, rng, rows=2)
    sandbags(b, x0+13, -(n1-18), 8, math.pi/2, rng, rows=2)
    b.box((x0+4, 0.8, -(n1-4)), (2.4, 1.6, 1.4), jitter(C["olive"], rng))          # generator
    b.cylinder((x0+4.6, 1.6, -(n1-4)), 0.12, 1.4, C["dark"], n=5)
    b.collide((x0+4, 0.8, -(n1-4)), (2.4, 1.6, 1.4), kind="low")
    b.box(((x0+x1)/2, 0.5, -(n0+7)), (5, 1.0, 1.2), C["concrete"])
    b.collide(((x0+x1)/2, 0.5, -(n0+7)), (5, 1.0, 1.2), kind="low")
    # watch tower
    tx, tz = x1-5, -(n1-5)
    for dx in (-1.2, 1.2):
        for dz in (-1.2, 1.2):
            b.box((tx+dx, 3, tz+dz), (0.25, 6, 0.25), C["wood"])
    b.box((tx, 6.2, tz), (3.4, 0.3, 3.4), C["wood"])
    b.box((tx, 7.0, tz), (3.4, 1.2, 3.4), jitter(C["olive"], rng))
    b.prism((tx, 7.6, tz), (3.4, 0.9, 3.4), C["olive"], 0, roof_col=C["roof_grey"], overhang=0.3)
    b.collide((tx, 3, tz), (2.8, 6, 2.8))


def block_bus_depot(b, rng, x0, n0, x1, n1):
    lot(b, rng, x0, n0, x1, n1, C["asphalt2"])
    building(b, rng, x0+2, -(n1-1), x1-2, -(n1-12), 2, C["green_b"], front="s", shop=False)
    for k in range(4):
        bus(b, x0+9+k*1.0+(k % 2)*14, -(n0+6+k*6.5), 0.05*(k-1.5), rng)
    rubble(b, x1-8, -(n0+10), rng, 1.2)
    b.box((x1-10, 3.2, -(n0+22)), (10, 0.25, 6), jitter(C["metal"], rng))         # shelter roof
    for dx in (-4.5, 4.5):
        for dz in (-2.5, 2.5):
            b.box((x1-10+dx, 1.6, -(n0+22+dz)), (0.2, 3.2, 0.2), C["metal"])
            b.collide((x1-10+dx, 1.6, -(n0+22+dz)), (0.25, 3.2, 0.25), kind="post")


def block_construction(b, rng, x0, n0, x1, n1):
    lot(b, rng, x0, n0, x1, n1, C["dirt"])
    chain_fence(b, x0+0.5, -(n0+0.5), x1-12, -(n0+0.5))
    chain_fence(b, x1-6, -(n0+0.5), x1-0.5, -(n0+0.5))
    # unfinished concrete frame
    fx0, fz0 = x0+6, n0+10
    for fy in range(3):
        y = fy*3.6
        jitter(C["concrete"], rng)  # Preserve the exterior dressing RNG sequence.
        for cx in range(4):
            for cz in range(3):
                b.box((fx0+cx*7.3, y+1.7, -(fz0+cz*9)), (0.5, 3.4, 0.5), C["concrete"])
                b.collide((fx0+cx*7.3, y+1.7, -(fz0+cz*9)), (0.6, 3.4, 0.6), kind="post")
    routes, _ = storeys(b,fx0,-(fz0+18),fx0+22,-fz0,3,3.6)
    b.open_buildings.append({"id":"city_construction","bounds":[fx0,-(fz0+18),22,18],
                             "floors":3,"floor_height":3.6,"stairs":routes,"kind":"construction"})
    # crane
    cx, cz = x1-6, -(n1-6)
    b.box((cx, 11, cz), (1.2, 22, 1.2), C["yellow_b"])
    b.box((cx-8, 22.3, cz), (22, 0.8, 0.9), C["yellow_b"])
    b.box((cx+2, 21.0, cz), (3, 2, 2), C["yellow_b"])
    b.collide((cx, 11, cz), (1.4, 22, 1.4))
    for k in range(4):
        b.box((x0+5+k*2.4, 0.4, -(n1-4)), (2.2, 0.8, 1.4), jitter(C["wood"], rng))
    b.collide((x0+8.6, 0.5, -(n1-4)), (9.6, 1.0, 1.4), kind="low")
    for k in range(5): cone(b, x0+30+k*1.6, -(n0+4))
    rubble(b, x0+30, -(n1-12), rng, 1.5)


def block_motel_diner(b, rng, x0, n0, x1, n1):
    lot(b, rng, x0, n0, x1, n1, C["asphalt2"])
    # diner with striped roof
    building(b, rng, x0+3, -(n0+16), x0+22, -(n0+4), 1, C["white"], front="s", shop=True, sign=C["sign_r"], roof=C["roof_red"])
    b.box((x0+12.5, 4.0, -(n0+10)), (19.4, 0.4, 12.4), C["sign_r"], top=C["roof_red"])
    # L-shaped yellow-roof motel
    building(b, rng, x0+26, -(n1-2), x1-2, -(n1-12), 2, C["cream"], front="n", roof=C["yellow_b"], cornice=False)
    building(b, rng, x1-12, -(n1-12), x1-2, -(n0+18), 2, C["cream"], front="w", roof=C["yellow_b"], cornice=False)
    b.cylinder((x0+3, 0, -(n1-4)), 0.22, 8.5, C["metal"], n=6)
    b.box((x0+3, 9.0, -(n1-4)), (3.5, 2.2, 0.3), C["sign_y"], top=C["sign_r"])
    b.collide((x0+3, 2, -(n1-4)), (0.5, 4, 0.5), kind="post")
    for k in range(4): car(b, x0+28+k*4.6, -(n0+8), math.pi/2+rng.uniform(-0.2, 0.2), rng, wreck=rng.random() < 0.4)
    # water tower
    tx, tz = x1-6, -(n0+6)
    for dx in (-1.6, 1.6):
        for dz in (-1.6, 1.6):
            b.box((tx+dx, 4.5, tz+dz), (0.25, 9, 0.25), C["metal"])
    b.cylinder((tx, 9.0, tz), 3.0, 3.6, jitter(C["white"], rng), n=10, top=C["roof2"])
    b.cylinder((tx, 12.6, tz), 3.1, 1.2, C["roof2"], n=10, r_top=0.2)
    b.collide((tx, 4.5, tz), (3.6, 9, 3.6))


def block_warehouse(b, rng, x0, n0, x1, n1):
    lot(b, rng, x0, n0, x1, n1, C["concrete"])
    b.interior_kind = "warehouse"
    building(b, rng, x0+2, -(n1-2), x0+30, -(n0+14), 3, C["grey"], front="e", roof=C["roof_grey"], cornice=False)
    b.interior_kind = "office"
    # corrugated roof ridges
    for k in range(9):
        b.box((x0+16, 3*3.3+0.15, -(n0+16+k*3)), (28, 0.3, 0.3), C["metal"])
    for k in range(3):
        b.box((x1-6, 1.3, -(n0+8+k*10)), (6.0, 2.6, 2.4), jitter(rng.choice([C["awning_b"], C["rust"], C["awning_g"], C["red"]]), rng))
        b.collide((x1-6, 1.3, -(n0+8+k*10)), (6.0, 2.6, 2.4))
    van(b, x0+20, -(n0+6), 0.2, rng)
    for k in range(5): b.box((x0+4+k*1.4, 0.6, -(n0+8)), (1.2, 1.2, 1.2), jitter(C["wood"], rng))
    b.collide((x0+6.8, 0.6, -(n0+8)), (7, 1.2, 1.2), kind="low")


def block_apartments(b, rng, x0, n0, x1, n1):
    lot(b, rng, x0, n0, x1, n1, C["grass"])
    building(b, rng, x0+3, -(n0+21), x0+19, -(n0+3), 6, C["brick"], front="s", roof=C["roof2"])
    building(b, rng, x0+24, -(n0+19), x1-3, -(n0+3), 5, C["beige"], front="s", roof=C["roof"])
    building(b, rng, x0+3, -(n1-3), x1-20, -(n1-15), 4, C["teal"], front="n", roof=C["roof"])
    b.flat(x0+20, -(n1-3), x1-2, -(n0+22), 0.1, jitter(C["asphalt2"], rng))
    for k in range(3): car(b, x0+24+k*5, -(n1-8), math.pi/2, rng, wreck=k == 1)
    round_tree(b, x0+21, -(n0+12), rng)
    dead_tree(b, x1-6, -(n0+24), rng)


def block_school(b, rng, x0, n0, x1, n1):
    lot(b, rng, x0, n0, x1, n1, C["grass2"])
    building(b, rng, x0+2, -(n1-2), x1-2, -(n1-16), 3, C["brick2"], front="s", roof=C["roof"])
    building(b, rng, x0+2, -(n1-17), x0+14, -(n0+16), 2, C["brick2"], front="e", roof=C["roof"])
    # sports court
    b.flat(x0+18, -(n1-20), x1-4, -(n0+3), 0.11, jitter(C["roof_teal"], rng))
    b.flat(x0+18, -(n0+13.5), x1-4, -(n0+13.2), 0.12, C["lane_w"])
    for hx in (x0+19, x1-5):
        b.box((hx, 1.7, -(n0+13.3)), (0.15, 3.4, 0.15), C["metal"])
        b.box((hx, 3.3, -(n0+13.3)), (0.1, 1.0, 1.6), C["white"])
    chain_fence(b, x0+17, -(n0+2.5), x1-3, -(n0+2.5))
    for k in range(3): round_tree(b, x0+5+k*4.5, -(n0+5), rng, autumn=True)


# ------------------------------------------------------------ street dressing
def dress_streets(b, rng, spawn, extract):
    def clear_of(x, n, pts, r):
        return all(math.hypot(x-p[0], n-p[1]) > r for p in pts)
    keep = [spawn, extract]
    # lamps along sidewalks
    for r in ROADS:
        for t in range(int(CITY_MIN)+20, int(CITY_MAX)-10, 26):
            if any(abs(t-rr) < 10 for rr in ROADS): continue
            for side in (-1, 1):
                off = side*(ROAD/2+0.8)
                if rng.random() < 0.8: lamp(b, t, -(r+off), math.pi/2*(1 if side < 0 else -1))
                if rng.random() < 0.8: lamp(b, r+off, -t, 0 if side < 0 else math.pi)
    # abandoned vehicles in lanes (never across a whole road)
    for _ in range(120):
        r = rng.choice(ROADS); t = rng.uniform(CITY_MIN+15, CITY_MAX-15)
        if any(abs(t-rr) < 9 for rr in ROADS): continue
        lane = rng.choice([-3.0, 3.0])
        horizontal = rng.random() < 0.5
        x, n = (t, r+lane) if horizontal else (r+lane, t)
        if not clear_of(x, n, keep, 14): continue
        ang = (0 if horizontal else math.pi/2)+rng.uniform(-0.35, 0.35)
        k = rng.random()
        if k < 0.7: car(b, x, -n, ang, rng, wreck=rng.random() < 0.3)
        elif k < 0.85: van(b, x, -n, ang, rng)
        else: bus(b, x, -n, ang, rng)
    # road blocks: jersey barriers + cones at a few intersections
    for (ix, iz) in [(1, 2), (3, 1), (2, 4), (0, 3)]:
        rx, rz = ROADS[ix], ROADS[iz]
        for k in range(3):
            barrier(b, rx-4+k*2.1, -(rz+ROAD/2+3), rng.uniform(-0.2, 0.2), rng)
        for k in range(3): cone(b, rx+3+k*1.2, -(rz+ROAD/2+2))
    # rubble and debris
    for _ in range(110):
        x = rng.uniform(CITY_MIN+8, CITY_MAX-8); n = rng.uniform(CITY_MIN+8, CITY_MAX-8)
        if (on_road(x, n) or near_walk(x, n)) and clear_of(x, n, keep, 10):
            rubble(b, x, -n, rng, rng.uniform(0.5, 1.1))
    # tyres, papers, planks and pallets scattered on the streets
    for _ in range(260):
        x = rng.uniform(CITY_MIN+4, CITY_MAX-4); n = rng.uniform(CITY_MIN+4, CITY_MAX-4)
        if not (on_road(x, n) or near_walk(x, n)) or not clear_of(x, n, keep, 6): continue
        k = rng.random()
        if k < 0.3: b.cylinder((x, 0.0, -n), 0.38, 0.25, C["tire"], n=7, top=C["dark"])
        elif k < 0.6: b.box((x, 0.03, -n), (0.5, 0.02, 0.35), jitter(C["white"], rng, 0.1), rng.uniform(0, 3))
        elif k < 0.8: b.box((x, 0.08, -n), (1.2, 0.14, 1.0), C["wood"], rng.uniform(0, 3))
        else: b.cylinder((x, 0.0, -n), 0.3, 0.9, jitter(rng.choice([C["rust"], C["awning_b"], C["red"]]), rng), n=7)
    # trash bins and hydrants on sidewalks
    for _ in range(60):
        r = rng.choice(ROADS); t = rng.uniform(CITY_MIN+15, CITY_MAX-15)
        if any(abs(t-rr) < 9 for rr in ROADS): continue
        side = rng.choice([-1, 1])*(ROAD/2+1.6)
        x, n = (t, r+side) if rng.random() < 0.5 else (r+side, t)
        if rng.random() < 0.5:
            b.cylinder((x, 0.08, -n), 0.35, 1.0, jitter(C["awning_g"], rng), n=7)
        else:
            b.cylinder((x, 0.08, -n), 0.18, 0.7, C["red"], n=6, top=C["red"])


def extraction_site(b, rng, x, n):
    b.cylinder((x, 0.02, -n), 4.0, 0.03, C["lane_y"], n=16)
    b.cylinder((x, 0.03, -n), 3.4, 0.03, C["asphalt"], n=16)
    for k in range(8):
        a = 2*math.pi*k/8
        cone(b, x+math.cos(a)*4.6, -n+math.sin(a)*4.6)
    b.cylinder((x+5.5, 0, -n), 0.12, 4.5, C["metal"], n=6)
    b.box((x+6.3, 4.0, -n), (1.6, 1.0, 0.06), C["cone"])
    van(b, x-6.5, -(n+1), 0.3, rng, col=C["white"])


# ------------------------------------------------------------ outskirts
def outskirts(b, rng):
    """Forest belt and mountains outside the air walls (visual only)."""
    def outside(x, n, margin):
        return x < WALL_MIN-margin or x > WALL_MAX+margin or n < WALL_MIN-margin or n > WALL_MAX+margin
    # forest belt 4..40 m beyond the walls
    count = 0
    for gx in range(-60, 345, 5):
        for gn in range(-60, 345, 5):
            x = gx+rng.uniform(-2, 2); n = gn+rng.uniform(-2, 2)
            if not outside(x, n, 3): continue
            if outside(x, n, 46): continue
            if rng.random() < 0.18: continue
            if rng.random() < 0.8: pine(b, x, -n, rng, scale=rng.uniform(1.1, 1.6), group="Outskirts", collide=False)
            else: round_tree(b, x, -n, rng, autumn=rng.random() < 0.3, scale=1.3, group="Outskirts", collide=False)
            count += 1
    # mountains ring
    cx = cn = (CITY_MIN+CITY_MAX)/2
    for k in range(56):
        a = 2*math.pi*k/56+rng.uniform(-0.03, 0.03)
        # square-ish ring hugging the forest belt
        dist = min(1.0/max(abs(math.cos(a)), abs(math.sin(a))), 1.35)*rng.uniform(206, 222)
        mx, mn = cx+math.cos(a)*dist, cn+math.sin(a)*dist
        mountain(b, rng, mx, -mn, rng.uniform(30, 48), rng.uniform(24, 46))
    return count


def mountain(b, rng, x, z, radius, height):
    g = b.geo_at(x, z, "Outskirts")
    n = 9
    rings = [(radius, 0.0), (radius*0.72, height*0.38), (radius*0.42, height*0.72), (radius*0.12, height)]
    pts = []
    for r, h in rings:
        row = []
        for i in range(n):
            a = 2*math.pi*i/n
            k = rng.uniform(0.8, 1.15)
            row.append((x+math.cos(a)*r*k, h+rng.uniform(-1.5, 1.5)*(h > 0), z+math.sin(a)*r*k))
        pts.append(row)
    for j in range(len(rings)-1):
        for i in range(n):
            a, bb = pts[j][i], pts[j][(i+1) % n]
            c, d = pts[j+1][(i+1) % n], pts[j+1][i]
            col = C["moss"] if j == 0 else (C["rock"] if j == 1 else (C["rock2"] if j == 2 else C["snow"]))
            if j == 1 and rng.random() < 0.4: col = C["moss"]
            col = jitter(col, rng, 0.07)
            g.quad(a, bb, c, d, col, (x, height*0.25, z))
    top = (x, height+3, z)
    for i in range(n):
        g.tri(pts[-1][i], top, pts[-1][(i+1) % n], jitter(C["snow"], rng, 0.04), (x, height*0.5, z))


# ------------------------------------------------------------ assemble
def build():
    rng = random.Random(SEED)
    b = Builder(rng)
    blocks = build_ground(b, rng)
    designs = {
        (0, 0): block_parking, (1, 0): block_shop_row, (2, 0): block_bus_depot, (3, 0): block_motel_diner,
        (0, 1): block_gas_station, (1, 1): block_plaza, (2, 1): block_military, (3, 1): block_warehouse,
        (0, 2): block_houses, (1, 2): block_downtown_tower, (2, 2): block_shop_row, (3, 2): block_construction,
        (0, 3): lambda *a: block_houses(*a, autumn=True), (1, 3): block_school, (2, 3): block_houses, (3, 3): block_apartments,
    }
    for i, j, x0, n0, x1, n1 in blocks:
        designs[(i, j)](b, rng, x0, n0, x1, n1)
    spawn = (ROADS[2], ROADS[0]-0.0)          # south avenue, centre
    extract = (ROADS[4], ROADS[4])             # north-east corner intersection
    dress_streets(b, rng, spawn, extract)
    extraction_site(b, rng, *extract)
    trees = outskirts(b, rng)
    # air walls: tall invisible boxes just outside the edge sidewalks
    mid = (WALL_MIN+WALL_MAX)/2
    span = WALL_MAX-WALL_MIN+2
    for c, s in [((mid, 4, -(WALL_MIN-0.5)), (span, 8, 1)), ((mid, 4, -(WALL_MAX+0.5)), (span, 8, 1)),
                 ((WALL_MIN-0.5, 4, -mid), (1, 8, span)), ((WALL_MAX+0.5, 4, -mid), (1, 8, span))]:
        b.collide(c, s, kind="air")
    return b, spawn, extract, trees


# ------------------------------------------------------------ glb writer
def write_glb(b, path):
    doc = {"asset": {"version": "2.0", "generator": "tools/build_city_map.py"}, "scene": 0,
           "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "accessors": [], "bufferViews": [],
           "buffers": [], "materials": [{"name": "city_vertex_color", "pbrMetallicRoughness": {"metallicFactor": 0, "roughnessFactor": 0.9}}]}
    blob = bytearray()
    def view(data, target):
        while len(blob) % 4: blob.append(0)
        doc["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob.extend(data)
        return len(doc["bufferViews"])-1
    total = 0
    for (group, tx, tz), g in sorted(b.tiles.items()):
        if not g.p: continue
        pos = []; nor = []; col = []
        for i in range(0, len(g.p), 3):
            a, bb, c = g.p[i], g.p[i+1], g.p[i+2]
            u = (bb[0]-a[0], bb[1]-a[1], bb[2]-a[2]); v = (c[0]-a[0], c[1]-a[1], c[2]-a[2])
            n = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
            ln = math.sqrt(n[0]**2+n[1]**2+n[2]**2) or 1.0
            n = (n[0]/ln, n[1]/ln, n[2]/ln)
            for k in range(3):
                pos.extend(g.p[i+k]); nor.extend(n); col.extend((*g.c[i+k], 1.0))
        count = len(pos)//3
        total += count//3
        mins = [min(pos[k::3]) for k in range(3)]; maxs = [max(pos[k::3]) for k in range(3)]
        acc = doc["accessors"]
        acc.append({"bufferView": view(struct.pack("<%df" % len(pos), *pos), 34962), "componentType": 5126, "count": count, "type": "VEC3", "min": mins, "max": maxs})
        acc.append({"bufferView": view(struct.pack("<%df" % len(nor), *nor), 34962), "componentType": 5126, "count": count, "type": "VEC3"})
        acc.append({"bufferView": view(struct.pack("<%df" % len(col), *col), 34962), "componentType": 5126, "count": count, "type": "VEC4"})
        k = len(acc)
        name = "%s_%d_%d" % (group, tx, tz)
        doc["meshes"].append({"name": name, "primitives": [{"attributes": {"POSITION": k-3, "NORMAL": k-2, "COLOR_0": k-1}, "material": 0}]})
        doc["nodes"].append({"name": name, "mesh": len(doc["meshes"])-1})
        doc["scenes"][0]["nodes"].append(len(doc["nodes"])-1)
    while len(blob) % 4: blob.append(0)
    doc["buffers"] = [{"byteLength": len(blob)}]
    text = json.dumps(doc, separators=(",", ":")).encode()
    while len(text) % 4: text += b" "
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12+8+len(text)+8+len(blob)))
        f.write(struct.pack("<II", len(text), 0x4E4F534A)); f.write(text)
        f.write(struct.pack("<II", len(blob), 0x004E4942)); f.write(blob)
    return total


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    b, spawn, extract, trees = build()
    tris = write_glb(b, OUT/"city.glb")
    layout = {
        "version": 3, "seed": SEED,
        "bounds": [WALL_MIN-1, -(WALL_MAX+1), WALL_MAX-WALL_MIN+2, WALL_MAX-WALL_MIN+2],
        "spawn": [spawn[0], 0.0, -spawn[1]],
        "extraction": [extract[0], 0.0, -extract[1]],
        "camera_center": [(CITY_MIN+CITY_MAX)/2, 0.0, -(CITY_MIN+CITY_MAX)/2],
        "colliders": b.colliders,
        "buildings": b.buildings,
        "open_buildings": b.open_buildings,
    }
    (OUT/"city_layout.json").write_text(json.dumps(layout, separators=(",", ":")), encoding="utf-8")
    manifest = {"generator": "tools/build_city_map.py", "seed": SEED, "triangles": tris, "colliders": len(b.colliders),
                "forest_trees": trees, "files": {}}
    for name in ("city.glb", "city_layout.json"):
        p = OUT/name
        manifest["files"][name] = {"bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
    manifest["revision"] = manifest["files"]["city.glb"]["sha256"][:12]
    (OUT/"asset_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print("CITY_MAP triangles=%d colliders=%d tiles=%d forest=%d" % (tris, len(b.colliders), len(b.tiles), trees))


if __name__ == "__main__":
    main()
