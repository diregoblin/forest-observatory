# Soft cloud fringes, horizon and penumbra — 2026-11-03

Pavel reported over-bright hard cloud edges, sharp cloud shadows and a vertical
smear at the far horizon. The approved flat perspective projection is preserved.

## Installed choice

- `cloud_opacity.gdshaderinc` shares the low-deck density-to-coverage mapping.
  Visible sky mixing now transitions across .16 field units instead of .07,
  retaining dense cores. The edge colour is less bright/saturated; it is not
  an independently added glow or a transparent mesh sorting problem.
- Both sky decks fade from zero at EYEDIR.y=.08 to full at .22. Below .08 the
  world-deck projection uses its grazing-angle clamp: clouds are now invisible
  there instead of stretched into a vertical wall. This is sky-only horizon
  composition, not removing the near cloud caster or flattening the landscape.
- Native cloud shadows retain a solid cutout. Finite-disc filtering supplies
  a broad penumbra from the elevated deck. The artistic solar angular size is
  up to 1.5 degrees, tapered by smoothstep(.18,.60,sun_y) to avoid low-sun
  finite-filter leakage. It follows the cloud-shadow option and returns to zero
  when the deck is not casting. Other nearby casters also use the sun's filter,
  but have much shorter penumbrae because of their small receiver separation.
  No global shadow-quality override or temporal reconstruction was added.

This is a presentation change, not volumetric weather or fractional physical
cloud absorption. Cloud shape advection, the shared HDR field, models, worker
ownership, water physics and save schemas are unchanged.

## Verification

- `artifacts/cloud-softness-accepted.log`: real paused Forward+ A/B in pixel and
  painterly modes, day/broken cloud/sunset/overcast/night, four bearings and
  zenith. Valley cloud-shadow A/B and three small camera moves inspected.
  Model snapshots were byte-identical. No script/assertion errors in this run.
- Independent straight-edge receiver control: clear/solid mean RGB .786928/0;
  intermediate pixels in a fixed ROI increased from 136 with a point sun to
  14,692 with the finite disc. The point-sun control rejects the old hard edge;
  these are display measurements, not optical transmittance estimates.
- `artifacts/cloud-softness-oracle-final.log`: existing independent ray/plane
  cloud-shadow oracle passed, including clear/solid, preserved ambient, actual
  cached cloud field, near/far receivers, 20-degree sun from opposite sides,
  world anchoring, submitted-time advection and baseline/below-horizon controls.
  It explicitly disables the now-default-on volumetrics to isolate direct light.
- Both accepted runs exited 0 under the 75 C guard. General ecological suite
  not rerun for these shader/presentation changes. No FPS claim is made.

Rejected trials: native alpha-hashed coverage gave valid intermediate shadow
intensities but visible pepper across the valley, so it is not installed. The
initial untapered 1.5-degree disc leaked .023 RGB in the low-sun solid control;
that failed run is not a pass receipt. The low-elevation taper restored a black
solid control without relaxing the oracle. Some sampling grain remains possible
within the native finite-disc penumbra, not across the full translucent fringe.

Follow-up: Pavel observed that grain at ground level. Directional filtering
was subsequently increased and made user-adjustable; see
[shadow-filter verification](2026-11-03-shadow-filter.md). The original receipts
above describe the earlier default-quality setting, not this later change.

Scoped pre-task shader copies: `/run/media/pavel/Storage/tmp/forest-soft-clouds-20261103/shaders/`.
The comparison helper uses those explicit reference paths; it does not read or
rewrite user saves. Existing user window was not restarted.
