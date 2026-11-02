#!/usr/bin/env python3
"""Author resource-only low-poly fauna. No physiology or animation curves here."""
from pathlib import Path
import re
from math import sin, cos, sqrt, atan2, degrees

ROOT = Path(__file__).resolve().parents[1]
RECIPES = {}


def recipe(name):
    parts = []
    RECIPES[name] = parts

    def add(shape, size, at, color, role="body", rotation=(0, 0, 0), pivot=None):
        parts.append((shape, size, at, rotation, color, role, at if pivot is None else pivot))

    return add


def eyes(add, head, x, y, z, radius, lining="c9b78f"):
    for sign in (-1, 1):
        add("ellipsoid", (radius*.43, radius*1.12, radius*.98),
            (sign*x, y, z), lining, "head", pivot=head)
        add("ellipsoid", (radius*.31, radius*.80, radius*.71),
            (sign*(x+radius*.16), y, z+radius*.05), "181e19", "eye", pivot=head)
        add("ellipsoid", (radius*.12, radius*.18, radius*.18),
            (sign*(x+radius*.32), y+radius*.19, z+radius*.16), "ece5ce", "eye", pivot=head)


# White hare: arched back, heavy folded hindquarters, narrow forelegs, long feet.
a = recipe("hare")
head = (0, .55, .28)
a("barrel", (.39, .43, .62), (0, .31, -.04), "8e8c78")
a("ellipsoid", (.30, .32, .36), (0, .40, .16), "b6b2a0")
a("ellipsoid", (.25, .28, .30), head, "b9b6a3", "head", pivot=head)
a("taper", (.19, .14, .20), (0, .49, .43), "d4ceba", "head", pivot=head)
for s in (-1, 1):
    hinge = (s*.075, .64, .25)
    a("leaf", (.103, .39, .062), (s*.095, .815, .26), "999b88", "ear", (-7, 0, -s*9), hinge)
    a("leaf", (.061, .31, .016), (s*.095, .815, .292), "b9a18c", "ear", (-7, 0, -s*9), hinge)
    a("leaf", (.055, .094, .025), (s*.118, .969, .275), "424b42", "ear", (-7, 0, -s*9), hinge)
    hip = (s*.145, .28, -.18)
    a("barrel", (.21, .29, .30), (s*.16, .18, -.19), "7e816e", "haunch")
    a("ellipsoid", (.105, .12, .20), (s*.17, .075, -.18), "999b84", "leg", pivot=hip)
    a("taper", (.12, .071, .32), (s*.175, .037, -.02), "b2b29b", "paw", pivot=hip)
    shoulder = (s*.105, .34, .18)
    a("barrel", (.055, .055, .27), (s*.105, .18, .205), "bcb8a1", "leg", (90, 0, 0), shoulder)
    a("taper", (.071, .046, .135), (s*.105, .025, .255), "d4cdb6", "paw", pivot=shoulder)
    a("ellipsoid", (.091, .085, .09), (s*.044, .475, .455), "d7d1bb", "head", pivot=head)
a("ellipsoid", (.12, .14, .12), (0, .29, -.35), "dedbc8", "white")
eyes(a, head, .104, .578, .361, .030)
a("taper", (.046, .034, .045), (0, .492, .521), "766157", "nose", pivot=head)

# Fox: long narrow body and pointed muzzle, cream bib, dark socks, swept brush.
a = recipe("fox")
head = (0, .64, .37)
tail = (0, .40, -.37)
a("barrel", (.35, .36, .79), (0, .44, -.025), "a76232")
a("barrel", (.29, .31, .31), (0, .46, .25), "b9753b", rotation=(-28, 0, 0))
a("leaf", (.24, .32, .10), (0, .44, .393), "d7cdb0", rotation=(8, 0, 180))
a("ellipsoid", (.265, .25, .29), head, "c48242", "head", pivot=head)
a("taper", (.21, .16, .35), (0, .573, .565), "c89659", "head", pivot=head)
a("taper", (.15, .067, .27), (0, .526, .565), "ddd1b2", "head", pivot=head)
a("ellipsoid", (.062, .049, .052), (0, .555, .753), "252c25", "nose", pivot=head)
for s in (-1, 1):
    hinge = (s*.09, .71, .34)
    a("leaf", (.16, .25, .09), (s*.105, .816, .34), "805333", "ear", (2, 0, -s*17), hinge)
    a("leaf", (.10, .17, .018), (s*.106, .813, .389), "c5b695", "ear", (2, 0, -s*17), hinge)
    a("leaf", (.13, .15, .035), (s*.14, .563, .448), "d5c6a5", "head", (0, 0, -s*65), head)
    for z in (-.26, .25):
        hinge = (s*.13, .43, z)
        a("barrel", (.10, .14, .26), (s*.14, .31, z-.02), "a36d3d", "leg", (90, 0, 0), hinge)
        a("barrel", (.063, .065, .25), (s*.14, .155, z), "4b4837", "leg", (90, 0, 0), hinge)
        a("taper", (.091, .064, .16), (s*.14, .037, z+.035), "353d31", "paw", pivot=hinge)
