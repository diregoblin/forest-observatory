# Grass lighting, cloud shadows and optional volumetrics — 2026-11-03

Reference: David Holland, [3D Pixel Art Rendering](https://www.davidhol.land/articles/3d-pixel-art-rendering/),
read 2026-11-02/03. This uses current Redot's native LIGHT_VERTEX, shadows and
volumetric fog; it does not reproduce his custom engine patches or shell-raymarch.

## Shipped presentation

- **Grass lighting from the ground**: `LIGHT_VERTEX` blends toward the stable
  tuft root in view space (6 cm above the surface). Normals blend toward world up.
  Near tufts retain some volume; departing tufts converge more strongly to the
  ground. `root_lighting_strength=0` is the original lighting control. Rasterized
  vertices, cutouts, turf density/phenology, LoD and picking are unchanged.
- **Cloud shadows**: one 512×512 HDR field, generated from the existing seamless
  3D cloud noise, is shared by the visible low deck and a shadow-only mesh. This
  avoids recomputing the expensive noise in each directional shadow-map pixel.
  Ordinary native shadows reach terrain, cards, meshes, animals, water and fog
  without replacing PBR, multiplying albedo or removing ambient light.
- **Volumetric light**, off by default: stock Forward+ froxels, volume size 64 and
  depth 32 (height follows viewport aspect), 180 m integration range. No temporal
  reprojection, no new frame-random pattern. Density follows submitted cloud
  cover. Existing pixel enlargement/posterization also affects this image.
  This is currently soft scattering/mist; it is not a claim of crisp hand-drawn
  light slices like the article. Visibility depends on sun/view direction and
  actual occluders. Other rendering backends disable its checkbox.

All three have independent controls in **Options → View**, beside bank detail.
Grass lighting and cloud shadows start on; volumetrics and bank detail start
off. These are current-session presentation preferences, not ecological state
or new entries in saved-world model schemas. The soil diagnostic temporarily
suppresses volumetric fog and restores the preference on exit.

### World deck and finite bounds

For the default 512 m world, the low cloud deck is 256 m high and 4096 m wide.
Its visible projection is now world-anchored, not tied to camera translation.
The old standalone sky path remains for fixtures without a configured world.
The far edge of the cached field blends to the procedural sky to avoid a
clamped-texture stripe. The upper wispy layer retains its previous sky-only
presentation and does not cast a second strong cloud shadow.

The caster has 64×64 cells: a giant two-triangle plane deforms under directional
shadow pancaking. When clouds cast, the light's pancake is conservatively
expanded to `height / max(sun_y, .18) + 96 m`; when disabled it returns to 20 m.
The previous 28/84/280/819.2 m receiver cascades remain unchanged. Shadow
presence fades between sun_y=.18 and .30, and is absent below that finite
daylight coverage, not extrapolated into arbitrarily distant grazing rays.
The finite, horizontal deck is not a volumetric weather simulation or a promise
for cameras above the cloud layer. Shadow silhouettes are stylized cutouts,
not physically broad cloud penumbrae.

The field updates only when submitted weather time changes, or asynchronous
NoiseTexture3D generation finishes. Camera movement cannot move the map. Pause
and baseline style do not continually redraw it. No TIME-based independent
ecological clock, model RNG calls or worker-owned reads were introduced.

## Verification

```sh
tools/check.sh > artifacts/cloud-light-suite.log 2>&1
GPU_GUARD_LOG=artifacts/cloud-light-verified2-guard.jsonl tools/preview_isolated.sh --script res://tools/check_cloud_lighting_render.gd
GPU_GUARD_LOG=artifacts/cloud-light-final-guard.jsonl tools/preview_isolated.sh --script res://tools/preview_cloud_lighting.gd
```

- **37/37** fresh general engine checks, native checks and standard native
  benchmark completed; suite exit 0, no engine-check errors.
- `artifacts/cloud-lighting-check/report.json`: independent sun-ray/plane
  projection agrees with the native cloud mask. No-caster negative control,
  solid-caster positive control, clear/cloudy samples, near and ~386 m distant
  receivers, and low 20° light from opposite directions all passed.
  Mean RGB: near clear .803922 / shadow 0; far clear .807843 / shadow 0;
  low east/west opaque controls 0. Ambient-only shaded control .495425,
  proving ambient is preserved rather than the whole image darkened.
- Camera translation leaves the field byte-identical; advancing submitted
  weather time changes it. Baseline and below-horizon behavior passed.
- `artifacts/cloud-lighting/report.json`: actual GUI-input clicks round-trip
  all three checkboxes and their underlying render settings. Soil diagnostic
  suppression/restoration passed. All model snapshots stayed byte-identical.
- Same-camera grass A/B, cloud A/B/advection, actual grove volumetrics and
  small camera movements captured and inspected. Options fit the existing
  window; no new main-screen controls. The user's running window and saves
  were not touched.
- Final oracle and full-scene guards exited 0, maxima **55 / 56 °C** (limit 75).
  `git diff --check` passed.

### Cost and rejected trials

The direct procedural caster took ~11 ms versus ~4.9 ms for the initial
overview without it; it was rejected. The shared-field version eliminates
those repeated multi-octave noise evaluations. The final cached caster adds
four shadow draw calls and 32,768 triangles across four cascades in the overview.
The separately measured, animated map was ~.08–.19 ms in the final fixture.

Short alternating whole-scene GPU blocks were noisy: volumetric-off medians
5.26/7.29 ms, on 5.75/7.15 ms; cloud-shadow-off 9.56/7.29 ms, on 8.69/8.98 ms.
These overlap and do **not** establish a precise FPS cost or speedup. Both
effects remain switchable; the small map's cost is reported separately from
the world/composition viewports instead of silently omitted.

Earlier failed/rejected logs are not pass receipts: initial parser fixtures;
the unsplit/high-plane near-cascade failure; and a low-sun assay which forgot
that set_season restores natural ambient. The last was corrected by explicitly
zeroing ambient again after each climate change, not by tuning production
lighting to force the test. No shadow-bias or global-darkening workaround from
the diagnostic sweeps was retained.
