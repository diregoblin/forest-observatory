# Plant LoD, denser forest and active-frame costs

Pavel: FPS collapsed after the surface/mosaic change; pausing makes it smooth.
Requested mesh LoD / distant small-plant sprites and more trees without losing
the new mosaic. Work is local to Forest Observatory; user saves were not edited.

**Final clarification:** Pavel identified this as jerky tree animation at ×1,
not actual frame-rate drops. The wind animation fix and visual follow-up are
recorded at the end. Earlier timing tables below describe the pre-follow-up
paired experiment, not the final mixed-stand initialization.

## Changes

- The existing Godot/Redot MultiMesh, visibility ranges, SubViewport and alpha
  scissor are sufficient; no external library or service is needed.
- Trees retain their original 3D geometry. Other plants use 32 m spatial tiles,
  complete 3D meshes nearby, then two-triangle camera-facing impostors. The
  near/far boundary is species-height-derived, clamped to 45–110 m. Impostors
  end at 220–600 m, after which the existing model-driven ground material
  represents low cover. This changes presentation, never stocks or food.
- `tools/bake_plant_impostors.gd` renders the actual 19 non-tree species from
  four azimuths into separate stem/leaf atlases (64×128 per direction). Assets
  and mesh fingerprints are in `art/plant-impostors/`. Stale/missing assets use
  the full mesh instead of hiding plants. Bake via guarded `tools/run.sh`.
- Far sprites consume the exact same submitted transform, tint and phenology
  state as the near mesh. Autumn/stress/leaf absence remain model-driven.
  Tiny flowers and fruit are omitted at this distance; impostors cast no
  shadows. The switch is tile-based, not a continuous per-plant crossfade.
- Far picking intersects the submitted billboard and rejects transparent
  padding using the baked masks. Partial seasonal stipple is not a pixel-exact
  CPU copy of the fragment shader, as with the pre-existing mesh leaf stipple.
- HUD/follow no longer request full posed animal triangles every rendered
  frame. Each rigidly tagged body part contributes eight deformed AABB corners
  to a conservative display bound. Triangle picking remains exact and on demand.
- Style material discovery is revision-driven, not a per-frame scan through
  every vegetation batch. Rebuilds prune stale material references; impostors
  keep their own cutout shader in all three styles.
- The opening threshold gives forest stands more slope area. For the current
  seed, trees **972 → 1355**, all plants **10117 → 8541**; clearing, wet-meadow
  and sand categories remain. This is a changed initialization, not added trees
  in an existing save. The model timestep and species physiology did not change.

## Evidence

CPU inventory before LoD: `artifacts/render-budget-mosaic.json`: 15,062,681 plant
triangles per full geometry pass, including 6,483,664 from tufted hairgrass alone.
The preceding 3482-plant layout had 4,455,300 plant triangles. These are budgets,
not counters of actually rendered GPU triangles.

Controlled rendered comparison: `tools/probe_mosaic_fps.gd`, native X11 desktop,
Forward+ / RTX 3070 Ti, 1440×900, pixel style, cap 60. Both paired runs use the
**same old map and 10117 plants**, with matching initial plant hash 3634960949.
The baseline reconstructs the old 4×4 batching/full-mesh path and old HUD/follow
callers from the rollback source; it is not a historical git commit. Source
meshes, model code, seed, map, camera and shader style are shared.

Files: `artifacts/mosaic-desktop-before.json/.log`,
`artifacts/mosaic-desktop-after.json/.log`, with PNGs for each view.
Five warm-up draws, 18 samples per paused phase, 120 per active phase. Runs
were sequential, with no own simulation tests running alongside. Each sample
checks drawable/non-minimized state; unavailable counts are zero. Both physical
outputs reported DPMS on after the native comparison. Guard 75 °C was active.

| View | Paused world GPU mean, ms before → after | Rendered primitives before → after |
| --- | --- | --- |
| Above canopy | 8.787 → 2.532 | 39,299,024 → 4,714,922 |
| Creek | 6.636 → 1.916 | 33,618,941 → 4,852,243 |
| Hare viewpoint | 4.636 → 1.815 | 26,138,784 → 3,370,842 |

Primitive counts include repeated passes/shadows and non-plant scene geometry.
These reductions do **not** mean the capped game FPS multiplied by the same factor.

At active ×1 both versions stayed near the 60 FPS cap in this short initial-world
test. Hare-view frame max was 28.391 → 23.520 ms, main-process max 10.531 → 5.046 ms.
However canopy-view frame max was **37.045 → 40.954 ms**: active hitches are not
universally eliminated. The maximum profiled `_refresh_observation` call fell
3123 → 400 μs. This supports the display/picking separation, not a claim that
the entire reported FPS collapse has been reproduced and fixed.

Final denser map: `artifacts/mosaic-desktop-denser.json/.log`, 8541 plants,
1355 trees. Active ×1 frame p95 17.313/17.964 ms for canopy/hare views, maxima
34.711/28.612 ms. GPU mean 2.734/2.410 ms. The simulation completed eight ticks
by the second active phase. This is a short smoke profile, not long-run or
accelerated-world validation. The user's problematic speed was asked separately.

Earlier Xvfb cost-isolation logs are retained but are **not** native game-FPS
claims: they showed roughly 30 rendered FPS despite small GPU times. The native
comparison above supersedes them for desktop cadence.

