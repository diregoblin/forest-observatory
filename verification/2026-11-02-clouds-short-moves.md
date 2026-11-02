# Clouds and short animal approaches — 2026-11-02

## Scope and final choice

Pavel reported hard cloud boundaries and occasional missing hare locomotion,
especially over short moves between food patches. The original sky was a
procedural 2D field projected as a horizontal sheet, not separate sprite tiles.
Pavel explicitly rejected the spherical/dome candidate because it lost the
flat sheet's useful perspective. That candidate is **not** the installed version.
Extra cloud tiers were discussed and then explicitly deferred pending viewing.

The installed shader retains the original sheet projection:
`EYEDIR.xz / max(EYEDIR.y + .22, .10) * 2.4`.
It samples a fixed-height slice of an engine-generated seamless 128³
FastNoiseLite texture instead of the old fragment float-hash field, widens
the edge transition from .025 to .07, softens interior tones, and fades
clouds near the horizon. The 3D texture is only a lookup, not cloud geometry,
volumetric simulation or raymarching. The weather model, sky lighting path,
palette inputs and model clock are unchanged. No FPS improvement is claimed.

## Hare diagnosis and fix

A real one-animal feeding chamber reproduces a tick with two moving path
segments followed by six stationary feeding segments. The old view selected
`feed` from the action at tick end and applied it to the entire path. This
suppressed locomotion while the animal was still visibly approaching food.

The committed presentation frame now includes an optional resource-derived
`travel_clip`. The view selects the clip from the segment currently being
interpolated, not solely from the end action. Stationary segments do not
continue a hop/walk just because the final action is locomotion. Position
interpolation is unchanged. Old frame buffers without the optional key remain
valid; malformed new clip values are rejected. No animal model/physiology,
food reserves, traits, path decisions, clock or save version was changed.
This fixes the reproduced missing-hop case, not a claim about every possible
source of stutter under overload or accelerated simulation.

## Checks

- `tools/check_short_animal_motion.gd`: PASS, two moving / six feeding segments.
  The final-action-only policy is an explicit known-wrong control. Checks cover
  101 position samples without teleporting, actual AnimationPlayer clip,
  GPU shader parameters matching CPU pose, unknown gait choice through data,
  optional-frame compatibility, invalid-clip rejection and unchanged model.
- Actual Forward+ hare preview: PASS, before/after captures at four path phases;
  final log `artifacts/short-animal-motion-render-verified.log` is error-free.
  Early fixture shutdown leaked unparented rain particles; the fixture now
  attaches the observer/particles through the normal atmosphere API and frees
  its stage before exit. No production cleanup patch was needed.
- Actual Forward+ flat-cloud preview: PASS; day in pixel and painterly modes,
  broken cloud, sunset, overcast and night, plus four bearings and zenith.
  Saved images were inspected; model snapshots stayed byte-identical.
  `artifacts/cloud-edges-flat.log`, `artifacts/cloud-edges/report.json`.
  RGB differences only show an observable change, not a quality score.
- `tools/check.sh`: PASS. `artifacts/sky-hare-checks.log` ends in suite PASS.
- `gdlint` on the four touched/new scripts: PASS. `git diff --check`: PASS.
- All engine launches used the existing 75 °C GPU guard. No driver/fan/power
  changes or thermal soak. No external textures, dependencies or AI images.

Initial alternative fragment gradient noise and a seamless 2D lookup retained
unwanted cut-paper forms in the plane projection. A dome removed that effect
but Pavel rejected its perspective. The final flat-plane / 3D-noise-slice
candidate was rendered after that correction, not confused with the dome PNG.

## Files and rollback

Production: `shaders/painterly_sky.gdshader`, `art/clouds/noise.tres`,
`scripts/painterly_style.gd`, `scripts/animals_view.gd`.
New helpers: `tools/preview_cloud_edges.gd`, `tools/check_short_animal_motion.gd`;
the regression is included in `tools/check.sh`. Motion docs and README updated.

Pre-task shader/view copies are outside the project at
`/run/media/pavel/Storage/tmp/forest-sky-hare-20261102/`. The style rollback copy
is reconstructed by removing only this task's new cloud sampler assignment.
Restore only these scoped changes, never reset the heavily dirty checkout.
