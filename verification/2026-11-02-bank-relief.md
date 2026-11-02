# Optional dry-bank microrelief — 2026-11-02

## Decision

**VALIDATED as a bounded presentation feature**, not a terrain/erosion model.
The normal forest now has **Options → Вид → Микрорельеф берегов**.
It defaults **off** and lasts for the current run, like the existing frame limit.
No ocean, particle grass or global SSAO was enabled.

The question was whether Terrain3D 1.1's native displacement buffer can add
small coherent shore detail without introducing an overlay, LoD cracks, stale
water/snow masks or changes to authoritative world state. The isolated spike
lives outside the project at
`/run/media/pavel/Storage/Yandex.Disk/OpenClaw-workspace/.tmp/openclaw-spikes/terrain-bank-displacement`.
The shipped implementation was rewritten: only static detail is cached, all
model-driven masks are applied at draw time.

## Implementation and primary sources

- Native 1.1.0 buffer atlas addressing and start/end clipmap geomorph:
  [main.glsl](https://github.com/TokisanGames/Terrain3D/blob/v1.1.0-stable/src/shaders/main.glsl),
  [displacement_buffer.glsl](https://github.com/TokisanGames/Terrain3D/blob/v1.1.0-stable/src/shaders/displacement_buffer.glsl).
- [terrain_3d.cpp](https://github.com/TokisanGames/Terrain3D/blob/v1.1.0-stable/src/terrain_3d.cpp):
  `_process_proxy()` refreshes the buffer only after a snapped target-position
  change; public `snap()` invalidates its last position. A custom uniform change
  alone is NOT an update request.
- [terrain_3d_material.cpp](https://github.com/TokisanGames/Terrain3D/blob/v1.1.0-stable/src/terrain_3d_material.cpp):
  shared public uniforms are forwarded to both materials. No vendor code changed.

`shaders/bank_buffer.gdshader` caches rounded, deterministic, world-locked clods
resolvable on the near 25 cm lattice. The base ecological shader reads its Y
channel with native atlas/LoD addressing. Vertical offset is bounded by **±4 cm**;
there is no XZ displacement. Both geometry and normal perturbation use the same
masked and geomorphed height field. Far levels tend to zero rather than ending
at a hard distance ring. Authoritative height and field UVs remain undisplaced.

Masks read existing sand habitat alpha, previous/current displayed water depth
and interpolation alpha, snow water, and diagnostic mode. Snow/underwater/soil
maps bypass relief. These masks live in the vertex shader, not the cache, so a
stationary camera cannot retain an old wet/dry surface. The composition root
resynchronizes the display alpha after water uploads as well as during ordinary
and busy-worker frames. No model is read by that display synchronizer.

Enabling the option sets native tessellation to 2 and invalidates the buffer
once through `snap()`. Disabling returns to 0. The mesh is not rebuilt when the
camera enters/leaves individual sand patches. Existing turf normal/AO maps
remain unchanged; this does not invent an extra AO simulation.

## Checks and boundaries

Run the actual Forward+ presentation fixture:

```sh
tools/preview_isolated.sh --script res://tools/preview_bank_relief.gd
```

Receipt: `artifacts/bank-relief/report.json`; log: `artifacts/bank-relief.log`.
The comparisons use identical paused models, camera and texture settings.
The zero-offset negative control keeps tessellation enabled, isolating relief
from the base mesh subdivision. A repeat control measures incidental changes.

| Assay | Mean absolute RGB difference |
|---|---:|
| Repeat zero-offset control | 0 |
| ±4 cm relief vs zero offset | 0.002820108 |
| Snow: relief on/off | 0 |
| Wet surface: relief on/off | 0 |
| No-sand habitat: relief on/off | 0.0000000161 |
| Soil diagnostic: relief on/off | 0 |

A second dynamic-mask control supplies deliberately different dry previous / wet
current maps, then changes alpha without moving the camera or invalidating the
buffer: dry detail reappears. All model snapshots remain byte-identical. Two
fractional base surface heights remain exactly 13.4651298522949 and
14.2743101119995 m. The HUD signal route toggles level 0/2 and back successfully.
Twelve movement views cross the buffer snaps and near LoDs; representative
images were inspected for holes and discontinuities. Native and pixel views of
the populated forest, and the visible options panel, were also inspected.
This is not an exhaustive camera-path or temporal-shadow validation.

The bare-bank fixture submits **268,536 → 368,768 primitives** (+37.3%) and
**104 → 120 draw calls**. This cost is for native mesh subdivision/buffer work,
not an extra bank overlay. It is NOT a universal forest cost: the populated
fixture submits about 6.33 million primitives. Short GPU timing samples vary
even between equal controls (8.34 vs 5.83 ms); **no FPS benefit or precise GPU
penalty is established**. Hence the default-off quality option.

Initial spike failures were useful: changing cached buffer uniforms under a
stationary camera produced no effect and was correctly rejected by the assay.
The first viewing pose also intersected a rising bank; the fixture now anchors
camera height to the actual rendered surface. Neither failure is a successful
verification run. The successful isolated log is
`artifacts/bank-displacement-refresh.log`, not the earlier dry/debug attempts.

The physics, planting/picking base surface and hydrology remain unchanged.
Consequently, sub-4-cm visual contact differences are possible. **A true ravine
or a changed river bank must be built into the common height field and checked
against water, animals and vegetation, not painted into this shader.** No new
ravine was generated in this task. No user saves or running game were modified.

## Live worker/render check

```sh
GPU_GUARD_LOG=artifacts/bank-live-guard.jsonl tools/preview_isolated.sh --script res://tools/preview_bank_live.gd
```

`artifacts/bank-live.json`: **passed**, 90 actual rendered frames, **89 busy-worker
frames**, **14 completed ticks**. The quality setting was toggled off/on while
the worker still owned all models. Display-depth texture identity and water
interpolation alpha matched the water view in every sampled frame, including
an upload reset. Guard telemetry peaked at **55 °C**, cutoff unchanged at 75 °C.
This is an interface/concurrency smoke check, not an ecology-speed benchmark.

The default-off screenshot is pixel-identical to the pre-integration baseline
(`artifacts/bank-displacement/00-shipped-bank.png` vs
`artifacts/bank-relief/00-default-off.png`, mean/max RGB difference 0).

## General checks

`tools/check.sh > artifacts/bank-relief-suite.log 2>&1` completed successfully:
**37/37 engine checks**, native hydrology/fungi/soil checks and the standard
native benchmark. No runtime/script errors in required logs. The existing
editor Dummy-renderer/font RID shutdown warnings are not a Forward+ shader
result; actual GPU fixtures above are separate. No model/native code changed.
