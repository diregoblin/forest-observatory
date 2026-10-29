# Native surface + shallow groundwater hydrology

The game has no Python runtime dependency. C++17 `Hydro` owns SI/double arrays;
`ForestHydroNative` is a thin batch GDExtension adapter. GDScript reads snapshots.

## Build and run

```bash
./tools/build_hydro.sh
./tools/check.sh
./tools/run.sh
```

`build_hydro.sh` pins `Redot-Engine/redot-cpp` to
`ef6e110918198417521d87335a1bb9d883f5a5a4` (`redot-26.3-stable`), checks an existing
checkout rather than resetting it, and generates API/header files with the selected
`REDOT_BIN`. The official 26.3 binary `85e520394` reports **GDExtension API 4.5.2**
with single-precision engine vectors. This does not prevent `double` scalar arrays
in the independent solver. Bindings are built against that generated API, not an
assumed version inferred from the engine's marketing number. The addon is Linux
x86_64 only so far; other architectures have not been built or tested.

Generated bindings/API, object files and binaries are ignored by Git. CMake builds
into `native/build/lib`; the launcher helper installs the `.so` with atomic rename,
so a running process's mapped file is not overwritten. Restart the game to use a
new library; hot reload is disabled. No engine install/service is changed.

Core-only build (no Redot or bindings required):

```bash
cmake -S native -B native/build-core -DFOREST_EXTENSION=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build native/build-core
native/build-core/hydro_checks
native/build-core/hydro_checks --benchmark
```

## Numerical contract

- Cell-centred `bed`, `depth`: m. `qx/qz`: face discharge per width, m²/s.
  Transfers are `q * dt * face_width` in m³; source input is m³/s independent
  of source-cell count; areal rain/evaporation/infiltration are m/s.
- Local-inertial momentum, semi-implicit Manning friction. Face flow depth uses
  the higher water surface minus the bed/barrier crest. Hydrostatic reconstruction
  makes equal surfaces stationary, including bed steps and impermeable crests.
- Parallel-face momentum mixing follows the de Almeida idea, with its strength
  scaled by `dt / local_wave_CFL_time`. A shorter caller/soil-alignment step must
  not apply an unchanged blend more times per physical second. This time scaling,
  conservative wet/dry limiter and cell-centred layout are **not** a line-by-line
  reproduction of Landlab. No result-equivalence claim is made.
- CFL uses gravity-wave speed and the largest surface depth, with a bound on
  source/rain input during a step. `max_step_s` is a ceiling, not a fixed timestep.
- `max_froude=1` caps face discharges to the supported subcritical/critical
  approximation regime. Activation counts are exported. Fast supercritical flow,
  shocks, barrier collapse and advective acceleration are out of scope.
- Limit the **sum** of a donor's outgoing transfers, then apply each shared face
  flux with opposite signs to its two cells. There is no post-update water clamp
  or artificial minimum water film. Flux history stores the actual limited q.
- North/east/west boundaries are walls. South is a one-way normal-depth outlet
  driven by positive bed slope in the last row. No bidirectional tidal boundary.

## Soil and separate clocks

This first soil model is a two-bucket profile, **not Green–Ampt or Richards**.
`top` and `root` are equivalent water depths (m). Thickness × porosity is capacity;
theta and saturation are derived. Material parameters live in `ForestSoilProfile`.

Every water substep reserves at most available surface water, top-layer free
capacity and `Ksat * dt`. `pending` is a real included storage, not an unaccounted
future write. No column mixing or expensive root ecology runs at this frequency.
Surface evaporation is charged immediately; remaining evaporation demand is
integrated for the soil clock (the demand is not a water reserve).

At each 30-model-second soil boundary: deposit the reserved infiltration; move
top water above field capacity into available root storage; drain root excess
to the mobile shallow store when enabled (legacy mode: external deep sink);
apply accumulated soil evaporation above the
residual threshold. All exchanges are bounded. The default valley enables groundwater. Shared upwind Darcy face fluxes
redistribute it along hydraulic head `bed - aquifer_m + ground / specific_yield`.
An explicit diffusion ceiling and summed-donor bounds limit each slow substep;
saturation excess is transferred to surface water. Below-ground outer boundaries
are sealed; surface barriers do not implicitly become underground cutoff walls.
The persistent initial stream starts with saturated groundwater beneath it;
other cells start at the declared 60% mobile capacity. All of it is initial water,
not a new source. Root drainage is counted as internal recharge. The interval is independently configurable; frequency sensitivity
is an operator-splitting test, not a promise of frequency-independent physics.

