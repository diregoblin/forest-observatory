# Native surface + shallow groundwater hydrology

C++17 `Hydro` owns SI/double arrays;
`ForestHydroNative` is a thin batch GDExtension adapter. GDScript reads snapshots.

## Build and run

```bash
./tools/build_hydro.sh
./tools/check.sh
./tools/run.sh
```

`build_hydro.sh` pins `Redot-Engine/redot-cpp` to
`ef6e110918198417521d87335a1bb9d883f5a5a4` (`redot-26.3-stable`), checks an existing
checkout while preserving local changes, and generates API/header files with the selected
`REDOT_BIN`. The official 26.3 binary `85e520394` reports **GDExtension API 4.5.2**
with single-precision engine vectors. The independent solver uses `double` scalar
arrays. Bindings are built against that generated API. The addon is Linux
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
native/build-core/fungi_checks
```

## Numerical contract

The current valley uses 2 m³/s main headwater plus a separate 0.04 m³/s side
spring. Per-source weights preserve this split. Both are external boundary inputs. The ravine is part of the analytical bed; a
300 s dry source-only assay and source-off null live in `tools/check_spring.gd`.
The whole-world configuration now rejects the old bed without altering old saves.


- Cell-centred `bed`, `depth`: m. `qx/qz`: face discharge per width, m²/s.
  Transfers are `q * dt * face_width` in m³; source input is m³/s independent
  of source-cell count; areal rain/evaporation/infiltration are m/s.
- Local-inertial momentum, semi-implicit Manning friction. Face flow depth uses
  the higher water surface minus the bed/barrier crest. Hydrostatic reconstruction
  makes equal surfaces stationary, including bed steps and impermeable crests.
- Parallel-face momentum mixing follows the de Almeida idea, with its strength
  scaled by `dt / local_wave_CFL_time`. A shorter caller/soil-alignment step must
  not apply an unchanged blend more times per physical second. Time scaling, the
  conservative wet/dry limiter and cell-centred layout are local adaptations.
- CFL uses gravity-wave speed and the largest surface depth, with a bound on
  source/rain input during a step. `max_step_s` bounds the adaptive timestep from above.
- `max_froude=1` caps face discharges to the supported subcritical/critical
  approximation regime. Activation counts are exported. Fast supercritical flow,
  shocks, barrier collapse and advective acceleration are out of scope.
- Limit the **sum** of a donor's outgoing transfers, then apply each shared face
  flux with opposite signs to its two cells. There is no post-update water clamp
  or artificial minimum water film. Flux history stores the actual limited q.
- North/east/west boundaries are walls. South is a one-way normal-depth outlet
  driven by positive bed slope in the last row. No bidirectional tidal boundary.

## Soil and separate clocks

The soil model uses a two-bucket profile.
`top` and `root` are equivalent water depths (m). Thickness × porosity is capacity;
theta and saturation are derived. Material parameters live in `ForestSoilProfile`.

Every water substep reserves at most available surface water, top-layer free
capacity and `Ksat * dt`. `pending` is included in total water storage. No column mixing or expensive root ecology runs at this frequency.
Surface evaporation is charged immediately; remaining evaporation demand is
integrated for the soil clock as a requested withdrawal.

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
other cells start at the declared 60% mobile capacity. This water is included
in initial storage. Root drainage is counted as internal recharge. The interval
is configurable; frequency-sensitivity tests measure the effect of operator splitting.

The mobile aquifer is a **conceptual extra reservoir** below the two soil buckets. Its default thickness is 1.5 m, effective
specific yield 0.18, lateral conductivity 1e-4 m/s. These scenario values are not
calibrated. Instantaneous saturation-excess returnflow does not resolve
surface-pond backpressure, capillary rise, reverse bank storage or freeze/thaw.
Landlab GroundwaterDupuitPercolator was inspected as a reference
when developing this bounded reservoir model.

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
before replacing the running core. Native checkpoint version 3 adds nonnegative per-source weights (normalized over total source input). Version 2 added groundwater, seepage and transpiration. Old v1/v2 snapshots without weights retain uniform source distribution; v3 validates weights and their sum atomically. The CFL source bound uses the largest normalized fraction. Native
v1 import retains the old external-drain physics; the world wrapper rejects
configuration mismatches. The GDScript file API saves **hydrology only**.
`ForestWorldState` provides a separate transactional whole-world save format
that also includes plants, animals and the observer.

Rendering samples at 10 wall-Hz and blends the last two depth images each frame;
the CPU upload image is retained, avoiding texture readback. This interpolation
is display-only and lags the solver by one sample.

## Verification and remaining limits

`hydro_checks` uses failure checks that remain active in Release builds. Controls
include a stationary lake, analytic rain volume, a dry domain, wetting front,
barrier/release/overflow, Manning's uniform-flow fixed point, damping of alternating
face momentum, the Froude regime bound, capacity/evaporation/drainage, slow-clock
storage, clock partitioning and a deliberate unaccounted-water mutation.
Smooth-wave tests compare grid/time refinements on synthetic cases. The benchmark
measures CPU core only; `artifacts/runtime.json` measures the rendered scene.

Still pending: an offline Landlab comparison, real-world calibration, Green–Ampt,
spatially varying soil profiles, surface-stage groundwater coupling and physically driven
water ripples/shoreline reconstruction. A read-only point inspector is now available in V. GPU computation
has not been implemented. Soil rates and climate are scenario inputs.

## Fungal soil plots

`Fungi` (`fungi.hpp/.cpp`) is a separate native float64 model sharing the existing
extension build. It owns its own state. `ForestFungiNative` exposes batch forcing,
fields, metrics and versioned atomic snapshots (standalone and soil-coupled contracts differ). Four areal carbon stores use
kg C/m²: available resource, mycelium, finite organic reserve, fruiting biomass.
Only resource and biomass diffuse. The positive five-point stencil has reflecting
boundaries and `dt <= .225 dx²/max(D)`. Reaction substeps limit resource turnover;
first-order losses/transfers use exponential fractions. All uptake and transfers
are donor-bounded.

The paper-reference mode uses unlimited signed resource exchange, fruiting off,
and c2/c1=1. The forest mode replaces that exchange with transfers to/from the
finite organic reserve, and adds environmentally gated B→fruit→organic transfers.
Both modes account for carbon, with external exchange/respiration in the ledger.
Default yield=1 has no respiratory loss; this intentionally matches the chosen
paper kinetics.

The resource represents available carbon substrate, measured in kg C/m². The modes above describe the standalone reference. In the current
coupled forest, R/L read the stores of the single shared soil owner: vegetation supplies litter and competes for finite C/N/P. Mycelium and
fruit are fungal-owned; mortality returns elements to the soil. ECM fungi trade
finite nutrients for host carbon.
Moisture supplies read-only coarse-grid forcing; fungal water uptake is absent. Biological
seconds are a configured multiple of completed water time. See the shared-soil
section below and [the current model guide](../docs/models.md).

`fungi_checks` covers the independently calculated homogeneous paper RHS,
no-inoculum and no-resource nulls, no-spread counterexample, diffusion/carbon
conservation, finite-resource exhaustion, fruit transfer, mesh/timestep sensitivity
and CPU cost. `check_fungi.gd` checks the extension, exact continuation, invalid
restore atomicity, dry suppression and view/state separation.
See [dated equations, parameters, results and limits](../verification/2026-10-30-fungi.md).

## References and attribution

- [Bates et al. 2010](https://doi.org/10.1016/j.jhydrol.2010.03.027), simple
  inertial formulation of shallow-water flow.
- [de Almeida et al. 2012](https://doi.org/10.1029/2011WR011570), improved
  stability through weighted discharge memory.
- [Landlab OverlandFlow source](https://github.com/landlab/landlab/blob/master/src/landlab/components/overland_flow/generate_overland_flow_deAlmeida.py)
  was inspected as an open implementation reference.
  Landlab is [MIT, Copyright The Landlab Team](https://github.com/landlab/landlab/blob/master/LICENSE.md).
- The pinned [redot-cpp](https://github.com/Redot-Engine/redot-cpp/tree/ef6e110918198417521d87335a1bb9d883f5a5a4)
  dependency retains its upstream MIT license/copyright in `native/deps/redot-cpp/LICENSE.md`.

- [Landlab GroundwaterDupuitPercolator source](https://github.com/landlab/landlab/blob/master/src/landlab/components/groundwater/dupuit_percolator.py):
  maintained Boussinesq/Dupuit reference inspected before the bounded native model.
  The local model uses bounded saturation-excess coupling.

- [Karst, Dralle & Thompson (2016), PLoS ONE 11(3):e0149254](https://doi.org/10.1371/journal.pone.0149254),
  CC BY: biomass–resource equations and Gray–Scott correspondence. Equation MathML
  and Figure 3 parameter values were read from the publisher's manuscript XML.

## Shared ecosystem soil (2026-10-31)

`soil.hpp/cpp` stores kg C/N/P amounts in organic, labile
and mineral pools. The base cells retain only uncovered area after fine-patch
creation; patch integration is mass-conservative, overlaps are rejected. Native
soil and fungal calculations remain float64; strict audits sum float64 scalar
metrics. Soil decay follows qualitative scenario rules.

Coupled fungi exclude mirrored soil pools from their own carbon total. Fungal
`fields`/snapshots read the current owner even after later plant/animal deposits;
reading a snapshot never changes solver caches or reserves. Trees/herbs request
mineral N/P in one proportional batch; between plant/fungal guilds the scene uses
operator splitting. See `verification/2026-10-31-understory.md` for measured
order/step sensitivity, whole-world accounting and remaining limitations.
