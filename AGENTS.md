# Forest Observatory

This is a standalone Redot + Terrain3D prototype. Do not modify Rust Tide,
engine installations, services, user saves, or other projects for this work.

## Architecture contract

- Preserve the split between models, immutable configuration/resources, views,
  and the composition root. Views may read model state, never advance it.
- Species are data (`data/plants/*.tres`) consumed by one mesh builder and one
  placement pipeline. Never add `if species_id == "birch"` or individual-tree
  exceptions. Add reusable morphological parameters/components instead.
- Hydrological obstacles are arbitrary segments with crest elevations. The
  solver consumes face-crest fields, not scenario-specific dam conditionals.
- All ecology advances on fixed **model** time, not render-frame time. Rendering
  interpolation and wind are presentation only. Seeded generation is local.
- Keep world dimensions and field resolution in `ForestSettings`. Views use
  the model's cell size and extent; don't silently duplicate grid constants.
- No physics in shaders: shaders display model fields. Float64 -> float32
  conversion is centralized in `ForestFieldTexture`.
- Do not call reservoir exchange shallow-water hydrodynamics or Landlab.
  Conservation is a numerical check, not ecological/physical validation.
- Avoid speculative frameworks/ECS and new generic layers without a concrete
  consumer. This is a modular prototype, not an engine rewrite.

## Verification

Run `tools/check.sh` after changing a model/interface. For presentation changes,
run an actual Forward+ preview and inspect saved images. See README.md.
`tools/check_contracts.gd` covers adding a third species without code changes,
multiple oriented barriers, model/GPU field conversion, and ecological clock
partitioning. Keep numerical controls in `tools/check_water.gd` meaningful.

Formatting/lint: optional `.tools-venv/bin/gdformat` and `gdlint`; gdtoolkit 4.x.
Do not format or patch the third-party addon as part of an application change.
