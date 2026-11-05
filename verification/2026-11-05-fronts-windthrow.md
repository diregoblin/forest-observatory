# Moving fronts, cloud transport, local rain wind and windthrow · 2026-11-05

## Scope

Pavel requested wind-driven clouds, coarse spatial temperature/humidity/wind
fronts, local wind for drops, and tree resistance/windthrow in hurricanes.
Starting HEAD `7522bfa`; working tree was clean. Source rollback is that commit;
the task pointer is outside the project at
`/run/media/pavel/Storage/tmp/forest-fronts-20261105/`.
No running user window, user save, engine, service or GPU settings were changed.

## Implementation

`ForestWeatherFront` is the pure shared forcing. Air-mass transitions are spaced
85 hydrological seconds apart; each front moves along its incoming wind with
spatial delay `dot(position-centre, incoming_direction)/front_speed`. The default
8 m/s transport and 59.5 s smooth transition give an approximately 476 m band.
Directions cover the full compass. Neighbouring transitions blend sequentially
when spatial bands overlap; each interpolation remains bounded and continuous.
The default 16² weather grid and front speed belong to `ForestSettings`.

The fields prescribe local cloud cover, rainfall potential, temperature anomaly,
relative humidity and wind. Humidity modulates local plant evaporative demand; root demand and growth
sample the coarse local forcing. Watershed evaporation, soil kinetics, animal
weather responses, snow storage and snowmelt remain regional. Relative humidity has no
separate conserved vapour reservoir, condensation or pressure feedback.

Cloud deck displacement integrates the smooth weather wind multiplied by the
same seeded open-air gust envelope averaged at nine plot points. Deterministic
5 s midpoint segments and per-front checkpoints keep trajectory evaluation
bounded within an interval; the derived cache is reconstructed from seed/time.
Direction changes retain position. Low cloud density, local cover, native rain,
sky and caster share world coordinates. Upper wisps retain their noise source
and follow the accumulated transport. Deck translation is coherent, with no
local stretching/fluid-parcel advection. The view owns its trajectory cache and
native sampler; only the immutable source tile is shared with the model.

Rain/snow particles sample the same two interpolated wind textures and canopy
shelter as the plants and listener. Ground height comes from the immutable
hydrological bed texture. Horizontal velocity relaxes toward local wind;
vertical fall speed stays prescribed. This rendering does not move water
between authoritative cells. Snow particle intensity and liquid-only ripple
intensity have separate masks; snow cannot create liquid rain rings.

Tree resources expose `wind_resistance_m_s` as a scenario reference threshold.
Height, crown size, leaf area, stress and snow load modify resistance. Standing
dead trees have reduced strength and retain background biological decay.
Local wind/gust excess squared-load hazard is integrated over **hydrological SI
seconds**, separately from accelerated biological growth. C/N/P transfer through
the existing death/deadwood path, and fallen yaw follows the local wind. These
thresholds and hazard coefficients have no species-level field calibration.
Trunk/root mechanics, a staged falling animation and fracture/impact sound are
outside this implementation.

Vegetation/drop/audio gusts use smooth presentation wall time, including busy
worker frames. Cloud motion and windthrow use model time. At accelerated speed,
their gust phases can differ. Pause freezes both clocks. HUD weather samples
the observer location; relative humidity is available in its existing tooltip.

Weather v3 validates source, dimensions, weather resolution and front speed.
Existing v1/v2 ledgers migrate; old v2 fixed cloud velocity is replaced by the
new trajectory after loading. Tree saves lacking the new resistance trait
migrate while retaining all earlier configuration checks. Future evolution
uses the updated scenario.

## Checks and observed results

- `tools/check.sh`: PASS on the full-compass version, including native water/soil/
  fungi, plant/animal models, observer, exact worker reference, whole-world
  save/restore, controls and all registered checks. Log: `fronts-compass-suite.log`.

- `tools/check_fronts.gd`: PASS. Exact downwind arrival delay and a rejected
  backward-time control; spatial temperature range 3.3963 °C across the sampled
  front series; all eight compass sectors; continuous cloud position through a
  wind turn. Minimum displacement/wind alignment 0.999979 in selected samples.
- Independent double-precision cloud/rain threshold and coarse-grid sampling
  agree within 4.24e-22 m/s for the selected front. Liquid rates and summed mean
  agree. Snow particle cores remain present while the liquid-only mask is zero.
- A 240-tree controlled stand exposed to 35 m/s for 120 hydrological seconds:
  68 live trees fall; a 45 m/s-resistance stand has zero falls. One second of
  exposure gives zero live falls; 12 m/s gives zero live falls. This is an assay
  of the chosen coefficients, not an estimate for a real stand or hurricane.
  The standing-dead control gives 240 falls in the storm versus 3 background
  falls under calm forcing with the same biological elapsed time.
- C/N/P totals are conserved, fallen yaw follows wind, stressed/taller trees
  have lower thresholds, and post-fall save/RNG continuation is exact. Legacy
  weather/tree configuration migration and malformed configuration rejection pass.
- `tools/check_rain_wind_render.gd`: actual Forward+ and the production particle
  shader. Opposite local velocities yield +14.20 / -14.20 px drift over the assay;
  shelter reduces drift to 4.00 px; disabled spatial wind gives 0.00 px. The
  source particle motion was not replaced by a probe reimplementation.
- `tools/preview_fronts.gd`: actual Forward+ at 960×600. Selected cloud density,
  local cover and rain mask GPU/CPU differences are respectively <0.000514,
  <0.000466 and <0.000428. Model snapshots stay unchanged. Three saved forest
  images were inspected; existing rain/drop control images were inspected too.
- `tools/preview_spatial_rain.gd`: PASS after transport change, 60 frames,
  visible/hidden drop control, native mask agreement, unchanged model snapshots.
- `tools/check_spatial_rain_live.gd`: real busy-worker frames and completed ticks,
  joined pause, unchanged frozen models/masks and liquid-input residual
  approximately 4.44e-16 m³. Separate view/model trajectory ownership is asserted.
- The first full suite exposed loss of rare snow-load windfall below the new
  load threshold. Its existing rare-event term was retained in SI hazard units;
  `check_place_memory.gd` then passed. Known winter/null controls remain useful.
- GDScript formatting and `git diff --check` pass. Lint passes for the new/small
  touched scripts. Existing large `trees.gd` still exceeds lint file length and
  has pre-existing global-definition order diagnostics.
- GPU guard stayed active at 75 °C; recorded maximum across task render runs
  was 44 °C. No thermal/telemetry stop occurred. Existing Terrain3D asset and
  occasional ObjectDB-at-exit warnings remain; no script/render errors occur in
  the completed rendering checks.

## Reproduction

```bash
./tools/check.sh
./tools/run.sh --headless --script res://tools/check_fronts.gd
./tools/preview_isolated.sh --script res://tools/preview_fronts.gd
./tools/preview_isolated.sh --script res://tools/check_rain_wind_render.gd
./tools/preview_isolated.sh --script res://tools/check_spatial_rain_live.gd
```

Ignored evidence: `artifacts/fronts-check.json`, `fronts-check-verified.log`,
`fronts/render.json`, `fronts/rain-wind.json`, `fronts/*.png`,
`fronts-compass-render.log`, `fronts-particles.log`, `fronts-live-final.log`,
`fronts-compass-suite.log` and task GPU JSONL logs. Short render GPU means are
fixture observations; there is no A/B FPS or broad performance claim.
