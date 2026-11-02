# Fauna models — 2026-11-02

## Scope and implementation

Pavel explicitly asked to update animal models while the botanical understory
was being finished. All five existing species are included. The human's running
game was not restarted, controlled, or overwritten; code appears on next launch.
Normal startup still creates a new world, without an implicit save/autoload path.

`tools/author_fauna.py` authors only `part_*` fields in the five animal resources.
The runtime never checks species names. Existing ellipsoids/boxes/cylinders/cones
are joined by five reusable closed eight-sided lofts in `animal_geometry.gd`:
barrel, taper, leaf, plume and feather. Model/view/resource separation, one
merged indexed mesh per individual, shader/material sharing and stable inherited
build/length/coat/ear variation remain intact. No new per-part draw calls.

- Hare: arched back, folded hindquarters, long feet, volumetric pointed ears
  with lining and dark tips, light cheek pads and small recessed eyes.
- Fox: narrow body, pointed muzzle and jaw, cream cheek/bib, dark socks and feet,
  large brush with a pale tip.
- Bank vole: russet mantle, pale belly, small rounded two-tone ears, blunt snout,
  short thin tail and four small feet. Studio views magnify it substantially.
- Song thrush: buff spotted breast, bill/jaw, layered folded wing feathers,
  three-feather tail and fine toes. This preserves the stylized existing wing
  motion; it is not a new anatomically calibrated flight rig.
- Boar: high shoulders, sloping head/snout, nostrils and tusks, split hooves,
  dorsal bristles and attached short tail.

The optional `part_pivots` array supplies shared anatomical hinges: lining and
ear tip use the ear base, shin/paw one leg joint, brush and pale tip one tail base,
wing and feathers one shoulder. Legacy resources with no pivot array retain the
automatic fallback. The first head component is now the skull pivot, rather than
the last cheek/muzzle component. Existing CPU and shader affine transforms and
the eight authored animation curves were not changed. Recipe colours are sRGB
and decoded exactly once into vertex colours.

Inherited ear length/angle also acts on the entire group about that base. The
old per-piece elongation left a 0.0524177 m gap in a two-box connected-ear control;
the corrected affine group transform retains exact contact at three gene settings
(measured maximum gap zero). `artifacts/fauna-ear-negative.log` records the old
policy failing; `artifacts/fauna-geometry-final.log` records the same control
passing along with the 600 pose cases. This is a geometry regression fixture,
not a biological measurement of ear morphology.

## Verification

- `check_fauna_geometry.gd` checks all five species at three inherited appearance
  settings, all eight clips at five time points: 600 posed cases. Finite vertices,
  normalized outward loft normals, index/tag count, CPU/AnimationPlayer shader
  channels, conservative follow bounds and exact posed picking bounds are checked.
  Resource renaming to an unknown species leaves mesh arrays identical; ear
  linings share real hinges. View sampling does not mutate model snapshots.
- `artifacts/fauna-biology-unchanged.json`: all non-`part_*` resource fields match
  the pre-redesign copies, ignoring whitespace. Initial populations, diet, energy,
  traits, timings, reproduction, movement and model clocks were not edited.
- `artifacts/fauna-source-hashes.json` records the final resource/view/geometry
  and unchanged animation-source hashes.
- Forward+ studio fixture `preview_fauna.gd`: front and side views of all species,
  equal-height gallery and all eight existing clips. Models remain unchanged.
  Large-plan inspection corrected floating eye placements, breast spots and the
  boar tail/tusks before the final render. Gallery is not the real size ratio.
- `preview_fauna_live.gd` shows real committed individuals of all five species at
  their original locations in the paused forest, with the actual pixel renderer,
  ground, vegetation and lighting. Entire model snapshots are unchanged.
- `artifacts/fauna-suite.log`: the entire 35-engine-check suite and existing
  native checks passed. After the final presentation-only ear-group correction,
  geometry, short-approach animation and observation/picking checks were rerun
  separately. The correction does not change any model or resource interface.
  The headless observer check skips Dummy-renderer MultiMesh buffer readback;
  posed mesh/bounds tests and actual Forward+ previews supplement it. No claim
  of physical mouse-click validation is made.
- Final renders after that correction: `artifacts/fauna-models-coherent-ears.log`
  and `artifacts/fauna-live-coherent-ears.log`; no engine errors, model snapshots
  unchanged. Final images were inspected. All experiments used the 75 C guard.

| Species | Parts | Triangles per individual |
| --- | ---: | ---: |
| Hare | 30 | 2744 |
| Fox | 33 | 2704 |
| Bank vole | 24 | 2448 |
| Song thrush | 44 | 3520 |
| Boar | 43 | 3496 |

These are per-individual mesh counts, not an FPS or population-cost measurement.
Meshes are more detailed, not claimed to be cheaper than the old models. The
earlier biology optimization remains separate from this visual change.

## Reproduce / rollback

For recipe edits run `python3 tools/author_fauna.py`, then guarded import,
`tools/check.sh`, and `tools/preview_isolated.sh --script res://tools/preview_fauna.gd`.
All engine/GPU experiments use the existing fail-closed 75 C guard; no fan,
driver, power or service configuration is changed.

Pre-redesign sources/resources are outside the project:
`/run/media/pavel/Storage/tmp/forest-fauna-models-20261102/`.
Restore only the scoped animal files; never reset the dirty working tree. The
separate botanical report documents the plant rollback and atlas rebuild path.
