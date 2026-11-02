# Live animal/solar presentation and complete stones — 2026-11-01

## Report and diagnosis

Pavel reported jerky animal translation and sunlight at x1 after the tree-wind
fix, plus incomplete bank stones. The worker-busy early return still skipped
atmosphere and animal refreshes. The older solar assay was synchronous; its
success did not cover the production worker path. Updating live model readers
before the return would race the coupled tick and was not a valid fix.

## Implementation

- `ForestAnimalsView.capture_frame()` copies completed locomotion polylines,
  times, body transforms, visibility and motion clips only after the worker joins.
  Drawing, posed selection bounds and camera following consume only these copies.
- The live root buffers completed intervals and samples one shared scalar phase
  for the sun and animals, including busy frames and completed-tick boundaries.
  Normal latency is up to two fixed ticks (1 water second at default x1), versus
  one tick for the unchanged synchronous reference. Animal turns also interpolate.
- Weather presentation owns a separate restored committed sampler; rain controls
  refresh its overrides. No worker-owned arrays/field/forcing are read while busy.
- This is bounded interpolation, not extrapolation or independent simulation.
  If compute falls farther behind than the buffer can cover, display stops at
  the latest completed state. High-speed overload is not a smoothness guarantee.
- Pause freezes display. An optional, validated scene presentation window preserves
  animal poses/paths and follow anchors over save/load; older scene saves without
  that optional key still use the existing model-backed initialization. No
  existing user save file was read, rewritten or migrated by this work.
- A regression check caught a shared-dictionary alias: clearing the view's cached
  frame during rebuild also cleared a queued frame. Replacing the cache rather
  than mutating it fixed this; worker and soil-layer controls were rechecked.

## Stones

The mesh was already a whole sphere. All three foliage shaders treated generic
primitive `UV.x` as plant component tags: UV > .5 became an inactive flower and
was discarded. Tags now apply only to tree-enabled plant meshes, never stones.
The closed oval sphere is also less coarse (16 segments, 8 rings). Orientation
uses the bank normal, and its equatorial rim is embedded against the actual
Terrain3D height samples, rather than seating only its centre on an analytic hill.
No terrain, water or obstacle physics was changed.

## Checks

- `check_smooth_motion.gd`: a real Thread is held at coupled-tick entry. Eight
  main-loop samples keep the worker busy while the view's model and root weather
  references are temporarily null. All seven consecutive animal intervals move,
  poses advance, exact picking and display bounds remain available, and all sun
  samples move by about 0.00024754 rad per requested 10 ms frame.
  The old early-return-only path would leave these transforms/light stationary.
- Pause freezes models and display; buffered save/load with a followed target
  round-trips exactly. A NaN in a saved presentation path is rejected atomically.
- Real Forward+ run: 120 rendered/requested 25 ms frames at x1 cross actual tick
  dispatches/completions, including 64 worker-busy frames in the final run. Sun
  increments are 0.000618315–0.000618869 rad with no stationary frame or tick jump.
  This is a scripted continuity assay, NOT a delivered-desktop FPS benchmark.
- Six opposed-side stone PNGs cover all three styles; baseline and pixel views
  were inspected. Complete surfaces reach the ground. The three fungal plots
  were photographed without changing their initialization.
- Final render: `artifacts/smooth-motion-final.log`,
  `artifacts/smooth-motion/report.json`; normal exit 0. Guard telemetry
  `artifacts/smooth-motion-final-gpu.jsonl` peaks at 60 C, below the unchanged
  75 C cutoff. Headless report: `artifacts/smooth-motion/headless-report.json`.
- Full existing model suite produced 26 passing JSONs. Its first aggregation
  caught the cleared-frame runtime error in worker/soil-layer logs despite their
  own PASS markers; affected paths were fixed/rechecked rather than trusting
  process exit codes or overwriting model evidence. Final aggregation and touched
  save/control checks are recorded in `artifacts/smooth-motion-aggregate.log`.
- `gdformat`, targeted `gdlint`, and `git diff --check` pass. Existing headless
  import shutdown RID warnings and Terrain3D deprecation remain separate.

## Fungal clarification and nitrogen question

Pavel clarified with a screenshot that the apparent sand was boar-rooted ground:
not bad fungal initialization. Current initial meadow-mushroom fruit cells have
no sand-majority cells in the site mask, and the initial green meadow image was
inspected. No fungal layout or physiology was changed. Current boar disturbance
tramples plants and recolors the surface but does not mechanically damage fungal
fruit bodies. Implementing that would require an explicit conserved transfer to
soil, not just hiding meshes. This remains an unimplemented ecological coupling.

The UI's organic/labile/mineral N entries are map layers for separate chemical
pools in the same soil cell, not three depth horizons. Soil decomposition moves
35% of decomposed N/P into labile and 65% into mineral stocks; plants withdraw
mineral N/P, coupled fungi consume labile nutrients first and then mineral ones.
NH4/NO3 are not separated. Display units are element stocks in g/m2, not dissolved
concentrations. Checked in `native/soil.cpp`, `native/fungi.cpp`,
`native/soil_extension.hpp`, `scripts/soil_layers.gd`.

## Scope and rollback

Existing Redot Thread/MultiMesh/animation primitives were sufficient; no new
library, service, installation, model timestep, food source or clock forcing.
No running user game was stopped/restarted; new scripts require relaunching it.
Prior unrelated edits remain. Slice rollback sources are outside the project:
`/run/media/pavel/Storage/tmp/forest-smooth-motion-20261101/before/`.