## Checks and visual inspection

- `tools/check.sh` completed its checks, but its final aggregation initially
  failed because the boar insect fixture assumed any nonzero pool was edible.
  The denser map moved its first plant into a cell below the species' threshold.
  The fixture now selects an **existing, dry, finite** pool meeting the actual
  threshold, without adding food. `mosaic-boars-recheck.log` then passed, including
  conservation, negative controls and 40-tick exact continuation. Final aggregate
  validation: all 26 result JSONs pass; relevant runtime logs have no ERROR.
- Whole-world restore/continuation, worker equivalence, picking, controls,
  food-web, climate/soil/CNP checks passed. No timestep/clock changes.
- `check_plant_lod.gd`: all 19 assets match source geometry; all submitted near/far
  slots and phenology states match; every posed animal corner is inside the cheap
  display bound; a known-wrong tiny bound fails. Solid/transparent billboard ray
  hits are tested separately; plant snapshot is unchanged.
- Actual Forward+ `plant-lod-render.log`: PASS, three styles at 12/75/150 m.
  PNGs `artifacts/lod-*.png`; pixel mid-range and baseline far frame inspected.
  Guard telemetry for this isolated render sampled up to 56 °C; normal exit.
- Native overview/camera PNGs are saved with each comparison. `gdformat`, targeted
  `gdlint`, and `git diff --check` pass. Headless editor import retains existing
  shutdown RID-leak diagnostics, without script/parse errors.

Rollback for existing sources:
`/run/media/pavel/Storage/tmp/forest-fps-mosaic-20261101/before/`.
All prior unrelated uncommitted changes were preserved. No automatic restart,
publication, service/configuration changes, or user-save edits were performed.

## Final user clarification and visual follow-up

Pavel supplied the earlier green/autumn valley image as the visual reference:
partly mixed stands with dominant species, green ground and a separate visual
texture for unspecific fine grass, without adding all of it as named meshes.

- Placement now preserves each site's previous total forest weight, distributing
  eligible tree choice as **65% dominant / 35% local admixture**. This is a sampling
  target, not an exact fraction in every finite stand. Current seed: **1331 trees**,
  8541 total plants, and no trees in the clearing/meadow/sand dominant categories.
  Of 28 sampled stands with ≥10 trees, 25 have a majority species; all retain
  admixture. Observed dominant fractions range 0.389–0.833, median about 0.67.
  The check rejects both a uniform ten-species mix and pure monoculture.
- The existing layered terrain material adds continuous fine-turf coloration
  from site weights, smooth noise and seasonal greenness. It is explicitly
  decorative: no independent carbon/food/water stock, mesh population or grass
  regrowth system was introduced. Named plants still contribute actual cover;
  sand stays exposed; snow/diagnostic layers retain their original ordering.
- Forward+ previews include ordinary valley camera frames in spring and autumn:
  `artifacts/site-surface-render/07-reference-spring.png` and
  `08-reference-autumn.png`; autumn reference and overview inspected.

### The reported 'FPS' problem was quantized wind

The old foliage `weather_time` came from `_display_climate()` and was only
submitted after the worker-busy early return. The presentation clock clamps
pending time to one 0.5 s coupled step, so a busy model tick freezes the wind
phase and subsequent updates jump it. At ×1 this is visible as tree motion
stepping while the camera and render frames themselves remain smooth.

`ForestVegetation.advance_weather(dt)` now runs **before** the busy-worker return,
using only cached, already-submitted wind targets and materials, never mutable
model reads. The visual sway phase advances in real presentation seconds each
frame; direction/strength targets ease over 0.35 s. It freezes at pause and does
not become a strobe at ×600. Authoritative weather, growth, C/N/P, hydrology and
clock coupling remain untouched. The three near foliage shaders share the same
phase. Distant cutouts are intentionally static small representations.

`check_plant_lod.gd` exercises an actual busy `Thread` with no model writes:
four 10 ms scene updates must keep the early-return branch busy and advance
the phase by exactly 10 ms each, then a paused update must not advance it.
This rejects the previous busy-worker freeze. It also retains geometry,
transparent-padding picking, posed-bound containment and immutable-plant checks.

### Interruption recovery

After the interrupted turn, no Redot/guard/test processes remained. The saved
`mixed-green-suite.log` confirmed completed aggregation; the 26 current result
JSONs were read back and all passed. `wind-lod-check.log` recorded the busy-worker
and pause regression test's normal exit. Neither run was blindly repeated.

A short **Forward+** run of `check_plant_lod.gd` after the wind fix also passed:
`artifacts/wind-lod-render-recovery.log`, nine PNGs `artifacts/lod-*.png` across
three styles and distances. Pixel mid-range and the mixed-green autumn valley
frame were inspected. Guard telemetry peaked at **56 °C**, normal exit 0.
The first preview launch used an unavailable system `xvfb-run` wrapper and did
not start the engine; the existing project `tools/preview_isolated.sh` was used
successfully instead. No system packages were installed.

This verifies the wind phase during the worker-busy branch, pause behavior,
and shader/render compatibility. It is not a new native-desktop FPS benchmark
or a human judgement of animation smoothness. The mixed distribution applies
to newly initialized worlds; no existing user save was rewritten.
