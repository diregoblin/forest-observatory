# Living understory, shared soil and first hare — 2026-10-31

## Delivered slice

Nine resource-defined plant species share `ForestTrees`, `ForestPlantMeshBuilder`
and species MultiMeshes. Trees, shrubs, dwarf shrubs, annual/perennial herbs and
grass use the same age/stress/growth/seed/harvest/inspection path. Stable IDs are
append-only, including recruits. Anonymous independently growing decorative grass
was removed; `ForestGroundcover` derives occupancy and owns no food or biological clock.
Species morphology/life forms are described in `docs/species.md`; numeric traits
are scenario coefficients, not measurements.

`ForestSoilNative` is the only owner of soil organic/labile/mineral C/N/P amounts.
The 128×128 base grid is 4 m; three 128×128 fine patches are 0.25 m. Refinement
transfers covered reserves/area, rejects overlaps, never counts the same soil twice.
Plants take mineral N/P; fungi use the shared fine-cell substrates. Fungal
resource/litter arrays are read-only projections, excluded from fungal totals.
Snapshots project the current soil owner even after a later animal deposit;
reading a snapshot does not advance or synchronize solver caches.

Plants retain finite C/N/P in live biomass, dead biomass and seeds. Dead biomass
transfers gradually into organic soil, with configurable decay and environmental
forcing. Annuals die at their common phenological season end; finite seed banks
persist through winter and create new spring IDs, never revive a dead mother.

One resource-defined hare senses locally, consumes actual `harvest` returns,
spends energy, rests/seeks cover, avoids deep water and returns excretion/carcass
once. A minimum edible-stock trait prevents endless nibbling of near-zero food;
ignored remnants stay in plants. Presentation interpolates executed, bounded
waypoints rather than inventing movement or advancing the model.

LMB/free cursor: shared observer/card for a plant or animal. Candidates use a
spatial grid; exact grid traversal and closest mesh triangles (not only AABBs)
respect terrain occlusion. Geometry comes from the view's submitted state, not a
not-yet-shown model update. Right-click flight and normal HUD input remain.

F5/F9: versioned full-world checkpoint in `user://observatory-world-v1.bin`:
water, soil, plants/seeds/dead pools, fungi, animals, RNG, clock/debt, camera and
selection. Configuration, metadata, clocks and patch geometry are checked;
participant failure rolls earlier models back in dependency order. A same-filesystem
staging rename preserves the previous file on a failed write. No existing user
save was loaded, replaced or migrated by verification.

## Checks performed

`./tools/check.sh`: **PASS**. Native build and all twelve report groups passed:

| Report | Evidence |
|---|---|
| native-check | 120 hydrology assertions; deliberate wrong-water case rejected |
| water-check | water balance/save continuation, retained/released barriers, dry-weather returnflow |
| fungi-native-check | legacy spatial/step controls; closed C error 4.83e-13 kg |
| soil-native-check | conservative refinement, overlap rejection, coupled CNP closure, nutrient null |
| contracts | nine loaded species meshes with stem/foliage tags, data-only extra species, oriented barriers, GPU conversion, real shared-clock partitioning, derived cover |
| ecology-check | water/light/stress/growth, common clock, solar interpolation and exact continuation |
| fungi-check | exact continuation, dry fruiting null, read-only view, invalid save rejection |
| understory-check | 366 controlled recruits, finite seeds, zero-nutrient/nulls, harvest, deadwood, annual summer→autumn→winter→spring plus no-seed control, exact recruited-world continuation, late-soil-deposit snapshot |
| animals-check | real depletion, hunger/death, CNP ledger, one-shot carcass, local sensing/flood blocking, bounded production-tick waypoints, exact continuation, corrupt saves, data-only second species, near-empty food threshold |
| observation-check | independent ray fixtures: nearest triangle, holes inside AABB, terrain occlusion, low 10 cm plant, corner-crossed bin, stable group/ID and transactional registry |
| world-check + controls | composed binary roundtrip/exact continuation; late-model rollback; invalid camera/selection/clock/moved-patch rejection; injected N detected; pause/speed/season contracts |

