# Nested canopy shells — 2026-11-02

Pavel asked to replace the detached outer leaf plates in the earlier isolated
study with several alpha-masked shells, to consult online solutions, and to
give birch and oak different leaves. This is still a specimen study, **not a
live-world replacement**. No model, species resource, save or normal-world
material was edited. Original meshes are rebuilt before/after and checked for
byte-identical arrays.

## Sources actually read

- [Godot: transparency and alpha antialiasing](https://docs.godotengine.org/en/stable/tutorials/3d/standard_material_3d.html#transparency):
  alpha scissor is appropriate for foliage, writes opaque cutout surfaces,
  supports shadows, and avoids blended-transparency sorting problems.
- [Valve Developer Community: Vegetation](https://developer.valvesoftware.com/wiki/Vegetation):
  describes shell texturing, masks/atlases and the pixel-overdraw tradeoff.
  It describes stacked cards generally, not this particular nested crown mesh.
- [Discussion of Airborn foliage](https://www.reddit.com/r/unrealengine/comments/9kuiu6/changing_foliage_normals_for_smoother_look/):
  distinguishes a visible inner shell from a normal-transfer helper shell.
  This is a community explanation, not evidence of WrongNebula's shader.

Keenable search/page retrieval and official Godot documentation were usable;
Firecrawl returned credit exhaustion and several direct page fetches failed.
No third-party shader code or textures were copied. The earlier exact-demo
source limitation still applies; do not attribute this method to its author.

## Implementation

- `tools/bake_canopy_masks.py` draws our own deterministic tileable RGBA masks.
  Data profiles control the outline, leaf dimensions, twig density and repeat:
  birch has small pointed/serrated blades; oak larger elongated lobed blades.
  These are stylized approximations, not botanical scans. Both use one baker.
- `art/canopy-study/{birch,oak}-leaves.png`, `profiles.json` and
  `leaf-profiles.png` are generated fixtures. Texture RGB represents grayscale
  variation, not material albedo; empty texels have light RGB to avoid black
  fringes. Mipmaps are generated when the study loads the masks.
- `tools/preview_canopy_shells.gd` preserves the original module placements,
  transforms and bark; each spherical foliage module gets four nested lobed
  surfaces at radii 1/.93/.86/.79. Layers are rotated and their UVs phase-shifted
  independently. No camera-facing planes or detached geometry plates are added.
  This isolated builder explicitly retains UVs/UV2; the shared plant builder
  intentionally uses UV.x for phenotype tags and does not preserve mesh UVs.
- `shaders/study_canopy_shells.gdshader` discards mask alpha below .5, without
  writing ALPHA or entering alpha blending. COLOR.a remains a geometry tag,
  never opacity. Normals follow each crown lobe; actual sun direction drives
  shading. Palette uniforms use `source_color` so sRGB colours are not mistaken
  for linear albedo. Shells cast actual masked shadows; the older plate control
  retains its coarse proxy. Thus screenshots compare **whole methods**, not
  palette-only, geometry-only or performance-isolated effects.

## Checks and judgement

GDScript formatter/lint passed. Actual Forward+ preview captured 12 images
after frame_post_draw: two light directions, a no-cutout negative control,
and actual camera azimuths 0/90/180 degrees per species. Success criterion:
changing light direction and disabling cutouts must change the image. The
same right-specimen image-difference pipeline rejects an unchanged picture;
it includes shadows and is **not** a style score or pure leaf-only metric.

`artifacts/canopy-shells/report.json`: passed, original arrays unchanged.

| Specimen | Plate triangles | Shell triangles | Light change | No-cutout change |
|---|---:|---:|---:|---:|
| Birch | 8,088 | 10,392 | .02765 | .00705 |
| Oak | 4,392 | 5,832 | .04676 | .00955 |

These are mesh counts, not measured forest performance. The shells are not
claimed cheaper: four layers plus two-sided drawing increase overdraw. No
sustained frame benchmark, movement/temporal shimmer check, LoD, phenology,
snow, wind, picking or main-world integration was attempted.

Inspected the final oak comparison and birch 90-degree camera PNGs. The nested
leaf texture reads more continuously from the side than detached tangent
plates; real holes reveal deeper layers. It remains an obviously rounded,
somewhat dense shell-built crown, with stretch near sphere poles. The original
few-lobe morphology is still visible. This is a better direction for this
specific side-view objection, **not finished species-specific tree geometry**
or a match to the reference.

- [Oak: plates / shells / shells rotated](../artifacts/canopy-shells/oak-02-right-light.png)
- [Birch: actual side camera](../artifacts/canopy-shells/birch-side-090.png)
- [Leaf masks](../art/canopy-study/leaf-profiles.png)

Reproduce:

```bash
python3 tools/bake_canopy_masks.py
GPU_GUARD_LOG=artifacts/canopy-shells-final-gpu.jsonl \
  ./tools/preview_isolated.sh --script res://tools/preview_canopy_shells.gd
```

Final guard maximum **62 C**, normal exit 0; cutoff 75 C and fail-closed telemetry
unchanged. Earlier unshipped study files were copied to
`/run/media/pavel/Storage/tmp/canopy-shells-before-20261102/`; they were not edited.
