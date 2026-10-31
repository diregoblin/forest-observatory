# Smooth solar presentation — 2026-10-31

The earlier day/night slice diagnosed, but did not fix, the half-second solar
steps. `ForestEcologyClock.sample()` was fixed-step, and the composition root
updated atmosphere only with water/vegetation refreshes.

## Change and boundary

- `presentation_sample()` samples continuous calendar/solar geometry within the
  last completed ecological interval. It is at most one fixed tick (default
  0.5 scene seconds) behind authoritative ecology, never ahead of completed time.
- The composition root updates lighting every render frame. Display calendar and
  foliage use that same read-only phase; model forcing still uses `sample()`.
- No angle lerp across midnight/azimuth wraps: solar geometry is evaluated from
  continuous scalar time. Startup is clamped to zero, unserved debt is bounded,
  and no frame-based simulation or change to shipped periods is introduced.
- Pause freezes the interpolation fraction. Seasonal previews remain immediate,
  read-only noon views; exit restores the same presentation phase. Clock snapshots
  already contain ticks/pending time, so their schema and restore path are unchanged.
- Water, trees, fungi, native solvers, resources, engine/addon, services, user saves
  and other projects are untouched. An already running game needs a restart to
  load the changed scripts; the user's running instance was not stopped.

## Verification

`tools/check.sh`: PASS, including new presentation-clock regression controls:

- 2,400 successive 25 ms samples over a complete day advance solar hour uniformly,
  including tick boundaries and midnight.
- The old fixed-step sample has over 2,000 stationary frames through the same
  measurement path and therefore fails the smoothness criterion.
- Sampling is read-only; no requested time freezes display; snapshot/restore
  preserves the partial display phase; pending debt cannot extrapolate the sky.
- Existing water/ecology/fungi/control and exact-continuation checks still pass.

`./tools/preview_isolated.sh --script res://tools/check_sun.gd`: PASS. Real full
scene, Forward+ on RTX 3070 Ti, 1440×900, 3,510 trees, default day=60 s and
ecological step=0.5 s. The isolated assay drives the actual composition root at
25 ms *requested* frame increments and draws each frame, not a performance claim
of 40 delivered FPS. Every one of 80 checked rendered frames moved the actual
directional light: 0.14155–0.14179 degrees/frame, with no stationary samples or
half-second jumps. Pause freezes water/tree/fungi/clock snapshots and sun; all
four previews return to the exact frozen phase; resume moves the next frame;
rain retains the existing 0.74 attenuation. Generated report:
`artifacts/sun-check.json`; adjacent sunset PNGs: `artifacts/sun-smooth-*.png`.
Rendered scene/sky image inspected. This is scripted render/control validation,
not a physical-keyboard test or a user-desktop FPS benchmark.

`gdformat --check`, `gdlint`, `git diff --check`: PASS. The known Terrain3D
interpolation deprecation warning remains; no render SCRIPT ERROR/ERROR.
