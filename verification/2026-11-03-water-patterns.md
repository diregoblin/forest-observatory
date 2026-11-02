# Irregular water detail — 2026-11-03

Pavel reported rain circles arranged in rows and distant water appearing striped.
Both were presentation artifacts: `fract(p*1.7)` repeated identical synchronous
circles, while fixed sine waves and axis-aligned normal components made a lattice
of long coherent highlights. No hydrological change was needed.

## Installed

- Rain hits use stable world-cell hashes with independent phase, placement and
  activation. Each hit expands and fades, then gets a newly jittered location.
  Sampling neighbouring cells prevents clipping expanding rings at cell edges.
  This is decorative surface detail, not discrete physical rainfall or mass.
- Water normals use gradients of three advected noise fields with unequal scales
  and rotated coordinates, replacing the parallel sine fronts. A first trial
  merely warped the sines, but still showed curved rows from afar; it was replaced.
- Wave frequencies fade with the world-space footprint of the rendered artistic
  pixel. Subpixel rain rings fade too, instead of aliasing into distant patterns.
  Specular lighting and depth-based mineral/vegetal colours remain native.
- All animation still uses the submitted `weather_time` and `rainfall` uniforms;
  no TIME clock, model RNG, CPU upload, new geometry or simulation write was added.

## Checks and limits

`tools/preview_water_patterns.gd` / `artifacts/water-patterns-final.log`:

- Paused real Forward+ A/B at identical camera/climate for near and far water:
  dry day, rain, sunset, night; four short rain phases captured and inspected.
  The final overview loses the regular bands; near rings are individually
  positioned and phased rather than a tiled synchronized pattern.
- All model snapshots stayed byte-identical. Source comparison also confirms
  stage reconstruction, vertex displacement and the wet/dry mask are identical
  to the pre-task shader. No new physical waves, extra water or shoreline edits.
- Exit 0; no script/shader/assertion errors. 75 C guard maximum 54 C.
  `git diff --check` passed. The general ecological suite was not rerun for this
  surface-only shader edit.
- Short whole-scene GPU observations are noisy and include camera LoD rebuilds;
  no precise FPS cost or speedup is claimed. This is not an ocean model or a
  validation of real wave/current/rain dynamics. Rain circles are deliberately
  subtler at night and disappear when smaller than the image can resolve.

Production file: `shaders/water.gdshader`. Scoped shader rollback/reference:
`/run/media/pavel/Storage/tmp/forest-water-patterns-20261103/water.gdshader`.
The user's running window and saves were not touched.
