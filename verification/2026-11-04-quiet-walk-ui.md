# Quiet controls and terrain walking — 2026-11-04

## Scope

Pavel requested an improvement to the forest, then explicitly asked to rethink
its interface, remove the RMB requirement for WASD, and avoid visible hints or
interface clutter. Starting HEAD was `190d402`. Existing uncommitted animal
dense-bin changes, their tests and check.sh registration were left in place;
`animals.gd` and `check.sh` match the starting copies byte for byte. They are not
part of this change. No user save, service, engine, ecological
formula, simulation clock or resource was changed.

## Delivered behavior

- WASD translates without holding RMB. RMB only looks; Q/E changes altitude in
  flight and Shift accelerates. Diagonal input is normalized. Movement leaves
  animal following, independently of the pointer capture state.
- The existing camera menu contains flight/walk modes and viewpoints. The main
  toolbar is narrower, the menu/title quieter, and no new permanent panel or
  key legend was added. Optional controls/help stay in the menu.
- Walking uses Terrain3D's interpolated surface, 1.7 m eye height, 2.2 m/s or
  5 m/s with Shift, horizontal view direction and short bounded movement samples.
  It blocks steep banks (rise/run > 1.1) and displayed water deeper than 45 cm.
  The water query reconstructs the same wet-cell stage as the display shader,
  using submitted CPU images only; it never reads a worker-owned model.
- Walking is a camera constraint, not a new physical character. There are no
  collisions with tree trunks, rocks or animals, nor a new snow/ground solver.
  Optional centimetre-scale shader bank detail is not authoritative terrain.
- Modal menus, text entry and window focus loss block physical-key polling.
  A mouse release remains effective over UI. Focus/cancellation releases capture.
- The observation card grows to its content, caps its height, and scrolls detail
  beneath an always-accessible title/close row. Selecting a new object collapses
  the optional detail again.
- Whole-world saves retain walking mode. A missing field means legacy flight;
  invalid types or simultaneous walking/following are rejected before mutation.

## Verification

`tools/check_camera_walk.gd`, invoked by the normal controls check, uses analytical
flat/sloping surfaces, blocked-bank and deep/shallow-water controls, independent
expected horizontal travel at several pitches, diagonal normalization, stalled
frame/domain bounds, mode/focus transitions, and a wet-corner/dry-high-bank stage
reconstruction. It checks exact model preservation, save round-trip, corrupt
state rejection and the legacy default. Existing follow tests still pass.

`tools/preview_walk_ui.gd` ran in an isolated X11 display with actual Forward+
Vulkan. Native XTest held-key input proved WASD without RMB, native camera-menu
selection, blocking inside menus and a focused LineEdit, and escape/release
behavior. Pointer clicks went through the viewport GUI, not direct signals.
The fixture disables the unrelated preview.sh camera tour and publishes the
initial committed frame before freezing the model for comparison.

Final evidence: `artifacts/walk-ui-verified.log`, `artifacts/walk-ui/report.json`
and six inspected images under `artifacts/walk-ui/`. Both 1440×900 and 1050×680
windows were checked. Paused authoritative bytes were unchanged. The live walk
crossed **28 busy-worker frames**. The final preview's GPU guard reached **61 C**,
below the unchanged 75 C cutoff (`artifacts/walk-ui-final-guard.jsonl`). This is
a short functional/render check, not a thermal soak or a performance claim.

The full `tools/check.sh` completed successfully, including 40 engine-check
invocations and the native checks; final output is in
`artifacts/walk-full-check.log`; all 40 sequential successful exits were reread in
`artifacts/walk-suite-proof.json`. Source diff whitespace check also passed.
The user's application was not restarted; changes take effect on next launch.

Rollback source copies are outside the project at
`/run/media/pavel/Storage/tmp/forest-walk-20261104/before/`; the existing unrelated
dirty-tree diff is retained beside them. No duplicate class scripts were put
inside the Redot project.
