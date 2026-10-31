# Shared world speed and configurable time multipliers — 2026-10-31

Pavel requested solar/year cycles linked to water through settings and one UI
acceleration for all of them, after confirming the earlier smooth sun fix.
This explicitly supersedes the independent wall-clock ecosystem tempo in
`2026-10-30-ecosystem-time.md`, not the fixed-step/presentation separation.

## Configuration and execution

`data/forest.tres` / `ForestSettings` now expose:

- `initial_speed = 1.0`: requested hydrological seconds per wall second.
- `day_speed_multiplier = 1440.0`: solar seconds per hydrological second.
- `year_speed_multiplier = 52560.0`: biological seconds per hydrological second.

Thus at achieved ×1: a solar day takes 60 s, a biological year 600 s. At achieved
×8 these take 7.5 / 75 s; the intentional ten visible solar cycles per year are
retained. The two positive finite multipliers can be configured independently,
subject to the biological fixed-step resolution constraint. Solar sampling is
analytic, so increasing its multiplier alone does not require smaller model
ticks. Water remains SI; age/growth/
stress/fungi use biological seconds; transpiration uses actual hydrological
seconds. These are still scenario timescale conversions, not a physically
synchronized annual watershed model.

The scene requests `wall_dt * selected_speed` on one shared fixed clock. It
completes water, groundcover, trees and fungi for each tick before starting
another. One budget/debt ensures calendar, age and sun cannot outrun completed
water under load. Shared steps are 0.5 hydrological seconds, at most the existing
1 s requested water maximum; native CFL may subdivide further. This changes
scene water scheduling from 1 s calls to 0.5 s calls; it does not loosen CFL,
change native equations/coefficients, or promise bitwise equality to old runs.

Presentation retains the previous continuous, read-only interpolation. When
changing speeds, only excess unserved work is cancelled: at most one pending
tick is retained so that the displayed phase never rewinds. Pause freezes debt
as well as all models; seasonal previews remain paused/read-only. Speed stats
restart their observation window on a speed change rather than mixing tempos.

HUD uses **Темп мира**, highlights the selected native ButtonGroup button,
shows achieved common throughput, and updates target day/year durations for
that selected speed. Duration tooltip distinguishes target from achieved
throughput. Runtime sliders/settings persistence were not added: multiplier
configuration is the existing Resource/`.tres` route, loaded at startup.

The clock snapshot is version 2 because elapsed/pending seconds now mean water
time rather than independent scene time; old version 1 is rejected explicitly.
The fungal wrapper snapshot is also version 2 to distinguish period-based and
multiplier-based configuration; native fungal state is unchanged. Tree/fungi
configuration signatures include the new biological multiplier and reject
mismatched old configuration. Exact continuation under the same new
configuration passes. No user saves, engine, addon, native equations, services,
other projects or running user instances were modified.

## Checks

- `tools/check.sh`: PASS: native hydrology/fungi, water ledger/continuation,
  model interfaces, ecology, fungi and scene/control signals.
- Controlled ×1 vs ×8 requests through the same fixed-clock/water/tree pipeline:
  water elapsed time, solar-hour displacement and individual age increment scale
  by exactly 8 (age tolerance 1e-8). Independently changed day/year multipliers
  produce the expected double-speed solar phase and quarter biological step;
  that custom configuration passes validation without changing the fixed tick.
- Existing zero-water/dry-root/winter/solar-geometry controls remain; the old
  prescribed-biology/10x-water uptake test remains a *unit* control, not a claim
  that scene speed leaves age unchanged.
- Real scene signals at ×1/×8/×60/×600 request the same coupled tick in proportionally
  shorter wall intervals. Every tick checks water clock = driving clock = tree
  uptake clock and biological tree/fungi time = water time × configured factor.
- Deliberately overloaded ×600 request leaves debt while all completed clocks
  remain aligned. Slowing to ×1 preserves the exact visible phase; pause and
  all four seasonal previews preserve complete model snapshots.
- `tools/preview_isolated.sh --script res://tools/check_sun.gd`: PASS in Forward+,
  full scene with 3,510 trees. All 80 baseline frames move the actual sun
  (0.14155–0.14179 degrees/requested 25 ms frame). The ×8 UI signal then drives
  4 water seconds over 20 requested frames, checking tree/fungi/calendar alignment
  every frame. Pause, resume, preview return and rain attenuation pass.
- `artifacts/shared-speed-08.png` inspected for selected ×8 button and scaled
  calendar/period labels; `artifacts/sun-check.json` records the rendered assay.
  The script drives requested frame increments, not a desktop FPS benchmark;
  physical mouse/keyboard input was not tested.
- Formatting/lint and diff checks pass. Existing Terrain3D interpolation
  deprecation warning remains; no render SCRIPT ERROR/ERROR.