After adding the multi-day composed budget control, targeted `--check-world`
passed again: 33 production ticks, errors C = -1.59023e-7 kg,
N = -4.94765e-10 kg, P = -5.36602e-11 kg. The admitted audit tolerance is 1e-4 kg;
this is an accounting check, not a precision or physical-validation claim.
Command: `./tools/run.sh --headless -- --check-world`.

Scarce shared-fine-cell assay: production biological step 0.3041667 d,
18.25 d duration. Reversing plant/fungal order changed combined living C by
1.23921e-6 relative; halving step changed it by 1.12858e-5. Focal plant C changed
6.40398e-6 kg on reversal. This bounds this one assay only; between-guild exchange
is still operator-split, not a simultaneous universal fair allocator.

### Real renderer / interaction

`./tools/preview_isolated.sh -- --understory-check`: **PASS**, actual Redot 26.3
Vulkan Forward+ on RTX 3070 Ti, isolated Xvfb, 1440×900. Synthetic mouse events
went through Redot's input/GUI/unhandled-input path and selected a visible hare,
shrub and annual plant. Frames captured after `frame_post_draw` were inspected:

- `artifacts/understory-01-hare.png`
- `artifacts/understory-02-shrub.png`
- `artifacts/understory-03-herb.png`
- `artifacts/understory-04-fed-hare.png` (expanded dynamic state)
- `artifacts/understory-05-valley.png`

The control panel, all observation buttons and F5/F9 fit above the footer;
the card replaces the notes region. The 32-tick rendered scenario uses the real
unreset world; hare survives, consumes 0.989908 kg C and moves 130.141 m.
This is engine-event validation, not physical human mouse/keyboard use.

`./tools/preview_isolated.sh --script res://tools/check_observation.gd`: **PASS**
for actual submitted MultiMesh transforms/bounds/leaves, cached until refresh,
new-recruit membership, and world-space hare bounds. Report preserved as
`artifacts/observation-render-check.json`. Headless Dummy getters do not retain
submitted MultiMesh buffers, so this specific check is explicitly skipped there,
not falsely passed. Analytical observer checks still run headless.

Optional shipped-seed scenario: `./tools/run.sh --headless --script
res://tools/check_observation.gd -- --hare-scenario`, 66 complete coupled ticks,
20.075 biological days, no resets or food replenishment. Hare alive, consumed
1.768607 kg C, moved 146.989 m, energy 21841 kJ; observed eat, seek_food, rest,
seek_cover and shelter. Daily series: `artifacts/hare-scenario-check.json`.
This is one seed, not long-term population viability.

Formatting and gdlint of touched models/views/tests: PASS; `git diff --check`: PASS.
The existing Terrain3D interpolation-deprecation warning remains. No script errors
were accepted as successful checks (Redot can otherwise exit 0 after an assertion).

## Deliberate limits

- Numeric ecology/stoichiometry, initial ages, body CNP and movement rates are
  declared scenario assumptions, not calibrated field physiology/demography.
- Water remains SI; age/growth/soil/fungi/animals use multiplied biological time.
  The common driving clock is preserved, not a physically consistent annual water cycle.
- Between guilds exchange is sequential. Fine fungal domains retain reflecting
  boundaries; there is no whole-forest fine-grid colonization or mycorrhiza model.
- Seasonal leaf appearance is not a separate conserved leaf pool/annual leaf-litter
  flux yet. Organics currently receive dead biomass, decayed seeds and animal returns.
- Clonal shoot ages, separate raspberry canes, root architecture, animal reproduction,
  predation, seasonal coat animation and multi-seed long-term viability are not implemented.
- Live/selected/view geometry is the common low-poly representation, not exact
  wind-deformed/partially-dithered fragment picking.

No engine installation, service, Rust Tide or running user game was modified.
The source and new native library are installed in the main project; an already
running instance must be restarted to load them.