The mobile aquifer is a **conceptual extra reservoir**, not a resolved saturated
pore volume within the two soil buckets. Its default thickness is 1.5 m, effective
specific yield 0.18, lateral conductivity 1e-4 m/s. These scenario values are not
calibrated. Instantaneous saturation-excess returnflow does not resolve
surface-pond backpressure, capillary rise, reverse bank storage or freeze/thaw.
No equivalence to Landlab GroundwaterDupuitPercolator is claimed. That maintained
component was inspected as an existing reference; Python was not embedded and
its regularized numerical solver was not copied.

Trees submit one aggregated root-demand array. The native core returns actual
withdrawals above residual root water and records `transpired_m3`; co-located trees
share each cell's fulfillment ratio. Invalid demands are rejected before mutation.
Surface evaporation is adjusted by the same model calendar as tree phenology.

Ledger:

```text
surface + top + root + pending + groundwater + outlet + evaporation + deep_drain + transpiration
    - initial_storage - rain_and_source_input = residual
```

Infiltration/percolation are internal transfers and are not added as external
losses. Save/restore includes both q histories, pending storage/demand, the partial
soil clock, parameters, crests and cumulative ledger. Restore validates a candidate
before replacing the running core. Native checkpoint version 2 adds groundwater, seepage and transpiration. Native
v1 import retains the old external-drain physics; the world wrapper rejects
configuration mismatches rather than silently changing saved physics.
The GDScript file API saves **hydrology only**,
not camera/plant state or a finished full-world save system.

Rendering samples at 10 wall-Hz and blends the last two depth images each frame;
the CPU upload image is retained, avoiding texture readback. This interpolation
is display-only and is one sample behind, never a physical prediction.

## Verification and remaining limits

`hydro_checks` uses failure checks that remain active in Release builds. Controls
include a stationary lake, analytic rain volume, a dry domain, wetting front,
barrier/release/overflow, Manning's uniform-flow fixed point, damping of alternating
face momentum, the Froude regime bound, capacity/evaporation/drainage, slow-clock
storage, clock partitioning and a deliberate unaccounted-water mutation.
Smooth-wave tests compare grid/time refinements; these are synthetic sensitivity
checks, not physical convergence of the actual forest watershed. The benchmark
measures CPU core only; `artifacts/runtime.json` measures the rendered scene.

Still pending: an offline Landlab comparison, real-world calibration, Green–Ampt,
spatially varying soil profiles, surface-stage groundwater coupling, physically driven
water ripples/shoreline reconstruction and the point inspector. GPU computation
has not been implemented. Soil rates and climate are plausible scenario inputs,
not field measurements or validated ecological parameters.

## References and attribution

- [Bates et al. 2010](https://doi.org/10.1016/j.jhydrol.2010.03.027), simple
  inertial formulation of shallow-water flow.
- [de Almeida et al. 2012](https://doi.org/10.1029/2011WR011570), improved
  stability through weighted discharge memory.
- [Landlab OverlandFlow source](https://github.com/landlab/landlab/blob/master/src/landlab/components/overland_flow/generate_overland_flow_deAlmeida.py)
  was inspected as the open implementation/reference, not imported into the game.
  Landlab is [MIT, Copyright The Landlab Team](https://github.com/landlab/landlab/blob/master/LICENSE.md).
- The pinned [redot-cpp](https://github.com/Redot-Engine/redot-cpp/tree/ef6e110918198417521d87335a1bb9d883f5a5a4)
  dependency retains its upstream MIT license/copyright in `native/deps/redot-cpp/LICENSE.md`.

- [Landlab GroundwaterDupuitPercolator source](https://github.com/landlab/landlab/blob/master/src/landlab/components/groundwater/dupuit_percolator.py):
  maintained Boussinesq/Dupuit reference inspected before the bounded native model.
  Not executed or imported; our saturation-excess coupling is simpler.
