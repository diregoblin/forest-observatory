# Independent ecosystem time and day/night — 2026-10-30

## Requested change and contract

Pavel explicitly requested independent day/year durations, separate water and
biological tempos, then a day/night cycle. Birch mesh rework was explicitly
postponed: no plant resources/geometry, engine, addon, services, other projects
or user saves changed. This supersedes the original one-SI-clock requirement
in the earlier groundwater/tree slice, not its hydrology validation limits.

Configuration in `scripts/settings.gd`:

- `ecology_day_s = 60.0`: a visible solar cycle per minute of unpaused scene time.
- `ecology_year_s = 600.0`: a biological year per ten minutes of unpaused scene time.
- `ecology_step_s = 0.5`: fixed ecosystem steps; excess work remains pending.
- Day and year are independent periods: intentionally ten solar cycles per year,
  not 365 minute-long nights. Annual phenology still uses 365 nominal calendar days.
- Water ×1/×8/×60/×600 changes hydrological throughput only. Hydrology stays SI;
  no changed hydraulic dt, CFL or native numerical coefficients.

`ForestEcologyClock` owns fixed ticks/pending time; views do not advance it.
Season, temperature/day length, growth, biological age, stress and grass biomass
follow biological time. Root uptake and evaporation use elapsed **hydrological**
seconds with current seasonal coefficients; actual uptake remains a single native
withdrawal per root cell and an external ledger term. No duplicated reserve and
no hidden acceleration of water demand by 52,560x (the default year compression).
This is intentionally a two-timescale ecosystem scene, not a physically annual
watershed trajectory. Growth/ET retain seasonally varying daily-mean forcings;
instantaneous sun elevation currently drives presentation, not photosynthetic flux.

Pause freezes both models. T remains read-only seasonal preview at noon, restoring
the actual ecological date/hour and prior pause. Clock snapshot includes partial
fixed-step debt and rejects changed periods/corruption. Tree snapshots are version
2 and include biological and uptake time. Hydrology file API remains hydrology-only;
this does not add a full-world save/load UI or migrate old tree snapshot format.

## Numerical / integration checks

`tools/check.sh`: PASS (120 native assertions plus existing water/interface/ecology/
scene controls). Follow-up focused ecology check: PASS after strengthening the
three-state continuation control.

- Frame-partition control: one 60.125 s request equals 481 x 0.125 s requests,
  including exactly equal fixed ticks and pending fraction.
- One visible day returns the hour; 600 scene seconds complete a biological year.
- Identical wet closed chambers with 10x different water throughput have identical
  age/growth. Trees gain exactly one year and grow over a full compressed year;
  cumulative transpiration scales by 10, not biological-clock compression.
- Dry-root null: no water/no growth; a zero-water tick cannot falsely cure drought.
- Water, tree and ecological-clock snapshots resume exactly, including partial
  clock debt; negative tree size/clock ticks and changed clock periods are rejected.
- Definition-derived canopy checker sums higher live crown cover in the same 16 m
  column, independently of the implementation sorting algorithm. Sorting per column
  replaces unnecessary global sorting. Two-crown shading control remains.
- Solar geometry: equinox noon at 60 N has 30-degree elevation; midnight is below
  horizon and astronomical sunrise is on it; summer daylight exceeds equinox.
- Real scene signals: water speed 1 vs 600 leaves ecological stepping unchanged;
  pause freezes both complete states; T preserves water/trees/clock snapshots.
- Water residual remains below 1e-5 m3; native negative/corrupt-state controls pass.

`gdformat`, `gdlint`, `git diff --check`: PASS. Existing dummy RID warnings on
headless-editor exit and Terrain3D interpolation deprecation remain; final
model/control/render logs have no SCRIPT ERROR/ERROR. Physical mouse/keyboard
input was not exercised.

## Renderer

Forward+, RTX 3070 Ti, private Xvfb, 1440x900, 3510 trees.
Default-period preview: seven saved PNGs; scene clock advances independently
of delivered water time. Day/night sky, sun elevation/azimuth, warmth at the horizon,
night ambient fill and fog read only current ecological state. Sky uses its native
realtime radiance mode; repeated identical model samples do not rebuild it.
Screenshots freeze model state for the rendered frame and refresh HUD so date/hour
matches the accompanying report, not the previous vegetation refresh.

Final default-period run: 24 FPS normal, 18 FPS rain/barrier; requested water x60
achieved x34.89 in this host-load snapshot. Mean tree step 19.46 ms (earlier global
canopy sort measured 63.19 ms in a headless scene; not a controlled benchmark).
Ecological elapsed 23.0 s before preview paused it, water elapsed 638.0 s,
water balance residual 7.43e-9 m3. This is not a desktop speed guarantee.

Additional live-cycle assay: `./tools/preview_isolated.sh -- --cycle-check`.
Only this test process uses day=20 s, year=60 s and step=0.1 s; it advances the real
water/tree/calendar models without T/preview and does not rewrite configuration.
Seven `artifacts/cycle-*.png/.json` samples cover daylight, dusk, night, dawn,
autumn, winter and next spring. See generated reports for measured clocks/ages.
Final assay: ecological elapsed 60.5 s, biological age increment 1.00833333 years,
water elapsed 121.0 s, residual 6.91e-09 m3. First-to-last individual-age delta
matches ecological elapsed/year to <1e-8 years. Screenshots of day, dusk/night,
dawn, summer/autumn and winter were inspected. Default periods remain day=60 s,
year=600 s.

## Retained limits

Not field-calibrated ecology or hydrology. No snow/freeze-thaw, seed recruitment,
erosion, animals, detailed root distribution or crown rain interception. Birch
geometry is unchanged by request; visual rework is deferred. Offline Landlab and
valley-grid convergence work remain open. Biological acceleration does not prove
a year of hydrological forcing or ecological realism.
