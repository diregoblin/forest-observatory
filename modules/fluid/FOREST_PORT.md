# Forest laboratory port — 2026-11-01

**Parked by Pavel on 2026-11-01.** Keep the smoothed mesh river in normal play.
No further SPH runs or integration are pending under this task.

Source: our Night Shift/flask project, `/run/media/pavel/Storage/src/fluid-sim/project`.
`UPSTREAM.json` records the inherited Git HEAD and **source working-tree** hashes.
That checkout was dirty; the HEAD alone does not reproduce the copied source.
The donor checkout was left untouched. The original addon MIT notice is retained
in `LICENSE`; Night Shift's own modifications are part of our existing project.

## Local differences

- `compute_shader.gd` loads the original GLSL text through
  `RenderingDevice.shader_compile_spirv_from_source`. The official Redot editor
  crashed while importing GLSL in a worker. The shader folders have `.gdignore`,
  and four GDScript shader-resource loads use this process-local bytecode cache.
  No donor `.godot` cache/import metadata is shared. GLSL equations and dispatch
  order are unchanged. Exporting a standalone PCK would additionally require
  including these raw GLSL files; only local checkout execution is verified.
- `scripts/sph_river_probe.gd` subclasses the donor model: four-layer initial
  slab, a local MultiMesh AABB, inexpensive optional particle visualization.
- `tools/probe_gpu_water.gd` owns the isolated assay clock and the borrowed
  screen-space effect. It retires render work before freeing a model's buffers.

The module is **not instantiated by the normal forest scene**. It is an
independent box-domain experiment; it has no terrain collision or water ledger
exchange with `ForestWatershed`. In particular it is not a second backend for
the existing native local-inertial watershed model.

Run from the repository:

```bash
./tools/probe_water.sh
./tools/probe_water.sh --particles --counts=8192
```

Each run exits automatically. A 35-second timeout and a fail-closed 65°C GPU
watchdog bound this assay. The normal project ceiling remains 70°C. Window size
is 960×600; the pixel world is 480×300. The default close-up makes the SPH patch
visible. Output is in `artifacts/water-gpu-preview/`; each run overwrites its
named frames/report, while guard records append. No world saves are read/written.

## Model boundaries

The existing solver uses one SPH step per 1/60-second tick, analytic box walls,
optional boundary samples and baked SDF collision. This assay enables neither
vessel particles nor SDF. Radius is 0.05 m; support is 0.4 m; derived spacing is
about 0.1857 m; gravity is 9.81 m/s². Increasing count increases nominal volume
at fixed spacing. The source's pressure/viscosity scaling is particle-scale
similarity, not fixed continuum material parameters under refinement.

CPU submission, GPU compute timestamps, viewport rendering and completed frame
intervals are recorded separately. Timed windows have no particle readback or
main-device `submit`/`sync`. The independent gravity control checks transport;
pressure, viscosity and long-term physical accuracy are not independently
validated by this port. Screen-space water retains its source approximation
and edge/transparency limitations. Source README timings concern another scene.

See `verification/2026-11-01-surface-water.md` for measured forest results.
