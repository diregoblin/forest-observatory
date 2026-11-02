# Native plant-light batch, follow-up optimization — 2026-11-02

Pavel explicitly requested further optimization experiments, without requiring
60× or sacrificing the playful prototype. This follows the completed cloud,
display-clock and animal fast-path package in
[the first report](2026-11-02-sky-timeline-animal-cost.md).

## Measured target and bounded experiment

The remaining plant stage cost about 94 ms/tick: roughly 22 ms recruitment/finish,
21 ms assimilation, 17 ms growth requests, 16 ms light sorting/attenuation, and
smaller stages. These are disjoint timings, not stacked inclusive intervals.
The chosen trial was only the pure light calculation: retain numerical behavior
while moving one large script loop into the existing native extension.

`ForestPlantLightNative.compute` accepts packed arrays, returns float64 light and
column cover, and owns no model state, clock or RNG. `ForestTrees` keeps its normal
ownership. Trait arrays are rebuilt from current resources, including unknown
species. The native helper uses Redot's existing `SortArray` implementation and
the same height comparison/input order as `Array.sort_custom`, including tied
heights. The runtime exponent/libm path is retained rather than substituting a
differently rounded formula. The old GDScript operation remains as the executable
reference (`use_native_light = false`), not as a second ecology model.

No reduced plant count, lower ecological/decision frequency, GPU physics, new
parallel writer, material/geometry change or changed climate/soil physics.

## Controls and timing boundary

Same headless full default model, seed 29017, 8,541 plants / 90 animals, i5-10600KF,
Redot 26.3; three warmup + ten measured real coupled ticks per run. Agent timing
runs were sequential without agent tests alongside; existing desktop/human
workloads remained. Stage counters are outside authoritative snapshots.

| Run | Light mean, ms | Plant mean, ms | Whole tick mean, ms |
| --- | ---: | ---: | ---: |
| A1 GDScript | 15.948 | 94.431 | 224.276 |
| B1 native | 1.379 | 73.863 | 194.552 |
| A2 GDScript return control | 13.417 | 85.114 | 204.926 |
| B2 final native | 1.754 | 93.765 | 252.422 |

The light operation is approximately **8–12×** faster in the paired comparisons,
not the whole forest. The return control and final repeat show substantial
background/timing drift in other phases: B2's animal stage was 109.964 ms versus
82.336 ms in A2, although its animal code was unchanged. Do not assign the entire
30 ms A1→B1 difference to this kernel or claim a reproducible whole-tick win from
this small sample. The local light saving is roughly 12–15 ms in the tested
scenario, not a claimed FPS multiplier or aged-world performance guarantee.
The original animal optimization's separate 2.86× stage result is recorded in
the first report; ratios are not multiplied together.

Raw samples: `artifacts/plant-phases-{baseline,native,reference-repeat,native-final}.json`.
The consolidated samples, source hashes and exact-model comparison are in
`artifacts/native-light-comparison.json`.
Logs use the corresponding names (baseline log is `plant-phases-before.log`).
Harness: `tools/profile_plant_phases.gd`; `--reference-light` selects the control,
`--result=res://artifacts/name.json` selects its report path. Model seconds and
the 0.5 s coupled step remain identical. The observed 0.19–0.25 s/tick is still far
from the 8.33 ms/tick required for honest UI ×60.

## Verification

- `check_native_plant_light.gd`: independent two-plant analytical shade and dead
  crown controls; 14 synthetic cases (empty/single, sort boundaries, ties up to
  4096 individuals, negative positions, mixed species/sizes/alive flags), plus the
  real forest. Full native/reference arrays and column dictionaries match exactly.
  Invalid shapes, species indices and NaN traits are rejected without mutation.
- Whole model bytes after the same 13 coupled ticks equal the pre-native and
  pre-animal-optimization reference: 11,225,392 bytes, SHA-256
  `7744ddf17ea811d35cc59c34b751e1ae9ce43dcadf104378249b09d31e4e8140`.
- Final `tools/check.sh`: **33/33 engine checks passed**, including the real
  worker, coupled model continuation and the new native-light regression.
  Receipt: `artifacts/native-light-suite.log`; individual reports/logs were
  checked against the final import for freshness, with no engine errors.
- Final B2 trace again matches the full pre-optimization model bytes/hash above;
  `artifacts/native-light-comparison.json` records the explicit comparison.
  The earlier short Forward+ sky/motion checks remain applicable: this follow-up
  changes no presentation code, and its model outputs are identical. No new
  long GPU soak or aged-world performance run is claimed.
- New helper lint passes; the tree model retains its pre-existing generic
  style-limit failures. No third-party code was edited. Engine launches guarded.

## Files and rollback

New `native/plant_light_extension.hpp`, registered through `native/extension.cpp`;
`scripts/trees.gd` adapter/phase counters; native-light regression and phase
profiling helper; regression added to `tools/check.sh`.

Pre-follow-up sources/model dictionary:
`/run/media/pavel/Storage/tmp/forest-further-cost-20261102/`.
Restore scoped tree/extension changes and rebuild, never reset the dirty checkout.
Native library replacement uses the existing atomic staging in `build_hydro.sh`;
it does not overwrite the inode mapped by an already-running game. New code is
used after restart. This is not a general native rewrite or a promise of x60.
