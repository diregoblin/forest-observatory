# Cloud-linked spatial precipitation · 2026-11-05

## Implemented

The lower sky deck, native cloud caster and precipitation share an immutable
periodic 512² density tile. The source is generated offline by
`tools/build_cloud_density.gd`, committed as a lossless numerical PNG, and sampled
with texel-centred periodic bilinear interpolation. Default span is 4096 m;
scenario transport is (1.2, 0.45) m/s on hydrological seconds. The upper wispy deck
keeps its decorative source. Ground-level gusts have their own display clock.

At every fixed tick, `ForestWeather` evaluates cloud cores at water-cell centres
at the tick midpoint. The potential peak is 30 mm/h. A smooth core weight gives
local rates in m/s; transparent fringes receive zero. Rates are not rescaled to
maintain a regional mean. `Hydro::advance_field` accepts the full double-precision
array, sums its actual external volume, and bounds CFL using the peak rate.
Persisted hydraulic coefficients stay unchanged.

Precipitation and liquid accumulators are area-mean water equivalents. Cold
precipitation enters the existing mean snow reservoir. Warm degree-day melt is
uniform and limited by that reservoir. Atmospheric humidity, condensation,
canopy interception, fall-time transport and spatial snow storage remain open.
Animal weather responses and track erosion still use the regional front.

Presentation samples the immutable source on its interpolated water clock. A
1024² HDR cloud field serves the sky/caster; the normalized native water-grid
mask feeds particle thinning and water rings. No rendered field feeds model
water. Clouds and masks stop on pause. The transient liquid array is consumed
by hydrology before downstream climate caches; it is absent from habitat saves.
Weather snapshots v2 validate density-byte SHA256, resolution, span and velocity.
Legacy v1 weather snapshots retain their existing mean snow/water accounting
and start the new cloud-driven forcing on continuation.

## Checks

- Native numerical checks: PASS, 172 assertions. Exact local depths in isolated
  compartments, summed volume, uniform-grid equivalence, dry zero field,
  transactional rejection of wrong shape/negative/NaN rates; independent
  bilinear centre, periodic seam, advective translation, fringe/core controls.
  Existing hydro/groundwater conservation controls remain included.
- `tools/check_spatial_rain.gd`: PASS. An independent GDScript image sampler
  agrees within 2.395e-12 m/s. In the forced default scenario, 9,525 cells are
  completely dry and 6,777 exceed 1e-8 m/s. Rain volume in 0.5 s is
  0.30576593154674 m³; total native input is 1.32576593154674 m³ including known
  headwater/spring sources. Exact weather continuation over 100 further ticks,
  v1 migration, wrong-source rejection and mean-snow/melt accounting pass.
- `tools/check_worker.gd`: PASS with active spatial rain. Sixteen coupled ticks
  match the synchronous reference exactly. Pause, save/load and busy-worker
  map access join the owner. The transient rain array stays out of persisted
  downstream weather caches. The first integration run caught that cache
  payload error; the composed boundary now removes it after water consumes it.
- `tools/preview_spatial_rain.gd`: actual Forward+ at 960×600, 60 saved frames,
  source-density GPU discrepancy 0.00045443 and rain-mask discrepancy 0.00022669.
  The former includes HDR raster interpolation/readback; doubling the field
  raster from source resolution reduced the measured secondary-filter error
  from 0.0083. Authoritative model snapshots remain byte-identical. Captured
  rain and hidden-drop-control stills were inspected, along with sequence frames.
  Hiding the particle draw gives a mean image difference of 0.00021870,
  exceeding the predeclared 0.00005 visible-change threshold.
- `tools/check_spatial_rain_live.gd`: actual asynchronous scene, 13 busy frames,
  one completed coupled tick over 50 observed frames, matching submitted
  cloud/precipitation phase. Liquid input residual is 2.23e-16 m³. Pause freezes
  both model state and mask bytes. This short scene is a concurrency smoke check.
- `tools/check_cloud_lighting_render.gd`: PASS with the new source. Independent
  sun-ray projection agrees with bright/dark receivers near and far. Opaque
  and no-caster controls, ambient preservation, low sun from both sides,
  camera-independent cloud phase, clock-driven updates and below-horizon/
  baseline disabling pass.

- `tools/check.sh`: PASS after the integration fix. All registered native and
  headless checks, whole-world transactional save/restore, worker/synchronous
  equivalence, ecosystem budgets, observer and controls completed successfully.
- `gdformat --check`, `gdlint` on touched GDScript and `git diff --check`: clean.
  The editor import retains the established Dummy-renderer shutdown RID
  warnings; there are no script/import failures or runtime check errors.

## Artifacts and reproduction

```bash
./tools/check.sh
./tools/preview_isolated.sh --script res://tools/preview_spatial_rain.gd
./tools/preview_isolated.sh --script res://tools/check_spatial_rain_live.gd
./tools/preview_isolated.sh --script res://tools/check_cloud_lighting_render.gd
ffmpeg -framerate 10 -i artifacts/spatial-rain/frame-%03d.png \
  -c:v libx264 -pix_fmt yuv420p -crf 21 artifacts/spatial-rain/cloud-rain.mp4
```

Local outputs: `artifacts/spatial-rain-check.json`,
`artifacts/spatial-rain/{report.json,live.json,cloud-rain.mp4}`,
`artifacts/cloud-lighting-check/report.json`. The six-second video accelerates
56 water seconds of cloud transport; falling particles use display time. It is
a paused rendering fixture and does not advance ecological reserves. GPU
previews use the existing 75°C guard and isolated X11 display, Dummy audio.
These results establish numerical/implementation consistency for this scenario.
Field hydrology and atmospheric coupling have not been calibrated here.
