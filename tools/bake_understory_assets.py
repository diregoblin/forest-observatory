#!/usr/bin/env python3
"""Own botanical cutouts and data-only visual recipes. Never edits ecology fields."""
import math
import re
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]


class Raw(str):
    pass


def v(x, y, z):
    return Raw(f"Vector3({x}, {y}, {z})")


def c(r, g, b):
    return Raw(f"Color({r}, {g}, {b}, 1)")


GREEN = c(.29, .43, .22)
STEM = c(.38, .43, .24)
CREAM = c(.91, .87, .69)


def shoot(height, radius=.004, **kw):
    result = dict(shape="shoot", height=height, radius=radius, color=STEM)
    result.update(kw)
    return result


def card(width, length, **kw):
    return dict(shape="leaf_card", foliage=True, color=GREEN,
                scale_start=v(width, length, length), **kw)


def flower(shape, size, **kw):
    result = dict(shape=shape, component_kind=Raw('&"flower"'), foliage=True,
                  color=CREAM, scale_start=v(size, size, size))
    result.update(kw)
    return result


RECIPES = {
    "balsam": ("serrated", [
        shoot(.64, .006, leaf_count=10, leaf_size=Raw("Vector2(.055, .15)"),
              bend=v(.012, .025, .018), leaf_color=c(.28, .44, .19)),
        flower("spur", .038, count=6, offset=v(0, .28, 0), step=v(0, .045, 0),
               radial_offset=.085, turn=2.39996, rotation_degrees=v(-12, 0, 12),
               color=c(.96, .69, .16), petiole_length=.08),
    ]),
    "meadowsweet": ("lobed", [
        shoot(.89, .004, count=3, radial_offset=.028, turn=2.39996,
              bend=v(.025, .02, .015), leaf_count=4, leaflet_pairs=2,
              leaf_size=Raw("Vector2(.15, .29)"), leaf_color=c(.30, .43, .22)),
        flower("panicle", .16, count=3, radial_offset=.04, turn=2.39996,
               offset=v(0, .87, 0), cluster_members=23),
    ]),
    "raspberry": ("serrated", [
        shoot(1.30, .011, count=5, radial_offset=.045, turn=1.256637,
              scale_step=v(0, .045, 0), tip_offset=v(.43, -.12, .05), bend=v(.16, .13, .02),
              leaf_count=7, leaflet_pairs=1, leaf_size=Raw("Vector2(.17, .30)"),
              leaf_color=c(.30, .43, .23), color=c(.40, .27, .18)),
        dict(shape="aggregate", component_kind=Raw('&"fruit"'), color=c(.65, .16, .19),
             count=5, radial_offset=.35, offset=v(0, .99, 0), turn=1.256637,
             scale_start=v(.034, .034, .034)),
    ]),
    "wood_sorrel": ("obcordate", [
        shoot(.12, .0015),
        card(.062, .072, count=3, offset=v(0, .12, 0), turn=2.094395,
             rotation_degrees=v(-8, 0, 0), card_fold=.10),
        shoot(.165, .001),
        flower("star", .017, offset=v(0, .167, 0), petal_count=5),
    ]),
    "wood_anemone": ("palmate", [
        shoot(.17, .0017, bend=v(.009, 0, 0)),
        card(.075, .09, count=3, offset=v(.008, .09, 0), turn=2.094395,
             rotation_degrees=v(6, 0, 0)),
        flower("star", .028, offset=v(0, .172, 0), petal_count=6),
    ]),
    "lily_of_valley": ("broad", [
        shoot(.25, .0018, tip_offset=v(.025, -.012, 0), bend=v(.026, 0, 0)),
        card(.105, .29, count=2, turn=3.141593, offset=v(0, .007, 0),
             rotation_degrees=v(-67, 0, 0), card_curve=.16),
        flower("bell", .015, count=6, offset=v(.027, .11, .013), step=v(0, .022, 0),
               radial_offset=.014, turn=2.39996, rotation_degrees=v(0, 0, 18)),
    ]),
    "male_fern": ("fern_lance", [
        card(.31, .92, count=9, turn=.698132, offset=v(0, .03, 0), radial_offset=.012,
             rotation_degrees=v(-48, 0, 0), card_curve=.12, card_fold=.07),
    ]),
    "ostrich_fern": ("fern_vase", [
        card(.32, 1.30, count=10, turn=.628319, offset=v(0, .025, 0), radial_offset=.018,
             rotation_degrees=v(-67, 0, 0), card_curve=.15, card_fold=.08),
    ]),
    "bracken": ("fern_triangle", [
        shoot(.56, .0035, bend=v(.03, .02, 0)),
        card(.53, .63, count=3, turn=2.094395, offset=v(0, .56, 0),
             rotation_degrees=v(-15, 0, 0), card_curve=.09),
    ]),
    "tufted_hairgrass": ("blade", [
        card(.012, .67, count=15, turn=2.39996, radial_offset=.025,
             rotation_degrees=v(-62, 0, 0), card_curve=.17, card_fold=.14),
        card(.010, .48, count=11, turn=2.39996, radial_offset=.035,
             rotation_degrees=v(-35, 0, 0), card_curve=.18),
        shoot(.78, .0016, count=7, radial_offset=.04, turn=2.39996,
              tip_offset=v(.045, 0, 0), bend=v(.018, 0, 0)),
        flower("panicle", .11, count=7, radial_offset=.09, turn=2.39996,
               offset=v(0, .76, 0), cluster_members=13, component_kind=Raw('&"ordinary"'),
               color=c(.64, .58, .36)),
    ]),
}


