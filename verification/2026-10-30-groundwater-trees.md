# Groundwater, living trees and seasons — verified 2026-10-30

## Scope

Follow-on to `71c0ed3`, in `/run/media/pavel/Storage/src/forest-observatory`.
Pavel requested continued groundwater work and then living trees **with seasons**.
This is a first coupled ecological slice, not completion of the full development
plan. Existing hydrology-reference/grid-convergence work remains open.
No engine/addon/service/user-save/Rust Tide changes. No paid assets or Python game runtime.

## Implemented path

- C++ shallow mobile groundwater store: root drainage becomes internal recharge,
  shared upwind Darcy fluxes move water by head, saturation excess reaches surface.
  Surface/soil/pending/groundwater reserves and all actual external losses share
  one ledger. Water under the initial persistent stream starts saturated; other
  cells at declared 60% mobile capacity. Initial water is included, not injected.
- Native aggregated root withdrawals return an actual fulfilled volume per cell,
  never consuming below residual root storage. All co-located trees share that
  fulfillment ratio. Transpiration is an explicit external loss.
- `ForestTrees` owns stable individuals, seeded placement, size, age, stress,
  alive/dead state and stored RNG. `ForestVegetation` only displays them. Growth
  depends on warm-season phenology, root-water fulfillment and canopy light.
  Stress relaxes toward drought/flood forcing; death retains the standing stem.
  Species traits and leaf/wood geometry tags are data, no identity conditionals.
- Calendar is 365 × 86400 SI seconds, derived from water time; start 15 May,
  latitude 60 degrees. Temperature/day length drive growth and water demand.
  Evaporation forcing is separate checkpointed state, not mutated base config.
- Deciduous leaf-out, autumn tint and leaf drop; evergreen foliage stays. Stem
  geometry is not discarded. Fixed model clocks are independent of render frames.
- T cycles four seasonal **previews on pause**, then returns the actual date and
  previous pause state. It never changes water, tree age, stress or model time.
  M shows groundwater storage, surface water and current returnflow locations.

## Numerical / integration checks

`tools/check.sh`: PASS. Native Release executable: **120 assertions**.
Water, third-species/geometry/interface, ecology, and scene signal controls pass.

- Groundwater equal-head equilibrium over a bed step is stationary.
- Two-column upwind Darcy trajectory compared with independent exact solution:
  fine-step error 3.1227113e-05 m, smaller than coarse step.
- No-rain/source hill-to-lowland returnflow passes; zero-conductivity null has none.
- In the actual valley after stopping rain, 1.48831 m³
  returned from groundwater to surface over 120 model seconds. Headwater input
  remains enabled; this number specifically counts the internal groundwater transfer.
- Valley three-branch 600 s ledger maximum absolute residual:
  8.20768e-09 m³. No negative surface reserves.
- Mid-soil-tick save/continue is exact, including groundwater, q, pending water
  and changed seasonal evaporation forcing; corrupt water state is rejected.
- Controlled 4² homogeneous chambers, 38 individual trees: warm/wet
  growth, dry no-growth null, cold no-growth/no-transpiration, leaf cycle,
  evergreen winter foliage, taller-crown shading, stress recovery and flood death.
  The flood assay killed 38 trees after 80 days; dead IDs/stems persist.
  This is a controlled model check, NOT an annual full-valley ecological validation.
- Tree/native transpiration totals agree; coupled water + tree snapshot continuation
  is exactly equal; negative tree size is rejected without changing live state.
- Scene signals verify seasonal previews preserve both complete snapshots and
  prior pause state; diagnostic map toggles. Physical keyboard/mouse not exercised.
- Loaded `.tres` modules and mesh vertex tags are checked end-to-end: both foliage
  and stem tags must exist. This catches properties placed before their script.

## Actual renderer

Vulkan Forward+, RTX 3070 Ti, private Xvfb, 1440×900, 3510 trees. Seven saved PNGs;
winter, spring, summer, autumn and creek were inspected. Winter birches are bare,
summer crowns are full, autumn crowns are yellow; evergreens retain their foliage.
Map/legend, dates, preview label and HUD fit. Screenshot capture awaits the rendered
frame (`frame_post_draw`), not a stale previous frame.

Final run: 29 FPS normal, 22 FPS rain/barrier;
requested ×60 achieved ×40.98. Mean composed
simulation step 5.407 ms. Host-load snapshot, not a
controlled speedup comparison or desktop guarantee. This run reached 748 s,
12 tree ticks, transpired 1.36026 m³, returned
9.10329 m³ from groundwater, final balance residual
7.34326e-09 m³. All 3510 trees still alive in this short spring run;
mortality was checked in controlled chambers, not inferred from these pictures.

`gdlint`, `gdformat`, shell syntax and diff whitespace checks pass.
Final model/control/render logs have no SCRIPT ERROR/ERROR. Existing Terrain3D
deprecation and headless-editor dummy RID exit warnings remain.

## Limits

Conceptual mobile store, not a resolved saturated pore volume inside soil buckets;
no pond-stage backpressure, capillary rise, reverse bank storage, Green–Ampt/Richards,
field calibration or executed Landlab reference comparison. One root cell / tree,
16 m canopy columns, scenario growth/stress curves; no seeds/recruitment, crown rain
interception, distributed roots, nutrient cycle, falling-tree mechanics or animals.
No snow reservoir/freeze-thaw: manual precipitation remains liquid even in winter.
No erosion or sediment balance. Full-valley multi-year acceleration is not solved;
season preview is not substituted for physical integration. Hydrology file API is
still hydrology-only; coupled tree snapshots are checked, but full-world save UI
is not implemented. 4 m valley resolution remains provisional.

Sources of observed results: ignored `artifacts/native-check.json`, `water-check.json`,
`ecology-check.json`, `contracts.json`, `controls.json`, `runtime.json`, `preview.log`,
`01-valley.png` through `07-autumn-water.png`. Reproduce using tools/check.sh and
tools/preview_isolated.sh. Build/run details: README.md and native/README.md.
