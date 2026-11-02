# Flat cloud tiers, display clock and animal CPU cost — 2026-11-02

## Scope and ownership

Pavel approved the softened flat cloud projection, requested low dense and high
light clouds, reported stepped sun after the first day and stepped water, then
asked about CPU bottlenecks and authorized prioritizing animal performance.
The engine/driver, services, user data and unrelated dirty work were not changed.
Starting HEAD: `1a56e0a1cbca9651cc67ad1847392e18d172766a`; the checkout already
contained substantial uncommitted work, so HEAD alone is not the baseline.

The coupled simulation still runs sequentially on **one CPU worker**. Rendering,
input and the engine's own threads are separate. No GPU simulation, parallel
model writers, variable physical timestep or lower decision frequency was added.

## Reproduced display faults

The previous display cursor followed `elapsed_s + pending_s - 2 * step`. Under
overload, pending requests accumulate; this is not elapsed presentation time.
Eventually every completion exhausted the submitted buffer and the sun stood
still until the next tick. The fix advances by render delta, limited by requested
speed, measured worker production and the committed horizon. It approaches an
exhausted horizon rather than extrapolating. Production measurement excludes
buffer-full idle, so accelerating after x1 does not inherit an artificial cap.
Backpressure keeps four submitted paths from evicting still-displayed samples.
Physical clocks, completed ticks, resource accounting and RNG are unchanged.

Water had two independent faults: ripple uniforms were below the busy-worker
early return, and depth blending lasted 0.1 s despite less frequent uploads.
Ripple phase now samples the detached display climate on busy frames too.
Depth updates rebase onto the **currently displayed** CPU image, then approach
the new target exponentially using the observed upload interval. No GPU readback
is introduced; float64 reserves remain authoritative. Pause freezes blending;
an explicit restored-world refresh immediately displays that world's own depth.

`check_timeline_debt.gd` uses real coupled ticks/held workers, a frozen old-policy
negative control, 100 s requested debt and an accelerated **2 s solar period**.
Across 160 controlled busy frames (>2 solar days), the old sun stopped 152 times
and old ripple phase 160 times; the candidate stopped neither. This is not a
four-minute rendered soak or an aged-second-day ecosystem benchmark. The fixture
also checks production-rate recovery, buffer backpressure and pause.

## Sky

The approved perspective projection remains flat, not a dome. A higher, thinner,
stretched noise sheet is drawn behind the low deck; its angular scale, opacity
and drift differ. Dense low clouds darken with cloud cover. The seamless 128³
FastNoiseLite resource is only a lookup, not volumetric geometry/physics or
calibrated cloud altitudes. Cubemap lighting retains its cheap gradient path.

Actual Forward+ inspection covered pixel/painterly daytime, broken cloud, sunset,
overcast, night, four bearings and zenith. Low-only/high-only controls contribute
visibly, and wind changes the composite. Model snapshots remained equal.
Images: `artifacts/cloud-layers/`; log `artifacts/cloud-layers-preview.log`.
RGB differences show observability, not a quality score or FPS improvement.

## Animal diagnosis and exact fast paths

Temporary inclusive function profiling identified insect seeking at approximately
144 ms/tick and nearest-threat search at 34 ms/tick. These are nested in animal
time and must **not** be added to total tick time. The insect scan repeatedly
computed terrain height for 256 centres only to convert each centre back into its
already-known cell ID. It ran about 141 times/tick in this initial scenario.

Changes:

- Fixed habitat cell geometry is computed once; food lookup accepts a cell ID.
- Insect feeding points have an 8 m spatial index valid only during the owned
  animal step. It indexes actual plant/feeding positions, not nominal cell centres.
  Available food remains live and uncached. Outside the step, direct calls use
  a fresh full scan. Restore invalidates the derived index.
- Species membership is derived/rebuilt and maintained for appended IDs. Threat
  queries inspect only species whose current diet can include the observer.
  They still check live positions/alive flags, with the original lowest-ID tie.
- Candidate insect IDs retain reference scan order. No decisions, motion,
  reactions, metabolic transfers, population or fixed-step cadence were skipped.

### Timing

Intel i5-10600KF, Redot 26.3 stable, headless full default model, seed 29017,
8,541 plants / 90 founders. Three warmup + ten measured coupled ticks per run;
0.5 hydrological seconds/tick, 6,570 biological seconds/tick. Before/after runs
were sequential without concurrent agent-launched tests. Existing human/desktop
workloads were left alone: these are scoped wall-clock timings, not process CPU
time, GPU FPS, long-term thermal validation or a late-ecosystem benchmark.

