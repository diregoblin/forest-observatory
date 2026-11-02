# Thrush flight rig — 2026-11-02

## Scope

Pavel liked the new fauna and explicitly requested a proper thrush flight
animation. The old short folded wings merely rotated by ±0.7 radians about one
hinge; they could not unfold into a flight silhouette. No animal model biology,
XZ trajectory, speed, flight height, resource decisions or simulation clocks
are changed. The running human game was not restarted or controlled.

## Implementation

- The thrush resource now assembles an inner wing, secondary feathers and a
  seven-primary fan per side. The unfolded geometry has a shoulder and wrist.
  The same one-merged-mesh/material path remains, 4416 triangles per bird
  (previously 3520), not a separate draw call for every feather.
- Resource `wing_shoulder` and generic roles `flight_wing`, `flight_tip` and
  `flight_leg` define the rig. No renderer branch checks a species identifier.
  CUSTOM0 retains the wrist/leg hinge, and the parent shoulder is mirrored from
  the resource and cached with the view, safe while the coupled model worker runs.
- Shared curves add `flight` and `wrist`; seven non-flight clips preserve their
  old seven channels exactly, with zeroes in both new channels. The fly clip
  has a .24 s stylized cycle with a broad asymmetric shoulder stroke and delayed
  wrist flexion. This is an artistic animation, not calibrated bird biomechanics.
- Wings yaw/pitch against the sides on the ground. In flight the primaries
  spread, the wrist flexes, feet tuck and the body tilts forward. Vertex positions
  and normals use wrist → shoulder → body transforms. CPU picking/bounds use
  the identical transform order and blend, including across takeoff/landing.
- Articulated birds cross-fade poses for .18 display seconds. The interpolation
  starts at the last visible pose, follows the existing display clock, does not
  advance models, and resets on rewind/rebuild. Other animals retain their old
  playback path. Runtime authored-library playback and CPU sampled channels
  remain consistent, with blended GPU uniforms and CPU pose overridden together.

Sources: `tools/author_fauna.py`, `data/animals/thrush.tres`,
`scripts/animal_motion.gd`, `scripts/animals_view.gd`,
`shaders/animal_motion.gdshader`. Editable Blender actions, JSON samples and
Redot AnimationLibrary regenerated together using `build_animal_motion.py` and
`build_motion_library.gd`; CPU-only isolated Blender launch used the GPU guard.

## Verification

- `bird-flight-check.json`: folded span 0.16646 m, spread span 0.53987 m;
  selected tip vertical travel 0.24915 m. Both wrists stay attached through 98
  side/phase cases. Maximum sampled 5 ms transition movement is 0.03003 m,
  no initial takeoff/landing pose pop, no stale transition after rewind.
  These numbers describe this authored model, not measured thrush anatomy.
- `thrush-model-invariance.json`: other four animal resource files remain byte
  identical; thrush nonvisual resource fields unchanged. Seven non-flight JSON
  clips retain their previous original samples/durations exactly.
- `preview_thrush_flight.gd`: 120 actual Forward+ frames, 30 fps, four-second
  animation video. Key folded/upstroke/downstroke/landing frames inspected.
  Camera-stage elevation is explicitly presentation-only and labelled, not a
  claim that its takeoff trajectory comes from the animal model. Model snapshot
  unchanged; every captured pose remains inside displayed selection bounds.
- `preview_bird_flight_live.gd`: a genuinely moving bird chosen after three real
  coupled ticks, rendering an actual committed route in the main forest. View
  model reference detached during sampling (busy-worker-safe read path), all
  authoritative models unchanged during display. No fabricated world route.
- `tools/check.sh`: all 36 engine checks passed, together with the native
  checks and benchmark; no script/runtime errors. This includes 600 fauna
  geometry poses, short approaches, observer selection and busy-worker views.
  Final receipts: `artifacts/thrush-flight-suite.log`,
  `artifacts/thrush-flight-verification.json`,
  `artifacts/thrush-flight-final-preview.log`,
  `artifacts/bird-flight-live-final.log` and both preview `report.json` files.
  The first live-preview attempt failed during resource loading; removing
  unnecessary eager animal-class type hints in that standalone fixture fixed
  its load order. Production files did not require a workaround. The failed
  log is retained separately from the successful final run.

## Reproduce and rollback

Use guarded `tools/run.sh` for import/library building/headless checks and
`tools/preview_isolated.sh --script res://tools/preview_thrush_flight.gd` for the
render. Video is CPU-encoded with libx264. The fail-closed thermal limit remains
75 C; no system, driver, fan, power or scheduler changes were made.

Scoped pre-change files are outside the project:
`/run/media/pavel/Storage/tmp/forest-thrush-flight-20261102/`.
Restore only scoped files and reimport; never reset the dirty working tree.