eyes(a, head, .108, .653, .455, .027, "bfa16b")
a("plume", (.29, .30, .72), (0, .265, -.68), "a76231", "tail", (-17, 0, 0), tail)
a("plume", (.20, .20, .30), (0, .155, -.985), "ded6ba", "tail", (-17, 0, 0), tail)

# Bank vole: rounded short ears, russet mantle, pale belly and small blunt snout.
a = recipe("bank_vole")
head = (0, .076, .083)
a("barrel", (.105, .10, .17), (0, .064, -.014), "996544")
a("barrel", (.083, .045, .14), (0, .037, -.006), "bcb39a")
a("ellipsoid", (.074, .068, .081), head, "b58356", "head", pivot=head)
a("taper", (.047, .037, .059), (0, .058, .124), "c0a580", "head", pivot=head)
for s in (-1, 1):
    hinge = (s*.029, .091, .066)
    a("ellipsoid", (.035, .041, .018), (s*.031, .109, .066), "87664c", "ear", pivot=hinge)
    a("ellipsoid", (.023, .028, .007), (s*.031, .109, .076), "bf9f82", "ear", pivot=hinge)
    for z in (-.048, .048):
        hinge = (s*.039, .05, z)
        a("ellipsoid", (.020, .036, .024), (s*.042, .027, z), "a5815b", "leg", pivot=hinge)
        a("taper", (.022, .012, .039), (s*.044, .009, z+.014), "c0a182", "paw", pivot=hinge)
eyes(a, head, .0245, .086, .112, .012, "ab9370")
a("ellipsoid", (.018, .013, .014), (0, .059, .156), "a37f6b", "nose", pivot=head)
a("plume", (.012, .013, .10), (0, .026, -.13), "927e60", "tail", (-8, 0, 0), (0, .04, -.08))

# Boar: high heavy shoulders, long sloping wedge, split hooves and dorsal bristles.
a = recipe("boar")
head = (0, .61, .64)
a("barrel", (.70, .72, 1.30), (0, .65, -.12), "626350")
a("barrel", (.65, .79, .77), (0, .72, .21), "6e705b")
a("taper", (.48, .49, .72), head, "72735c", "head", (12, 0, 0), head)
a("taper", (.32, .27, .44), (0, .455, 1.015), "868369", "head", (8, 0, 0), head)
a("ellipsoid", (.255, .19, .068), (0, .415, 1.25), "65634f", "nose", pivot=head)
for s in (-1, 1):
    a("ellipsoid", (.049, .038, .019), (s*.067, .429, 1.282), "373f33", "nose", pivot=head)
    hinge = (s*.17, .78, .55)
    a("leaf", (.21, .28, .075), (s*.22, .874, .60), "686a55", "ear", (18, 0, -s*42), hinge)
    a("leaf", (.13, .17, .020), (s*.22, .87, .64), "9b9174", "ear", (18, 0, -s*42), hinge)
    a("cone", (.066, .16, .066), (s*.10, .43, 1.075), "c8c3a4", "nose", (5, 0, -s*18), head)
    for z in (-.45, .33):
        hinge = (s*.255, .57, z)
        a("barrel", (.17, .19, .43), (s*.26, .32, z), "5c604e", "leg", (90, 0, 0), hinge)
        a("barrel", (.105, .11, .22), (s*.26, .14, z+.025), "4d5646", "leg", (90, 0, 0), hinge)
        for toe in (-1, 1):
            a("taper", (.057, .10, .19), (s*.26+toe*.033, .055, z+.066), "303d31", "paw", pivot=hinge)
eyes(a, head, .119, .658, .77, .029, "88816a")
for i in range(7):
    a("leaf", (.040, .13+(.03 if i > 3 else 0), .11),
        (0, .987, -.43+i*.105), "454e3f", rotation=(-22, 0, 0))
a("plume", (.028, .028, .24), (0, .65, -.79), "686854", "tail", (-45, 0, 0), (0, .72, -.72))

