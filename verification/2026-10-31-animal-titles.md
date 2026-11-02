# Hidden animal distinctions — 2026-10-31

Requested as a small profile-only easter egg. Existing animal model, stable IDs,
observation record/card and world snapshots are reused; no dependency, achievement
manager, popup, bonus, species branch or extra HUD panel was added.

## Rules

Each individual owns four monotone records. Titles are a read-only projection of
them, so history-ring eviction and death do not erase an earned distinction.
Only executed biological actions count, not rendered frames or initial age.

| Title | Personal record threshold |
|---|---|
| Гроза подлеска | Actual harvested food >= 0.75 kg C |
| Ушёл за хлебом | Executed horizontal path >= 100 m |
| Мастер тихого часа | Rest/shelter >= 3 biological days |
| Местная легенда | Alive in the observed simulation >= 30 biological days |

The same rules serve every resource-defined herbivore. The existing profile
shows a quiet gold line only after a distinction is earned, with a short reason
on hover. There is no progress tracker. These are playful scenario thresholds,
not validated biological traits or claims of exceptional field performance.

Animal snapshot v2 saves the personal records. v1 input is migrated in memory
with zero personal records: no retrospective life is fabricated from the initial
age, short event history or population totals. Existing simulation/RNG state is
preserved. User save files were not opened or overwritten during verification.

## Verification

- `./tools/check.sh`: PASS, all twelve report groups. No script errors in the
  checked execution logs. The headless editor import reports engine
  resource-allocation leaks at shutdown; the import check excludes those known
  shutdown diagnostics, not parser/load errors.
- `tools/check_animals.gd`: executed 35-day two-species control; deleting only
  cosmetic records each day leaves every other animal snapshot field and food
  identical. One individual's meals do not grant the other a feeding title.
  Boundary fixtures check each threshold just below/at its value; initial age
  grants no title. Profile reads are inert; selecting a plant clears the line.
- Binary whole-world roundtrip/exact continuation remains covered. Corrupt
  personal records reject atomically, including late-model whole-world rollback.
  v1 animal migration is exercised independently and inside a composed world.
- `./tools/preview_isolated.sh -- --understory-check`: PASS, actual Vulkan
  Forward+ on RTX 3070 Ti. Inspected `artifacts/understory-04-fed-hare.png`:
  the normal unreset 32-tick world earned «Гроза подлеска · Ушёл за хлебом»,
  neatly below the animal name; expanded details remain inside the viewport.
  The existing Terrain3D interpolation deprecation warning remains.
- `gdformat`, `gdlint` on the four changed GDScript files and `git diff --check`:
  PASS.

No running user game, service, engine installation or other project was changed.
An already-running forest needs a restart to load the source change. Only the
isolated renderer and model scenarios were exercised, not physical human input.
