#!/usr/bin/env python3
"""Bake our own seamless fine-turf material on CPU (NumPy + Pillow).

This is presentation, not another population or C/N/P stock. Shapes are
periodically splatted on a torus; normals use metric height differences with
wrap boundaries. No photograph, generated image model or third-party asset.
"""

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 512
TILE_M = 1.6
SEED = 20261102
OUT = Path(__file__).resolve().parents[1] / "art/ground-turf"


def smooth_noise(rng, cells):
    grid = rng.random((cells, cells))
    t = np.arange(SIZE) * cells / SIZE
    i = t.astype(int)
    f = t - i
    f = f * f * (3 - 2 * f)
    a = grid[i[:, None], i[None, :]]
    b = grid[i[:, None], (i[None, :] + 1) % cells]
    c = grid[(i[:, None] + 1) % cells, i[None, :]]
    d = grid[(i[:, None] + 1) % cells, (i[None, :] + 1) % cells]
    return (a * (1 - f) + b * f) * (1 - f[:, None]) + (
        c * (1 - f) + d * f
    ) * f[:, None]


def bake():
    rng = np.random.default_rng(SEED)
    moss = smooth_noise(rng, 32)
    broad = smooth_noise(rng, 7)
    height = .0015 * moss
    color = np.empty((SIZE, SIZE, 3), dtype=float)
    color[:] = [.105, .145, .055]
    color *= (.7 + .6 * moss + .18 * broad)[..., None]
    dry_mask = np.zeros((SIZE, SIZE))
    for _ in range(3400):
        cx, cy = rng.uniform(0, SIZE, 2)
        angle = rng.uniform(0, 2 * np.pi)
        length = rng.uniform(.035, .17) * SIZE / TILE_M
        width = rng.uniform(.0035, .011) * SIZE / TILE_M
        radius = int(np.ceil(length / 2 + width * 2 + 2))
        xi = np.arange(int(cx) - radius, int(cx) + radius + 1)
        yi = np.arange(int(cy) - radius, int(cy) + radius + 1)
        dx, dy = np.meshgrid(xi - cx, yi - cy)
        u = dx * np.cos(angle) + dy * np.sin(angle)
        v = -dx * np.sin(angle) + dy * np.cos(angle)
        t = u / length + .5
        bend = rng.uniform(-1, 1) * width * np.sin(np.pi * np.clip(t, 0, 1))
        half_width = width * np.maximum(0, 1 - t) ** .65
        edge = np.abs(v - bend) / np.maximum(half_width, .05)
        alpha = np.clip((1 - edge) * width + .5, 0, 1)
        alpha *= np.clip((t + .01) * length, 0, 1)
        alpha *= np.clip((1 - t) * length, 0, 1)
        ridge = np.sqrt(np.clip(1 - edge * edge, 0, 1))
        dry = rng.random() < .13
        tint = np.array([.38, .32, .13] if dry else [.24, .34, .095])
        tint *= rng.uniform(.70, 1.30)
        tint = tint[None, None, :] * (.7 + .35 * ridge[..., None])
        target = np.ix_(yi % SIZE, xi % SIZE)
        color[target] = color[target] * (1 - alpha[..., None]) + tint * alpha[..., None]
        leaf_height = rng.uniform(.002, .010) + .003 * ridge
        height[target] = height[target] * (1 - alpha) + leaf_height * alpha
        dry_mask[target] = dry_mask[target] * (1 - alpha) + float(dry) * alpha
    # Metric derivatives: the texture's X/Y axes are world X/Z. The shader
    # transforms these slopes into the Terrain3D tangent frame on real slopes.
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) / (2 * TILE_M / SIZE)
    dz = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) / (2 * TILE_M / SIZE)
    normal = np.stack([-dx, np.ones_like(dx), -dz], axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    ao = np.clip(.80 + 16 * height, .80, 1)
    roughness = .90 + .06 * dry_mask
    # Shader samples albedo with source_color; encode linear reflectance once.
    srgb = np.where(color <= .0031308, color * 12.92, 1.055 * color ** (1 / 2.4) - .055)
    albedo = np.dstack([srgb, height / .016])
    packed = np.dstack([normal[..., 0] * .5 + .5, normal[..., 2] * .5 + .5, roughness, ao])
    return albedo, packed


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    albedo, normal = bake()
    hashes = {}
    for name, values in [("albedo-height.png", albedo), ("normal-roughness-ao.png", normal)]:
        path = OUT / name
        pixels = np.round(np.clip(values, 0, 1) * 255).astype(np.uint8)
        Image.fromarray(pixels).save(path)
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    # Upright cutout, in the same palette. Nine curved tapered blades, not a
    # photo billboard: the renderer places three fixed intersecting planes.
    rng = np.random.default_rng(SEED + 1)
    y, x = np.mgrid[0:256, 0:128]
    x = (x + .5) / 128
    growth = 1 - (y + .5) / 256
    rgb = np.empty((256, 128, 3))
    rgb[:] = [.19, .29, .07]
    alpha = np.zeros((256, 128))
    for _ in range(11):
        length = rng.uniform(.4, .97)
        t = np.clip(growth / length, 0, 1)
        base, tip = rng.uniform(.35, .65), rng.uniform(.07, .93)
        curve = base + (tip - base) * t + rng.uniform(-.15, .15) * np.sin(np.pi * t)
        width = rng.uniform(.012, .027) * np.maximum(0, 1 - t) ** .7
        edge = np.abs(x - curve)
        a = np.clip((width - edge) * 128 + .5, 0, 1) * (growth < length)
        tint = np.array([.25, .36, .10]) * rng.uniform(.8, 1.2)
        ridge = .85 + .2 * np.clip(1 - edge / np.maximum(width, .001), 0, 1)
        rgb = rgb * (1 - a[..., None]) + tint * ridge[..., None] * a[..., None]
        alpha = np.maximum(alpha, a)
    srgb = np.where(rgb <= .0031308, rgb * 12.92, 1.055 * rgb ** (1 / 2.4) - .055)
    path = OUT / "upright-tuft.png"
    Image.fromarray(np.round(np.clip(np.dstack([srgb, alpha]), 0, 1) * 255).astype(np.uint8)).save(path)
    hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
    manifest = {
        "seed": SEED, "size": SIZE, "tile_m": TILE_M,
        "provenance": "Original CPU procedural turf; inspired by lucillenull's node-texture example, not copied pixels.",
        "reference": "https://x.com/lucillenull/status/2117207091849138551/photo/1",
        "channels": {"albedo-height": "sRGB RGB, linear A=height/0.016m", "normal-roughness-ao": "linear RG=normal XZ*0.5+0.5, B=roughness, A=AO"},
        "sha256": hashes,
    }
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
