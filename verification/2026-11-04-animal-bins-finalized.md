# Animal spatial-index completion — 2026-11-04

## Change and authority

Pavel explicitly asked to finish the existing uncommitted animal optimization.
Starting HEAD: `f6e89927774d03e71e5f85d6dd074f285cbb2136` (quiet walking UI).
The working tree already contained the dense-index implementation, its first
test, suite registration and [November 3 report](2026-11-03-data-oriented-bins.md).
Those changes are retained, not represented as a newly invented mechanism.

The production change replaces plant/insect-site hash bins and per-bin Arrays
with packed head/next indices. Reverse insertion keeps ascending stable IDs;
plant queries retain z/x traversal and exact distance filtering. Insect results
remain habitat-ID sorted. Rebuild/invalidation boundaries and live finite food
pools are unchanged. Valid plant positions are in `[0, extent)` at creation and
restore; query centres may lie outside it and their search rectangles are clipped.

No animal policy, reproduction, feeding quantity, species, model timestep, RNG
operation, save schema, view, camera, user save, running window or service changes.
This finishes a bounded spatial-lookup optimization, not an ECS/engine rewrite.

## What this completion adds

- `check_dense_bins.gd`: 810 original ordered queries plus **578** domain/lifecycle
  assertions against the frozen hash implementation. Coverage adds fractional
  final bins (509.5/520.25 m), a one-bin 7.5 m domain, shrink/regrow of reused
  arrays, all plants dead then alive, empty plants, detached habitat, exact lower
  edge and just-inside upper edge, outside queries, and restoration of fixture
  geometry. These are isolated index assays, not ecology runs on distorted worlds.
- `profile_animal_bins.gd`: runs the actual composition-root coupled tick for two
  identical worlds; only the baseline animal's four index/query methods differ.
  The test-only subclass in `tools/reference/animal_hash_bins.gd` freezes those
  methods from starting HEAD, with all other animal behavior inherited unchanged.
- Compare serialized bytes of **all authoritative models after each tick**,
  including clock, weather, RNG, food, C/N/P, event history and paths. Never infer
  equivalence from a similar picture or only the final animal positions.
- Each of two trajectories uses three warmup and twenty measured paired ticks.
  A/B execution order alternates every tick; the second trajectory reverses its
  starting order. Comparisons/serialization and scene creation are outside timing.

## Result

All **46 paired ticks** have identical model dictionaries and serialized bytes.
Concatenated reference-state SHA-256:
`3aaf2e956bd210bb5491134c41ba2d2f220be80104f6895b8336a88809cae55b`.
The 40 measured pairs reuse seed 29017, 8541 initial plants and 90 initial animals
in the default 512 m world; each trajectory advances 11.5 hydrological seconds
(1.749 biological days at the unchanged clock multiplier).

| Scope | Hash baseline, mean | Dense candidate, mean | Time reduction |
| --- | ---: | ---: | ---: |
| Animal model stage (40 paired samples) | 95.641 ms | 82.766 ms | 13.46% |
| Sum of all model stages (same pairs) | 216.470 ms | 205.582 ms | 5.03% |
| 1800 plant/insect queries (8 paired samples) | 15.442 ms | 9.179 ms | 40.56% |
| Build both indices (4 samples of 10 builds) | 5.459 ms | 3.375 ms | 38.17% |

Animal-stage mean ratios are 1.152× and 1.159× in the two trajectories; the dense
path wins 18/20 pairs in each. P50 is 93.925 → 83.560 ms and nearest-rank P95
122.331 → 101.990 ms. P95 is descriptive for this small dependent trajectory
sample, not a long-session tail-latency guarantee. Full raw samples, mean,
median, nearest-rank P95, maximum and counts are retained in the artifacts below.

These are **headless wall-clock measurements under existing desktop load**
(Redot, Steam and browser processes were active and untouched), not isolated
process CPU time or rendered FPS. Same Redot 26.3 editor binary, native models,
hardware and inputs; the Dummy renderer is used. The full-model gain is smaller
than the lookup-kernel gain, as expected. No extrapolation to mature, differently
populated ecosystems or large sparse domains; no new GPU thermal soak or rendered
benchmark was necessary because production presentation is unchanged.

## Checks and artifacts

Targeted query/lifecycle benchmark and paired coupled-model assay: PASS, no
`ERROR:`/`SCRIPT ERROR`. GDScript format/lint of the three assay scripts and
`git diff --check`: PASS. Full `tools/check.sh`: **PASS**, all **40 runtime checks**,
native water/soil/fungi checks and editor import. All 41 guarded engine launches
exit 0; all 40 runtime logs are free of `ERROR:`. The saved source hashes still
match the measured candidate. The guard's observed maximum is **51 °C** (the
cutoff remains 75 °C); see `suite-proof.json` for the final machine-readable count.

Headless editor shutdown still reports the four existing RID/TextServer/Viewport
leak categories. Their exact allocation counts match
`artifacts/dod-20261103/baseline-import.log`; there are no parser/load failures.
They are not counted as new runtime regressions or concealed by a zero exit code.

Artifacts: `artifacts/animals-finalize-20261104/`:

- `protocol.json`: predeclared comparison, starting ref and source hashes.
- `paired-profile.json`, `profile.log`, `summary.json`: actual paired samples,
  equality trace and summary statistics.
- `dense-benchmark.json`, `dense-benchmark.log`: ordered/lifecycle assertions and
  lookup/build samples (copied before the general suite replaces its report).
- `profile-guard.jsonl`, `dense-guard.jsonl`, `suite-guard.jsonl`: unchanged
  fail-closed **75 °C** watchdog receipts for every engine launch.
- `suite.log`, `suite-proof.json`, `editor-import.log`: complete check-suite result
  and readback of all engine exits/runtime logs.

## Reproduction and rollback

```sh
tools/run.sh --headless --script res://tools/check_dense_bins.gd -- --benchmark
tools/run.sh --headless --script res://tools/profile_animal_bins.gd
tools/check.sh
```

The profiler writes `artifacts/animal-bins-profile.json`; it is deliberately a
standalone measurement, not forty timing-dependent CI assertions. No threshold
on noisy elapsed time gates model correctness.

Before-state files are under
`/run/media/pavel/Storage/tmp/forest-animals-finalize-20261104/before/`.
For a production rollback restore only the four original spatial-index methods
and two Dictionary fields from starting HEAD, or revert this scoped completion
commit. Preserve the already committed quiet-interface/walking work and any
subsequent independent edits. The new reference subclass is test-only and never
selected at runtime.
