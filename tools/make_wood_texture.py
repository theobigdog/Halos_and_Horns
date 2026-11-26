# Bakes the shared wood grain (scripts/wood_grain.gd's GLSL, the same maths) into a tiling texture and its
# normal map, for the hand-built props' wood (surfaces.gd). Run from the project folder:
#   python tools/make_wood_texture.py
# The texture covers TILE metres: 0.5 across the grain (image x) by 5 along it (image y).
import numpy as np
from PIL import Image

W, H = 256, 1024
ACROSS, ALONG = 0.5, 5.0
AGE = 0.5


def h21(px, py):
    q = np.stack([px, py, px], -1) * 0.1031
    q = q - np.floor(q)
    d = (q * (q[..., [1, 2, 0]] + 33.33)).sum(-1, keepdims=True)
    q = q + d
    v = (q[..., 0] + q[..., 1]) * q[..., 2]
    return v - np.floor(v)


def noise(x, y, per_x, per_y):
    """value noise whose lattice repeats every per_x, per_y cells (so the texture tiles)"""
    ix, iy = np.floor(x), np.floor(y)
    fx, fy = x - ix, y - iy
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)

    def hh(a, b):
        return h21(np.mod(a, per_x), np.mod(b, per_y))
    return (hh(ix, iy) * (1 - fx) + hh(ix + 1, iy) * fx) * (1 - fy) + (hh(ix, iy + 1) * (1 - fx) + hh(ix + 1, iy + 1) * fx) * fy


def n(gx, gy, fa, fc, ox=0.0):
    return noise(gx * fa + ox, gy * fc, round(ALONG * fa), round(ACROSS * fc))


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


ys, xs = np.mgrid[0:H, 0:W].astype(np.float64)
gx = ys / H * ALONG          # along the grain
gy = xs / W * ACROSS         # across it
ring = n(gx, gy, 0.8, 30.0) * 0.6 + n(gx, gy, 3.0, 90.0) * 0.4
split = (1 - smooth(0.0, 0.035, np.abs(n(gx, gy, 0.6, 14.0) - 0.5))) * (n(gx, gy, 0.4, 4.0, 7.0) >= 0.55) * AGE
kx, ky = gx * 1.0, gy * 6.0
cx, cy = np.mod(np.floor(kx), 5), np.mod(np.floor(ky), 3)
ax = 0.5 + (h21(cx + 3.1, cy + 3.1) - 0.5) * 0.6
ay = 0.5 + (h21(cx + 8.7, cy + 8.7) - 0.5) * 0.6
kf = np.stack([kx - np.floor(kx) - ax, ky - np.floor(ky) - ay], -1)
knot = (1 - smooth(0.05, 0.12, np.linalg.norm(kf, axis=-1))) * (h21(cx, cy) >= 0.86)
shade = (0.8 + (0.7 - 0.8) * AGE + (0.3 + 0.12 * AGE) * ring) * (1 - split * 0.6) * (1 - knot * 0.5) * (0.9 + 0.1 * n(gx, gy, 2.0, 2.0))
height = ring * 0.0012 - split * 0.003 - knot * 0.001

Image.fromarray((np.clip(shade, 0, 1) * 255).astype(np.uint8), "L").convert("RGB").save("assets/textures/wood_grain.png")
# normal map from the height (metres per pixel along each axis), wrapping at the edges
dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) / (2 * ACROSS / W)
dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) / (2 * ALONG / H)
nrm = np.stack([-dx * 2.0, -dy * 2.0, np.ones_like(dx)], -1)
nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
Image.fromarray(((nrm * 0.5 + 0.5) * 255).astype(np.uint8), "RGB").save("assets/textures/wood_grain_normal.png")
print("baked", shade.mean())
