# Ravine, falling trees, wind ripples and lowland mist — 2026-11-05

Baseline: `1a70bda`. Owner-requested continuation of spatial weather work.

## Implemented

- Landscape revision 3: asymmetric variable-width incision, three passive side gullies,
  continuously descending curved thalweg. Source floor 26.41888 m, confluence 14.41888 m;
  source is 9.76256 m above the main channel at the same northing. Existing 40 L/s external
  source is unchanged. Terrain and native bed sample the same analytical surface.
- Static incision/slope exposure masks mineral banks. All initial/recruitment/seed placement
  uses minimum distance to either watercourse. Existing user saves are preserved; older
  incompatible terrain revisions require a new world.
- Detached treefall events capture committed transforms and foliage, show a creaking lean
  and accelerating descent, then one positional impact. Model death/CNP accounting remains
  on its coupled tick. Presentation uses 2.8–4.6 wall seconds and survives pause/save/load.
  Eight positional audio voices prioritize nearer events. Procedural sounds avoid external
  assets; actual listening remains unassessed (tests use Dummy audio).
- Water normals use local canopy-attenuated wind m/s, direction, accumulated advection and
  smoothly interpolated gust strength. Surface stage and water reserves are unchanged.
- One native FogVolume samples submitted ground and coarse weather fields. Cool humid calm
  lowlands collect a shallow drifting layer at night/dawn. Strong wind, warmth, dryness and
  daylight suppress it. Native Forward+ lights/shadows shade the density. No vapor/condensation
  budget is introduced. Existing volumetric/diagnostic switches control the volume.

## Verification

`tools/check.sh` passed; log `artifacts/natural-weather-suite.log`.
`tools/check_spring.gd` additionally checks >=12 m relief, >8 m lateral relief and 101
monotonic thalweg samples. Source-only dry 300 s assay delivers 6.2602133 m³ downstream;
source-off remains dry; water ledger and exact weighted continuation pass.

`tools/preview_ravine.gd`: actual Forward+ overview, bare banks and view downstream from
spring. Images inspected in `artifacts/ravine-natural/`.

`tools/preview_weather_life.gd`: actual Forward+ phase captures, exact paused pose,
exact saved-pose restoration, atomic rejection of NaN event duration, one impact after
continuation and matching picking pose. WAV samples have nonzero RMS and unclipped peaks.
Presentation-only controls preserve all authoritative snapshots byte-for-byte.
Mean RGB differences: calm/gust 0.0086758; dry/humid lowland 0.0502506. Daytime suppression
matches dry control; diagnostic and volumetric-off hide the volume. Final images and JSON:
`artifacts/weather-life/`; log `artifacts/weather-life-preview-final.log`.

`tools/check_wind.gd` additionally advances a staged fall and ripple uniforms on actual
worker-busy early-return frames with vegetation's model pointer removed. Authoritative
models unchanged, pause exact. Log `artifacts/wind-effects-busy-check.log`.

All engine experiments used the 75 C GPU guard; no user save was written or services changed.
The mist comparison fixes lighting and explicitly varies density inputs to isolate the effect.
Its appearance follows a prescribed humidity field; water condensation, breakup physics,
tree collisions and measured storm calibration remain outside this implementation.
