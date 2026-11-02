# Terrain horizon shadows, animal profiles and title pacing — 2026-11-02

## Terrain shadows

The directional light already had shadows enabled, and Terrain3D's default
`cast_shadows` was On. The reproducible problem was **receiver distance**:
shadow coverage ended at 280 m (fade began at 224 m). Standard overview targets
can be farther away. A hill therefore stopped occluding direct sunlight there,
although the same hill occluded it correctly close to the camera.

The atmosphere now receives the configured world extent. Shadow distance is
`max(280, extent * 1.6)`: **819.2 m** for this 512 m world, with fade starting at
90%. Cascades end at **28 / 84 / 280 / 819.2 m**. The first cascade keeps its
previous 28 m footprint instead of expanding all near-shadow texels along with
the far plane. Terrain casts double-sided shadows as a solid heightfield.
Bias, normal bias, shadow atlas size and default 20 m pancake are unchanged.
No synthetic global sunlight dimmer, terrain-ray march or new shadow mesh added.
Below the astronomical horizon the existing solar energy already clamps to 0;
that law and all model lighting/physiology are unchanged.

Primary API reference:
[DirectionalLight3D](https://docs.godotengine.org/en/stable/classes/class_directionallight3d.html).
Actual defaults and behavior were checked on Redot 26.3 + Terrain3D 1.1.0, not
inferred from those docs. Increasing shadow range includes more casters and can
cost GPU time; **no FPS gain or precise cost was measured**. Far shadow detail
is intentionally coarser than nearby foliage shadows. Very high/free-fly views
beyond the configured finite range are not promised infinite shadow coverage.

### Actual Forward+ assay

```sh
GPU_GUARD_LOG=artifacts/terrain-shadows-final-guard.jsonl tools/preview_isolated.sh --script res://tools/preview_terrain_shadows.gd
```

Receipt: `artifacts/terrain-shadows/report.json`, log:
`artifacts/terrain-shadows-final.log`.

A white direct-light receiver is placed above the actual heightfield. An
independent 1 m geometric ray along the sun vector establishes whether the
hill blocks the receiver, without using a shadow map. Ambient/sky/fog are
removed for this assay; solar energy is held fixed so this measures occlusion,
not the natural dusk dimming curve. Morning/evening directions are 5° above
the astronomical horizon; the unoccluded midday control is at 60°.

| Receiver / sun | Old mean RGB | Corrected | Terrain casting disabled |
|---|---:|---:|---:|
| Near / morning | 0 | 0 | 0.619608 |
| Near / evening | 0 | 0 | 0.619608 |
| Far (~386 m) / morning | 0.619608 | 0 | 0.619608 |
| Far (~386 m) / evening | 0.619608 | 0 | 0.619608 |
| Near / midday | 0.887582 | 0.887582 | 0.887582 |
| Far / midday | 0.884967 | 0.884967 | 0.884967 |

This rejects both the old distant leak and the wrong fix of darkening every
receiver. Same-camera populated forest pairs were inspected at morning,
evening and midday, with natural solar energy and ambient restored. All model
snapshots remained byte-identical. Full world pictures stay readable in terrain
shadow because ambient light is not removed in production.

Investigation controls outside the project independently varied distance and
split placement (`artifacts/terrain-shadow-far.log`, `terrain-shadow-range.log`):
range alone fixes the distant leak. A zero-pancake variant failed the blocked
near receiver and was rejected; it is not a recommended setting for this scene.

## Animal profiles

The screenshot's three death messages came from one model stage, a duplicate
localized action, and a generic UI suffix. `_die()` already has an alive guard;
this was duplicate presentation, not three biomass/death transfers.

The compact card now has separate identity/age and state lines. Living animals
show stage + action. Dead animals show exactly one gender-correct terminal
status (`Погибла` / `Погиб`); follow is hidden. Expanded dead profiles omit current
action, energy, sleep routine, alarm, food target, expected offspring and home
behavior. Stable identity/age provenance, parents, lifetime hunts, remains and
reference link stay available. Plant/fungus cards keep their own stage format;
the shared UI no longer appends a second death suffix to an already dead stage.

Display labels are additive `inspect()` output only. No snapshot schema,
existing counters, biological state, movement or numerical time step changed.
Reading cards still cannot advance the models.

### Title thresholds: exactly fivefold

| Personal metric | Before | Now |
|---|---:|---:|
| Consumed carbon | 0.75 kg C | 3.75 kg C |
| Travel | 100 m | 500 m |
| Rest | 3 biological days | 15 biological days |
| Observed lifetime | 30 biological days | 150 biological days |

The last description now says 150 biological days, not one month. No bonus,
notification or stat reset was added. Titles are recomputed from existing
personal counters with the new thresholds, including records loaded later.

`check_animals.gd` checks literal requested thresholds, just-below/exact
boundaries, independent personal credits, unchanged behavior/RNG/CNP trajectory,
and now terminal cards for both sexes and absence of live fields after death.
The existing saved-world continuation checks remain required.

```sh
GPU_GUARD_LOG=artifacts/animal-profiles-guard.jsonl tools/preview_isolated.sh --script res://tools/preview_animal_profiles.gd
```

`artifacts/animal-profiles/report.json` passed: actual isolated model deaths,
collapsed and expanded cards for both sexes, living card, and return to a plant
without stale animal controls. Display reads preserve snapshots. Images were
inspected. These are deliberate deaths in a throwaway fixture, not the user's
world; no user saves or already running window were touched.

## Final checks

`tools/check.sh` exited 0: all **37/37** engine checks are fresh and free of
script errors, with native hydrology/fungi/soil checks and the standard native
benchmark also completed. Save/restore, exact continuation, worker boundaries,
selection and controls passed. A final focused `check_animals.gd` run also
passed after tightening the male/female terminal-label assertion.

Both actual Forward+ fixtures passed. GPU guard maximum temperatures were
52 °C for terrain shadows and 54 °C for animal profiles, below the 75 °C limit;
both guarded processes exited 0. `git diff --check` passed. Consolidated local
receipt: `artifacts/shadows-profiles-verification.json`; full suite log:
`artifacts/shadows-profiles-suite.log`.
