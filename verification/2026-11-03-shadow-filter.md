# Cloud-shadow sampling grain and live quality option — 2026-11-03

Pavel's screenshot showed pepper in the wide cloud penumbra, despite acceptable
nearby tree shadows. The existing solid cloud cutout was not alpha-hashed:
the native finite-disc filter used default Low directional-shadow quality (2).

## Installed

- Default directional filter is Ultra (5) in `project.godot`. Cloud caster,
  solar angular size/taper, map resolution, cascades and fog are unchanged.
  Residual sampling grain is reduced, not eliminated. No new render pass.
- Options → View → Shadow quality exposes Low/Medium/High/Ultra (native 2–5).
  HUD emits the choice; the composition root routes it to atmosphere's bounded
  setter. It affects directional sunlight on clouds AND trees, not ambient
  brightness or positional lights. Changes are live, current-launch only,
  and survive presentation-mode/cloud-shadow toggles. No save-schema changes.

## Verification

`tools/preview_cloud_shadow_filter.gd`: actual Forward+ receipt
`artifacts/cloud-shadow-quality-final.log` exited 0, no script/assert errors.
All four real popup selections (mouse + directional keyboard navigation)
reached the atmosphere; default UI selected Ultra. Neutral straight-edge images
were taken after GUI selections, with no direct renderer override, also checking
the live wiring. No ambient/fog/vegetation texture can hide grain in this control.
Local high-frequency RMS .070968 → .022478 (68% lower); old Low is the negative
control and the checker rejects improvement below 40%. This is image grain,
not physical cloud transmittance. Saved ground/valley A/B, neutral edge and
short-motion images inspected. Authoritative model snapshots byte-identical.
`artifacts/cloud-shadow-filter/options.png` shows the complete graphics menu.

Interleaved Low/Ultra phases, 1200×750 output / 600×375 world: median measured
total GPU time 1.478 → 1.574 ms (valley), 4.887 → 5.598 ms (close forest).
Close-view timing drifted with concurrent desktop load: short paused render
measurements, not active-world FPS or a thermal soak. Quality is not free.

`artifacts/cloud-shadow-filter-oracle.log`, exit 0: existing independent
ray/plane oracle passed clear/solid, preserved ambient, shared cloud field,
near/far receivers, low sun from both sides, world anchoring, submitted-time
advection and baseline/below-horizon controls. Low-sun solid controls were black.
No model changes, so the full ecological suite was not rerun. All GPU runs used
`tools/run.sh` and the 75 C guard. User window/saves unchanged. Git is rollback.

Earlier helper failures are not passes: a fixed ROI missed the edge in a HiDPI
window (fixed with proportional bounds); native PopupMenu does not support
Home navigation (replaced with directional keys). Accepted receipt has neither.

Reproduce: `tools/run.sh --script res://tools/preview_cloud_shadow_filter.gd`.
Append `-- --ui-only` for just the GUI smoke. Use current display authentication.
