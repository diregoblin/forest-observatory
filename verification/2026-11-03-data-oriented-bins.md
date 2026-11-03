# Data-oriented animal lookup — 2026-11-03

Completion and current paired consumer measurements:
[2026-11-04 finalization](2026-11-04-animal-bins-finalized.md).
The measurements below remain the original historical observations.

## Scope

User-requested application of [Jarred Sumner's performance notes](https://x.com/jarredsumner/status/2117037940031496252)
and [his follow-up](https://x.com/jarredsumner/status/2117039564221256052).
The applicable technique here is replacing hash-keyed containers and separate
per-bin Arrays with flat integer-indexed storage. Forest models already use
packed structure-of-arrays for their authoritative state; that layout is retained.

Starting checkout: clean `master`, HEAD
`190d40247098f8b47ecc1b28aec6ed537881f838`. Changes affect derived animal spatial
indices only, plus their regression/benchmark and check-suite registration.
No model formula, fixed-step interval, number of individuals, climate, plant
traits, finite reserve, RNG operation, presentation, driver, service or user save
is changed. No new cache or native dependency is introduced.

## Mechanism and ordering

A valid plant position lies in the bounded landscape, already validated by the
plant restore/creation boundary. A bin therefore has the dense index
`z * ceil(extent / 8 m) + x`. Each index stores one head ID; one packed `next`
array stores links keyed by the existing stable plant or insect-site ID. Bin
heads reset when the old maps were rebuilt. The next links are overwritten only
for active IDs; no consumer can reach stale dead links from a fresh head.

Reverse-ID insertion preserves the previous ascending-ID order within each bin.
Queries retain outer z/x iteration and exact distance filtering; insect queries
still sort by habitat ID to preserve the full-scan equal-score tie. They index
actual feeding positions, including sites away from nominal cell centres. Food
pools remain live and uncached; out-of-step insect calls still use a fresh full
scan. Restore and each coupled tick rebuild/invalidate at the same boundaries.

Default 512 m world: two 4096-entry head arrays, one link per plant, and one link
per 256 habitat sites. The storage is O(world-bin area + individuals); it is
appropriate for this bounded dense landscape, not a general sparse-world claim.

## Verification and timing

`tools/check_dense_bins.gd` compares the ordered query results against the frozen
hash-map implementation, including domain/bin edges, out-of-domain query centres,
zero radius, small and large radii, dead plants, appended/coincident IDs and
feeding points far from nominal centres. It checks 810 ordered queries. Existing
`check_animal_fastpath.gd` independently checks decisions against a full scan.

Full model comparison uses the existing synchronous real coupled-tick harness,
three warmup plus ten measured ticks, default seed 29017, 8541 plants and 90
animals. Source-stage samples and logs are retained in `artifacts/dod-20261103/`.
All launched engine processes use the existing fail-closed 75 C GPU guard.
Timings are headless wall-clock under untouched existing desktop/human workloads,
not process CPU time, rendered FPS, an aged-ecosystem speed or a thermal soak.

The paired kernel assay alternates hash/flat execution order and measures the
same queries on both sides: one warmup plus eight measured samples, 1800 queries
per sample. Its synthetic fixture retains founder animal locations/radii and
adds dead plants, coincident late IDs and off-centre insect sites. Build timing
is reported separately from query timing. Neither ratio is a whole-game speedup.

| Scope | Hash maps | Flat indices | Ratio |
| --- | ---: | ---: | ---: |
| 1800 plant/insect queries, mean | 15.503 ms | 9.270 ms | 1.672× |
| Both index builds, mean per build | 5.304 ms | 3.375 ms | 1.572× |

Eight measured query samples; four measured build samples (ten builds/sample),
with warmup discarded. This includes no new native code. Build timing includes
flat-path species-membership maintenance, while the frozen hash builder measures
only spatial indices; the candidate still wins that conservative comparison.

The full 13-tick authoritative model bytes are identical: 11,238,420 bytes,
SHA-256 `f5c5f545296ec729a8c589a90c2ee4721270713aa6b4203b907f4f2343c58a43`.
That covers model state, RNG, food and C/N/P, paths and events. There is no save
schema migration. The kernel assay checks 810 ordered queries; the independent
full-scan decision regression checks 54 cases and model dictionary equality.

Whole animal stage mean in initial sequential runs was 94.515→92.773 ms;
whole tick 214.614→230.791 ms, with untouched habitat/plants/soil also slowing.
These runs do not establish a reproducible whole-tick gain: existing background
load drift is visible and the demonstrated result is the isolated lookup/build
improvement. No rendered FPS claim is made.

Final exact-source repeat: animal stage 76.513 ms, whole tick 187.395 ms, again
with identical model bytes. The variation across runs reinforces the scoped
kernel conclusion; no whole-tick ratio is attributed to this small layout diff.

`tools/check.sh`: PASS, all **40 engine checks**, native hydrology/soil/fungi
checks and editor import. This includes live-worker completion/joins, coupled
continuation, finite food, C/N/P accounting, atomic save rejection and controls.
Receipt: `artifacts/dod-20261103/suite.log`. The final dense-bin regression and
13-tick state trace were rerun after removing an unnecessary `maxi(1, ceil(...))`
guard; `ForestSettings.validate` already requires positive extent. Redundant
next-link fills were also removed: fresh heads make stale dead links unreachable.
Necessary query rectangle clipping remains because query centres may be outside
the domain. No per-plant validation or repeated world scan was added.

Headless editor import prints four existing RID/TextServer/Viewport leak-at-exit
errors. A guarded baseline-source return control reproduces the same four types
and allocation counts exactly (`baseline-import.log` versus `artifacts/import.log`).
Neither import has parser/load failures. The 40 runtime check logs contain no
`ERROR:`/`SCRIPT ERROR`. These editor-exit leaks are recorded, not classified as a
new model regression or hidden behind the suite's zero exit status.

New test lint and `git diff --check` pass. Presentation is unchanged and model
bytes are equal; no additional rendered benchmark or GPU thermal soak was run.

## Reproduction and rollback

```sh
tools/run.sh --headless --script res://tools/check_dense_bins.gd -- --benchmark
tools/run.sh --headless --script res://tools/profile_model_stages.gd
tools/run.sh --headless --script res://tools/check_animal_fastpath.gd -- \
  --reference-models=/run/media/pavel/Storage/tmp/forest-dod-20261103/models-baseline.bin
tools/check.sh
```

Read `artifacts/dod-20261103/comparison.json` for samples, exact state comparison,
source hashes and the timing boundary. The temporary pre-change source is
`/run/media/pavel/Storage/tmp/forest-dod-20261103/animals.gd`; restore only that
scoped source (or reverse the final scoped diff), remove the new test/registration
if rolling back the feature, and retain unrelated later edits. No old project
copy, engine replacement, published branch or long-running process is involved.