# Song thrush: buff spotted breast, feather fans, fine bill and real toes.
a = recipe("thrush")
head = (0, .263, .076)
a("barrel", (.15, .185, .225), (0, .158, -.009), "80785a", rotation=(-24, 0, 0))
a("ellipsoid", (.127, .15, .137), (0, .15, .056), "cfbd8e", rotation=(-20, 0, 0))
a("ellipsoid", (.11, .108, .115), head, "918263", "head", pivot=head)
a("taper", (.026, .026, .066), (0, .25, .157), "a89a61", "nose", pivot=head)
a("taper", (.022, .010, .060), (0, .239, .154), "736f4d", "nose", pivot=head)
eyes(a, head, .042, .276, .111, .013, "c4b382")
for s in (-1, 1):
    shoulder = (s*.063, .213, .016)
    wrist = (s*.155, .213, -.020)
    a("feather", (.080, .018, .12), (s*.111, .213, -.006), "706e51", "flight_wing", (0, -s*90, 0), shoulder)
    for i in range(4):
        a("feather", (.024, .007, .097), (s*(.08+i*.021), .210, -.035),
            "8d8562" if i % 2 else "77765a", "flight_wing", (0, -s*8, 0), shoulder)
    for i in range(7):
        root = (s*.155, .213, -.020-i*.0015)
        tip = (s*(.267-i*.012), .213, .015-i*.024)
        mid = tuple((x+y)*.5 for x,y in zip(root,tip))
        length = sqrt(sum((x-y)**2 for x,y in zip(root,tip)))
        yaw = degrees(atan2(root[0]-tip[0],root[2]-tip[2]))
        a("feather", (.028, .006, length), mid, "8d8562" if i % 2 else "77765a",
            "flight_tip", (0, yaw, 0), wrist)
    hip = (s*.033, .107, -.003)
    a("cylinder", (.010, .078, .010), (s*.033, .051, .004), "9e8d67", "flight_leg", (10, 0, 0), hip)
    for toe in (-1, 0, 1):
        a("taper", (.008, .007, .043), (s*.033+toe*.008, .012, .029), "aa9870", "flight_leg", (0, toe*19, 0), hip)
for i in (-1, 0, 1):
    a("feather", (.037, .015, .15), (i*.021, .139, -.166), "777457", "tail", (-12, i*10, 0), (0, .17, -.09))
# Surface points and normals on the rotated breast ellipsoid, not a sticker plane.
for row, angle in enumerate((-.60, -.22, .18, .55)):
    for col in (-1, 0, 1):
        u, v = col*.43, sin(angle)
        w = sqrt(1-u*u-v*v)
        x, y, z = u*.0635, v*.075, w*.0685
        t = -20*3.141592653589793/180
        at = (x, .15+y*cos(t)-z*sin(t), .056+y*sin(t)+z*cos(t)-.001)
        ny, nz = v/.075, w/.0685
        tilt = -degrees(atan2(ny, nz)) - 20
        a("leaf", (.009, .016, .004), at, "615d45", rotation=(tilt, 0, 180))


def vector(v):
    return "Vector3(" + ", ".join(f"{n:.6g}" for n in v) + ")"


def color(v):
    return "Color(" + ", ".join(f"{int(v[i:i+2],16)/255:.6f}" for i in (0, 2, 4)) + ", 1)"


def write(name, parts):
    path = ROOT / "data/animals" / (name + ".tres")
    source = path.read_text()
    source = re.sub(r"^part_\w+ = .*\n?", "", source, flags=re.M)
    keys = ("shapes", "dimensions", "offsets", "rotations", "colors", "roles", "pivots")
    for i, key in enumerate(keys):
        values = [p[i] for p in parts]
        if key in ("shapes", "roles"):
            encoded = "PackedStringArray(" + ", ".join(f'"{v}"' for v in values) + ")"
        else:
            kind, encode = ("Color", color) if key == "colors" else ("Vector3", vector)
            encoded = f"Array[{kind}]([" + ", ".join(map(encode, values)) + "])"
        source += f"part_{key} = {encoded}\n"
    if name == "thrush":
        source = re.sub(r"^wing_shoulder = .*\n?", "", source, flags=re.M)
        source += "wing_shoulder = Vector3(0.063, 0.213, 0.016)\n"
    path.write_text(source)


if __name__ == "__main__":
    for name, parts in RECIPES.items():
        write(name, parts)
        print(name, len(parts), "parts")
