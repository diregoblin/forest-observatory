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
- No physics in presentation shaders: they display model fields. A dedicated
  compute backend is allowed after comparison with the native CPU reference;
  it owns model state, not presentation logic. See DEVELOPMENT_PLAN.md.
  On the current CPU path, display-only float64 -> float32 conversion remains
  centralized in `ForestFieldTexture` and never changes authoritative reserves.
- Fungal plots are isolated reflecting domains, not camera-triggered tiles.
  Preserve the distinction between source biomass/resource kinetics and our
  finite-organic/fruiting extensions. Grid step resolves colony fronts, not caps.
  Carbon stores are kg C/m²; representative bodies/clumps never own or spend mass.
  Fungi use the ecosystem clock and read hydrological forcing without changing it.
- Current native water is a local-inertial approximation with a declared
  Froude limiter and bucket soil, not full shallow-water equations or an exact
  Landlab port. Conservation is a numerical check, not physical validation.
- Avoid speculative frameworks/ECS and new generic layers without a concrete
  consumer. This is a modular prototype, not an engine rewrite.

## Verification

Run `tools/check.sh` after changing a model/interface. For presentation changes,
run an actual Forward+ preview and inspect saved images. See README.md.
`tools/check_contracts.gd` covers adding a third species without code changes,
multiple oriented barriers, model/GPU field conversion, and ecological clock
partitioning. Keep numerical controls in `tools/check_water.gd` meaningful.

- In scripted `.tres` subresources, assign `script` before script-defined fields.
  Check loaded foliage/wood tags, not only the resource source text.
- Capture screenshots after `RenderingServer.frame_post_draw`; a forced draw can
  still return the previous frame. Verify the date/preview label in seasonal PNGs.
- Seasonal preview is read-only and paused, never a shortcut for advancing water
  or tree age. The shared driving clock (including pending fixed-step time),
  tree biology and hydrology/evaporation forcing must survive continuation.
- Water stays in SI; solar and biological seconds are configurable multiples
  of completed water seconds (`day_speed_multiplier`, `year_speed_multiplier`).
  UI speed scales water, sun, calendar, trees and fungi together. Complete each
  shared fixed tick before starting another; overload cannot separate clocks.
  The shared tick is at most `water_step`; native CFL may subdivide further.
  Presentation interpolates that clock without advancing it. A speed change
  may cancel excess requested debt, never rewind the displayed solar phase.
  Transpiration uses elapsed water seconds, age/growth/stress use biological
  seconds. This is intentional timescale separation, not an annual watershed claim.

Formatting/lint: optional `.tools-venv/bin/gdformat` and `gdlint`; gdtoolkit 4.x.
Do not format or patch the third-party addon as part of an application change.
