#!/usr/bin/env python3
"""Own deterministic, tileable leaf masks for an isolated shell study (not scans)."""
import json
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

OUTPUT = Path(__file__).resolve().parents[1] / "art/canopy-study"
PROFILES = [
    dict(name="birch", label="Берёза: острый зубчатый лист", groups=34,
         width=30, length=37, lobes=0, repeat=[8.0, 4.0]),
    dict(name="oak", label="Дуб: вытянутый лопастной лист", groups=24,
         width=32, length=59, lobes=4, repeat=[6.0, 3.0]),
]


def outline(profile):
    """Blade along Y, base 0 / tip 1, round oak lobes or birch teeth."""
    sides = []
    for sign in [-1, 1]:
        points = []
        for i in range(41):
            t = i / 40
            if profile["lobes"]:
                half = .43 * math.sin(math.pi * t) ** .42
                half *= .76 + .24 * math.cos(t * math.tau * profile["lobes"])
            else:
                half = .5 * (t / .35 if t < .35 else (1 - t) / .65)
                half *= .86 + .14 * (i % 2)
            points.append((sign * half, t))
        sides.extend(points if sign == -1 else reversed(points))
    return sides


def bake(profile):
    size, supersample = 512, 3
    rng = random.Random(20261102)
    # White RGB in empty texels: no black fringe in filtered mipmaps.
    image = Image.new("RGBA", (size * supersample,) * 2, (245, 245, 245, 0))
    draw = ImageDraw.Draw(image)
    blade = outline(profile)

    def line(points, color, width):
        for dx in [-size, 0, size]:
            for dy in [-size, 0, size]:
                draw.line([((x + dx) * supersample, (y + dy) * supersample)
                           for x, y in points], fill=color, width=width * supersample)

    def leaf(base, angle, length, width):
        c, s = math.cos(angle), math.sin(angle)
        points = [(base[0] + c * x * width - s * y * length,
                   base[1] + s * x * width + c * y * length) for x, y in blade]
        value = rng.randrange(165, 256)
        for dx in [-size, 0, size]:
            for dy in [-size, 0, size]:
                draw.polygon([((x + dx) * supersample, (y + dy) * supersample)
                              for x, y in points], fill=(value, value, value, 255))

    for _ in range(profile["groups"]):
        center = (rng.uniform(0, size), rng.uniform(0, size))
        angle = rng.uniform(0, math.tau)
        direction = (math.cos(angle), math.sin(angle))
        tip = (center[0] + direction[0] * 75, center[1] + direction[1] * 75)
        line([center, tip], (160, 160, 160, 255), 2)
        for j in range(9):
            t = (j // 2 + 1) / 5
            base = (center[0] + direction[0] * 68 * t,
                    center[1] + direction[1] * 68 * t)
            a = angle - math.pi / 2 + (-.9 if j % 2 else .9)
            scale = rng.uniform(.75, 1.12)
            leaf(base, a, profile["length"] * scale, profile["width"] * scale)
    image = image.resize((size, size), Image.Resampling.LANCZOS)
    image.save(OUTPUT / (profile["name"] + "-leaves.png"))
    alpha = image.getchannel("A")
    coverage = sum(v >= 128 for v in alpha.getdata()) / (size * size)
    return image, coverage


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    board = Image.new("RGB", (1080, 670), "#cacbb8")
    draw = ImageDraw.Draw(board)
    font = ImageFont.truetype("/usr/share/fonts/TTF/DejaVuSans.ttf", 23)
    cases = []
    for i, profile in enumerate(PROFILES):
        image, coverage = bake(profile)
        x = 20 + 540 * i
        preview = Image.new("RGBA", image.size, "#344d42")
        preview.alpha_composite(image)
        board.paste(preview.convert("RGB"), (x, 65))
        draw.text((x, 20), profile["label"], font=font, fill="#34463f")
        draw.text((x, 595), "Альфа-вырезы, собственный рисунок", font=font, fill="#34463f")
        cases.append(dict(source="res://data/plants/" + profile["name"] + ".tres",
                          mask="res://art/canopy-study/" + profile["name"] + "-leaves.png",
                          repeat=profile["repeat"], coverage=coverage))
    board.save(OUTPUT / "leaf-profiles.png")
    (OUTPUT / "profiles.json").write_text(json.dumps(cases, indent=2) + "\n")
    print(json.dumps(cases, indent=2))


if __name__ == "__main__":
    main()