def mask(shape, output):
    size, ss = 512, 2
    image = Image.new("RGBA", (size * ss,) * 2, (235, 241, 217, 0))
    draw = ImageDraw.Draw(image)

    def polygon(points, value=220):
        draw.polygon([((.5 + x) * size * ss, (1 - y) * size * ss) for x, y in points],
                     fill=(value, value, value, 255))

    if shape.startswith("fern_"):
        draw.line([(size * ss / 2, size * ss * .98), (size * ss / 2, size * ss * .02)],
                  fill=(173, 173, 173, 255), width=3 * ss)
        for j in range(19):
            t = .12 + j * .044
            if shape == "fern_triangle":
                width = .48 * (1 - t) ** .8
            elif shape == "fern_vase":
                width = .44 * math.sin(math.pi * t) ** .7 * t ** .35
            else:
                width = .43 * math.sin(math.pi * t) ** .75
            for sign in [-1, 1]:
                # Lobed pinnae leave actual transparent air, not painted dark gaps.
                points = [(0, t - .012)]
                for k in range(13):
                    x = (k + 1) / 13
                    points.append((sign * width * x, t + .07 * x + (.014 if k % 2 else -.002)))
                points.extend([(sign * width, t + .085), (0, t + .022)])
                polygon(points, 188 + j % 4 * 15)
    elif shape == "palmate":
        polygon([(0, 0), (-.12, .14), (-.45, .28), (-.26, .40), (-.48, .66),
                 (-.25, .64), (-.30, .91), (-.09, .72), (0, .99), (.09, .72),
                 (.30, .91), (.25, .64), (.48, .66), (.26, .40), (.45, .28), (.12, .14)])
    elif shape == "obcordate":
        polygon([(0, .02), (-.36, .40), (-.48, .69), (-.43, .88), (-.24, .98),
                 (-.10, .94), (0, .79), (.10, .94), (.24, .98), (.43, .88),
                 (.48, .69), (.36, .40)])
    else:
        points = []
        for sign in [-1, 1]:
            side = []
            for j in range(65):
                t = .02 + j / 64 * .96
                power = .65 if shape == "broad" else .85
                width = .47 * math.sin(math.pi * t) ** power
                if shape == "blade":
                    width *= (.96 - .65 * t)
                if shape == "serrated":
                    width *= .86 + .14 * (j % 2)
                if shape == "lobed":
                    width *= .78 + .22 * math.cos(t * math.tau * 3)
                side.append((sign * width, t))
            points.extend(side if sign < 0 else reversed(side))
        polygon(points)
    # Fixed vein shading; the shader supplies the species' actual display tint.
    draw.line([(size * ss / 2, size * ss * .97), (size * ss / 2, size * ss * .06)],
              fill=(168, 168, 168, 255), width=2 * ss)
    image.resize((size, size), Image.Resampling.LANCZOS).save(output)


def encode(value):
    if isinstance(value, Raw):
        return re.sub(r"(?<![\w\d])(-?)\.(\d)", lambda m: m[1] + "0." + m[2], str(value))
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, str):
        return f'"{value}"'
    return str(value)


def write_species(name, shape, modules):
    path = ROOT / "data/plants" / (name + ".tres")
    old = path.read_text()
    body = old.split("[resource]\n", 1)[1]
    visual_keys = {"modules", "canopy_texture", "canopy_color", "canopy_leaf_span_m"}
    body = "\n".join(line for line in body.splitlines()
                     if line.split(" = ")[0] not in visual_keys)
    chunks = ['[ext_resource type="Script" path="res://scripts/plant_definition.gd" id="1"]',
              '[ext_resource type="Script" path="res://scripts/plant_module.gd" id="2"]',
              f'[ext_resource type="Texture2D" path="res://art/herbs/{shape}.png" id="mask"]',
              '[sub_resource type="QuadMesh" id="Card"]\nsize = Vector2(1, 1)',
              '[sub_resource type="SphereMesh" id="Unit"]\nradius = 1.0\nheight = 2.0\nradial_segments = 6\nrings = 2']
    ids = []
    for i, source in enumerate(modules):
        props = dict(source)
        if props["shape"] == "shoot":
            height, radius = props.pop("height"), props.pop("radius")
            mesh = f"Axis{i}"
            chunks.append(f'[sub_resource type="CylinderMesh" id="{mesh}"]\n'
                          f'height = {height}\nbottom_radius = {radius}\n'
                          f'top_radius = {radius * .28}\nradial_segments = 5')
        else:
            mesh = "Card" if props["shape"] == "leaf_card" else "Unit"
        module_id = f"M{i}"
        ids.append(f'SubResource("{module_id}")')
        chunks.append(f'[sub_resource type="Resource" id="{module_id}"]\n'
                      'script = ExtResource("2")\n' + f'mesh = SubResource("{mesh}")\n' +
                      "\n".join(f"{key} = {encode(value)}" for key, value in props.items()))
    body += '\ncanopy_texture = ExtResource("mask")\n'
    body += 'modules = Array[ExtResource("2")]([' + ", ".join(ids) + '])\n'
    header = f'[gd_resource type="Resource" script_class="ForestPlantDefinition" load_steps={len(chunks)+1} format=3]\n'
    path.write_text(header + "\n".join(chunks) + "\n[resource]\n" + body)


def main():
    output = ROOT / "art/herbs"
    output.mkdir(parents=True, exist_ok=True)
    for shape in sorted({shape for shape, _ in RECIPES.values()}):
        mask(shape, output / (shape + ".png"))
    for name, (shape, modules) in RECIPES.items():
        write_species(name, shape, modules)
    print(f"Wrote {len(RECIPES)} visual recipes; ecology fields preserved")


if __name__ == "__main__":
    main()
