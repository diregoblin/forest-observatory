# Shared spatial wind · 2026-11-05

## Implemented

One seeded, advected field supplies nearby/mid-distance plant meshes, upright
terrain grass and listener wind ambience. Velocity is in m/s on a 32² grid,
updated every 0.1 wall second and linearly interpolated. A separate 64² field
stores canopy attenuation and height. Settings own both resolutions and cadence.

Submitted tree/shrub crown contributions update incrementally, including size,
leaf fraction and removal of fallen plants. Closed stands approach 20% of open
wind near the ground; velocity recovers toward the canopy height. Wind transport
uses accumulated displacement across direction changes. This is an isotropic
stand-scale scenario: terrain wakes and atmospheric conservation equations are
outside this model. Water/ecological forcing remains unchanged.

The three visual styles and grass share `forest_wind.gdshaderinc`. Roots remain
anchored; a smooth saturation bounds world displacement below 0.75 m without
flattening all large gusts at a hard limit. Near/mid picking samples velocity and
shelter once after its broad-phase hit and applies the same deformation. Far
atlas silhouettes retain their original static geometry.

Wind uses presentation wall time and stops on pause. A busy model worker cannot
freeze it or become a source for mutable model reads. This display field is not
saved. The new filtered-noise ambience follows local velocity at listener height;
existing positional bird calls and animal rustles remain intact.

## Checks

- `tools/check.sh`: PASS (native water/soil/fungi; plants, fauna, workers,
  observer, whole-world save/restore, controls and all registered checks).
- `tools/check_wind.gd`: PASS. Seed repeatability, spatial packet variation,
  exact downwind grid translation, rejected backward translation, calm,
  canopy attenuation/leaf loss/removal, bilinear centre/edge controls,
  bounded deformation and root/fallen controls, displaced-triangle picking,
  frozen pause, detached view while worker-busy and unchanged authoritative
  model snapshots. Queued clock requests are checked separately.
- `check_observation.gd` and `check_plant_lod.gd`: PASS again after the deferred
  deformation preparation change. Alpha selection, near/mid/far states and
  original phenology/source geometry are preserved.
- `tools/preview_wind.gd`: actual Forward+, 960×600, all three visual styles,
  40 fixed-camera frames over four display seconds. Authoritative snapshots
  remain byte-identical. Maximum CPU/GPU velocity discrepancy 0.02051 m/s
  (HDR readback precision); local deformation discrepancy 0.000933 m.
- `tools/check_wind_live.gd`: PASS with real asynchronous tick completions:
  22 busy frames, 5 committed ticks / 5 completion frames over 2.507 display
  seconds. Pause freezes wind and authoritative snapshots. Eight prepared
  picking shapes exercised; slowest shape query 4.381 ms in this short assay.
- Wind noise: 3 s loop, RMS 0.19988, peak 0.78445, near-zero DC; no clipped
  samples. Listener envelope is checked against the displayed field. Audio
  driver was Dummy in automated previews; subjective listening remains open.
- `gdformat`/`gdlint` and `git diff --check`: clean.

## Cost and boundaries

Velocity texture generation on the CPU measured approximately 0.5–0.9 ms per
100 ms update in these runs (the upper sample ran alongside other checks).
Incremental canopy edits and dirty shelter uploads add separate presentation
work. No new draw calls or geometry are introduced.

`tools/benchmark_wind.gd` uses saved source shaders from baseline commit
`8f7fa05` and the current shaders, alternated in eight warmed ABBA blocks. Both
use the same frozen scene: 1,286 calls, 7,862,302 primitives, default pixel mode,
960×600, RTX 3070 Ti. The mean of block medians was 3.422 ms for original source
and 3.017 ms for spatial wind. Individual block medians varied from about 2.38
to 4.65 ms, so these short measurements establish no stable slowdown and do not
support an FPS/speedup claim. World and composition GPU time are both included.
The first helper-only A/B was superseded by this original-source comparison.

GPU watchdog remained active at 75 °C; previews/benchmark reached at most 46 °C.
No thermal or telemetry stop, driver/power changes, user-save writes or running
window replacement occurred. Terrain3D's existing assets warning appeared;
one live fixture also emitted an ObjectDB-at-exit warning. No script/render
errors remain in the completed runtime checks. Headless editor imports parsed
successfully but reported Dummy renderer/font RID cleanup errors on exit; the
full-suite import and final import showed the same counts. The import criterion
in `check.sh` checks parsing/loading separately from editor shutdown cleanup.

Spatial precipitation, humidity transport, directional wakes and ecological
microclimate feedback are separate future extensions.

## Reproduction and local evidence

```bash
./tools/check.sh
GPU_GUARD_LOG=artifacts/spatial-wind-gpu.jsonl ./tools/preview_isolated.sh --script res://tools/preview_wind.gd
./tools/preview_isolated.sh --script res://tools/check_wind_live.gd
FOREST_WIND_BASELINE=/path/to/baseline GPU_GUARD_LOG=artifacts/spatial-wind-benchmark-gpu.jsonl ./tools/preview_isolated.sh --script res://tools/benchmark_wind.gd
```

The baseline tree must contain the original `shaders/pixel_foliage.gdshader` and
`shaders/turf_cards.gdshader` (for this comparison, commit `8f7fa05`). The actual
rollback used here is `/run/media/pavel/Storage/tmp/forest-wind-20261105/`, outside
the Godot project. Git keeps the durable source baseline.

Local ignored evidence:

- `artifacts/wind-check.json`, `wind-check.log`
- `artifacts/spatial-wind/report.json`, `benchmark.json`, `live.json`
- `artifacts/spatial-wind/style-*-*.png`, `frame-*.png`, `gusts.mp4`
- `artifacts/spatial-wind-*-gpu.jsonl`, `spatial-wind-gpu.jsonl`
- `artifacts/spatial-wind-suite.log`

The four-second H.264 preview has no audio track. Render images were inspected.