| Stage | Before mean, ms | After mean, ms |
| --- | ---: | ---: |
| Animals | 271.00 | 94.65 |
| Plants | 96.86 | 95.20 |
| Habitat | 27.72 | 27.37 |
| Groundcover | 5.21 | 5.87 |
| Fungi | 3.90 | 4.19 |
| Soil | 3.72 | 3.85 |
| Weather + water | 0.86 | 0.92 |
| Whole tick | **409.27** | **232.05** |

Animal stage **2.86×**; whole tick **1.76×**. Animal p50 265.88 → 94.01 ms,
max 320.14 → 116.86 ms. Tick p50 403.81 → 233.71 ms, max 457.85 → 285.69 ms.
With ten samples, nearest-rank p95 equals the sample maximum. Plants and animals
now have comparable cost; this is not a claim that the whole game runs 1.76× faster.

Raw samples/statistics/source hashes: `artifacts/animal-cost-comparison.json`.
Final log: `artifacts/model-stages-final-verified.log`; harness
`tools/profile_model_stages.gd`. Two earlier baseline runs gave animal means
265.80 and 271.00 ms; an earlier candidate gave 90.71 ms. The final table uses
the final 94.65 ms sample, not the most favourable candidate run.

## Checks and limits

- Whole authoritative model dictionaries after the same 13 coupled ticks match
  the baseline exactly, including RNG, paths, events and C/N/P, not just visuals.
  Final serialized bytes also match (11,225,392 bytes, SHA-256
  `7744ddf17ea811d35cc59c34b751e1ae9ce43dcadf104378249b09d31e4e8140`).
  `artifacts/animal-cost-equivalence.json` and the explicit reference-model run.
- `check_animal_fastpath.gd`: 54 full-scan/indexed decision equivalence cases,
  domain edges, off-centre feeding sites, fresh finite pools, out-of-step calls,
  unknown predator traits, dead predators, appended IDs and cross-species ties.
- `check_water_chunks.gd`: 12,288 independent wet-support stencil samples,
  interrupted blending, three irregular upload intervals, pause and immediate
  reset. Both regressions and the debt regression are in `tools/check.sh`.
- `tools/check.sh`: PASS, 32/32 engine checks exited zero without `ERROR:`, plus
  native hydrology/soil/fungi checks and import. Final suite log:
  `artifacts/sky-timeline-suite-final.log`.
- Final Forward+ motion run: PASS, 120 rendered frames, 35 worker-busy frames,
  no stopped sun; per-frame angular range 0.000618315–0.000618869 rad at fixture
  dt 0.025 s, x1. Detached-view, picking/follow, pause and internal state-roundtrip
  checks passed. `artifacts/timeline-live-final.log` and
  `artifacts/smooth-motion/report.json`. This was a short correctness check,
  not a draw-FPS benchmark. Guard maxima: 59 °C clouds, 60 °C final motion.
- Formatting and new-helper lint checks are scoped. Existing animal/habitat
  scripts already fail generic max-lines/max-returns/order lint rules; those
  baseline style failures were not reclassified as new regressions or hidden.

Pavel's speed question: this initial 232 ms / 0.5 s-tick scenario gives an
idealized ceiling of about 2.2× before display overhead. 60× needs 8.33 ms/tick,
about 28× faster again; headless/graphics-off alone cannot supply that. A proposed
interactive goal is stable x1 with growth headroom, then x4–8. This is a target,
not a measured capability or an authorization to begin a new native backend.

Cold CLI fixture note: parser-time inheritance/type/constant references to the
animal model caused two new fixtures to preload bare animal Resources before
their script dependencies were ready. Keeping the definition preload and loading
the composition root/model at runtime fixed the fixtures. The failing fixture
logs were not accepted as either timing results or model regressions.

All engine launches use the 75 °C guard. No thermal soak, power/fan/driver change
or promise of eliminating arbitrary pauses under unbounded overload.

## Rollback and reproduction

Pre-task display sources: `/run/media/pavel/Storage/tmp/forest-sky-timeline-20261102/`.
Pre-optimization animal/habitat sources, baseline model dictionary and timings:
`/run/media/pavel/Storage/tmp/forest-animal-cost-20261102/`.
Restore only scoped changes; never reset this dirty checkout.

```sh
tools/run.sh --headless --script res://tools/profile_model_stages.gd
tools/run.sh --headless --script res://tools/check_animal_fastpath.gd -- \
  --reference-models=/run/media/pavel/Storage/tmp/forest-animal-cost-20261102/models-before.bin
tools/check.sh
tools/preview_isolated.sh --script res://tools/check_smooth_motion.gd
tools/preview_isolated.sh --script res://tools/preview_cloud_layers.gd
```

The cloud A/B preview intentionally requires the retained pre-task shader copy;
ordinary scene startup and regressions have no dependency on that rollback path.
