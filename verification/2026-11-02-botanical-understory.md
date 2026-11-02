# Botanical understory and thin-leaf shadows — 2026-11-02

## Authorized scope

Pavel reported flickering shadows on meadowsweet and balsam, then explicitly
asked to remake those models, raspberry, and the entire herbaceous layer using
combinations of meshes and fixed cards. This covers eight herb species, tufted
hairgrass and raspberry, not a rewrite of the ecosystem or the other shrubs.
The already-running human game was not restarted or controlled.

## Implementation

One mesh builder dispatches reusable resource-defined shapes to
`ForestBotanicalGeometry`. There are no runtime species-name branches:

- Curved tapered shoots carry leaves at real points on their axes; compound
  leaves use connected rachises and paired leaflets.
- Folded, segmented, fixed leaf cards use our own deterministic alpha masks.
  They never face the camera. Male fern, ostrich fern and bracken have different
  blade profiles and arrangements; sorrel has obcordate leaflets, anemone lobed
  leaves, lily broad leaves, hairgrass fine arched blades.
- Meadowsweet has loose cream panicles; balsam yellow hollow flowers with spurs;
  lily hanging hollow bells; anemone/sorrel radial petals. Raspberry uses arching
  brown canes, trifoliate leaves and aggregate fruit rather than solid globes.
- Existing flower/fruit component tags, leaf/stress/autumn state and wind remain
  on the common material path. Near/mid models share the same cutout/picking
  coordinates. Far colour and normal atlases are rebuilt, with shared leaf-light
  response rather than an unlit billboard.

Recipes and masks: `tools/bake_understory_assets.py`, `art/herbs`, the ten changed
`data/plants/*.tres`. Botanical vertex colours are converted from authored sRGB
once, rather than appearing bleached against the tree materials.

## Shadow diagnosis and fix

The original two-specimen Forward+ fixture had dark speckling with SSAO disabled,
but not with the solar shadow map disabled. Raising normal bias did not solve it.
The final depth bias is .3 instead of the engine default .1; normal bias remains
2 and shadows are still cast and received.

The crown-shell mip heuristic is inappropriate for a single fern/leaf card:
lowering alpha threshold as holes become unresolved filled a whole rectangle in
the shadow map. UV.y=3 cards now retain the .5 cutout threshold. Crown shells
retain their previous behavior. Cards use consistent winding and two-sided
normals, no temporal/random alpha dither and no global disabling of shadows.

Reference guidance checked: Godot's maintained
[lights and shadows documentation](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html),
2026-11-02, specifically bias/normal-bias and PSSM tradeoffs. The project's actual
Redot 26.3 render, not that documentation alone, is the verification target.

## Verification

- `check_herb_geometry.gd`: all ten species have finite normalized geometry,
  smaller mid LoD, actual transparent/solid mask regions, source-mesh and source-
  image immutability, and identical output after renaming to an unknown species.
- `artifacts/herb-biology-unchanged.json`: all 29 resource bodies were compared
  to scoped rollback copies, excluding visual fields. Biology, scenario weights,
  age, reproduction, climate/soil/hydrology and model clocks were not changed.
- Short Forward+ equal-height gallery: all ten models, all three material styles,
  oblique views, mid LoD, autumn/fruit, winter skeleton, real shader wind and a
  small alternating solar-angle shadow control. These are seasonal presentation
  controls, not ecosystem growth experiments.
- Real paused forest preview: near plants, valley/creek, pixel/painterly styles,
  unchanged authoritative model snapshots and all 29 valid atlas entries.
- `artifacts/botanical-suite.log`: all 34 engine checks plus the existing native
  checks passed, zero reported errors. Final import followed the final atlas bake.
- `artifacts/understory-live-final.log`: post-import Forward+ preview passed;
  final near raspberry/fern and creek images inspected. All model snapshots were
  unchanged and all 29 colour/normal atlas entries loaded.
- Controlled fixed-camera, wind-zero alternating .015-degree solar-angle test:
  .1 bias changed 98/31500 ROI pixels above .025 RGB, .3 changed zero. Mean RGB
  delta fell from .0002630 to .00005855. This is a small controlled jitter test,
  not a promise of zero aliasing at every camera angle.
- Final colour-correct gallery: `artifacts/understory-colour-final.log`;
  final bake: `artifacts/herbs-impostor-final.log` (29 species).

Final per-template triangle counts (not per-frame draw totals or an FPS claim):

| Species | Near | Mid |
| --- | ---: | ---: |
| Raspberry | 2600 | 1390 |
| Wood sorrel | 238 | 120 |
| Tufted hairgrass | 2604 | 1072 |
| Balsam | 1456 | 732 |
| Male fern | 252 | 90 |
| Ostrich fern | 280 | 100 |
| Bracken | 156 | 62 |
| Wood anemone | 168 | 90 |
| Lily of the valley | 896 | 460 |
| Meadowsweet | 2112 | 966 |

The first scratch versions were needlessly expensive (e.g. grass 9084 triangles).
Straight fine rachises and tiny drupelets/florets now use small reusable forms,
not heavily tessellated cylinders/spheres. This does not establish a whole-forest
FPS improvement, nor eliminate every possible shadow alias at every angle.

## Reproduction / rollback

Run asset authoring only when changing the visual recipes:
`python3 tools/bake_understory_assets.py`; import via guarded `tools/run.sh`,
then bake `tools/bake_plant_impostors.gd` via `tools/preview_isolated.sh`, reimport,
and run `tools/check.sh`. Render fixtures are `preview_understory.gd` and
`preview_understory_live.gd`; all engine launches remain GPU-guarded at 75 C.

Pre-change source/data and manifest: `/run/media/pavel/Storage/tmp/forest-herb-shadows-20261102/`.
Restore only scoped sources and data, then regenerate/import the old atlases;
never reset this dirty checkout. New presentation appears after restarting the
game. Normal startup still creates a new world, without automatic save loading.
