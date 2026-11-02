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
- The live scene runs one entire coupled tick on one worker. While it owns the
  models, the main thread uses only submitted display state. Join before model
  reads/mutations (including pause, save/load, controls and picking); no competing
  model writers. The synchronous headless path is the exact reference.
- Keep world dimensions and field resolution in `ForestSettings`. Views use
  the model's cell size and extent; don't silently duplicate grid constants.
- No physics in presentation shaders: they display model fields. A dedicated
  compute backend is allowed after comparison with the native CPU reference;
  it owns model state, not presentation logic. See DEVELOPMENT_PLAN.md.
  On the current CPU path, display-only float64 -> float32 conversion remains
  centralized in `ForestFieldTexture` and never changes authoritative reserves.
- All plant life forms share `ForestTrees`, stable append-only IDs, finite seeds,
  live/dead C/N/P and one `harvest`/`inspect` interface. Groundcover is derived,
  never an independent food reserve. Animals use resource definitions as well.
- `ForestSoil` is the only soil C/N/P owner. Refinement transfers covered coarse
  reserves into non-overlapping fine patches. Coupled fungal resource/litter
  fields are read-only mirrors and excluded from ecosystem totals; snapshots
  must project the current owner, not stale solver caches.
- Leaf carbon is a subset of live plant carbon; fresh surface carbon is a subset
  of soil organic carbon. Neither is added again to ecosystem totals. Leaf fall
  transfers existing C/N/P locally, including at domain edges. ECM exchange pays
  actual host carbon for finite local nutrients; AM/ericoid traits are not yet
  implemented channels. Soil shaders only read snapshots, never invent stocks.
- Picking uses one observer and the view's last submitted geometry, not future
  model transforms. Whole-world load validates scene/cross-model contracts and
  restores participants transactionally in dependency order.
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

GPU safety (Pavel, 2026-11-01): launch experiments through `tools/run.sh` or
`python3 tools/gpu_guard.py -- COMMAND ...`, never the unguarded engine.
The watchdog refuses a hot/missing GPU and stops its process group at **>=75 C**
or the first invalid/missing telemetry sample. Pavel explicitly revised the
previous 70 C ceiling to 75 C; never raise/disable the current ceiling.
Do not repeat the failed thermal soak; use saved foreground telemetry and a
CPU/headless geometry audit first. No driver/power/fan changes are authorized.

Run `tools/check.sh` after changing a model/interface. For presentation changes,
run an actual Forward+ preview and inspect saved images. See README.md.
`tools/check_contracts.gd` covers adding a third species without code changes,
multiple oriented barriers, model/GPU field conversion, and ecological clock
partitioning. Keep numerical controls in `tools/check_water.gd` meaningful.

- In scripted `.tres` subresources, assign `script` before script-defined fields.
  Check loaded foliage/wood tags, not only the resource source text.
  Avoid standalone `#` comments in these resource files: on Redot 26.3 a
  comment before `canopy_texture` silently left that next property unset.
  Keep explanations in docs and assert the loaded Texture2D is non-null.
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

- Keep rollback copies containing `class_name` scripts outside the Godot project.
  If an in-project fixture directory is unavoidable, create `.gdignore` before
  copying scripts: the editor otherwise registers duplicate global classes.

- Test live presentation across actual busy-worker frames and tick completions,
  not just the synchronous reference. Copy paths/weather only after joining;
  per-frame drawing, picking bounds and camera follow use committed copies.
- Plant UV.x encodes component tags only when `tree_enabled` is true. Generic
  primitives (stones) use ordinary UVs; never run flower/fruit discard on them.
  UV.y=1..2 marks nested canopy shells/depth; UV2 holds fixed leaf-mask UVs.
  Legacy primitive modules reset UV2 and UV.y to zero. Keep picking and atlas baking
  on the same cutout/tag path. Duplicate source Images before generating
  mipmaps: the headless/Dummy renderer can return a shared source Image and
  otherwise invalidate subsequent species' visual hashes. `check_canopy` and
  `check_plant_lod` cover source immutability and all 29 LoDs after a rebuild.

- Grass cards use UV2.x for the crossed-plane index (not the plant canopy
  convention). Fade departing planes before changing a patch's shared mesh.
  Patch LoD uses nearest XZ distance conservatively, not its centre: no visible
  plane may be dropped early. Keep thresholds shared through material params.
  Alpha multiplied by a distance fade still hits a hard alpha-scissor cutoff;
  use stable world-seeded staggered tuft lowering instead of temporal dither.

- Botanical modules are generic shapes (`shoot`, `leaf_card`, `star`, `bell`,
  `spur`, `aggregate`, `panicle`), never species-name branches. UV.y=3 marks
  fixed folded leaf cards, UV2 their cutout coordinates. Unlike nested crown
  shells, they retain a .5 alpha threshold: lowering it at coarse shadow-map
  mips fills the whole rectangle. Picking and atlas baking share that mask.
  Botanical recipe colours are authored in sRGB and converted once at mesh
  emission (vertex COLOR is linear); do not brighten them with a second decode.
  Rebuild colour/normal impostors after geometry, mask or vertex-colour changes.

- Animal shapes are generic closed volumes from resource recipes. `part_pivots`
  are optional anatomical hinges, in the same coordinates as `part_offsets`:
  ear lining/tip, shin/paw and tail tip must share their parent hinge. The first
  `head` part is the skull pivot, not the last muzzle or eye detail. Preserve
  CUSTOM0 tags through indexed merging; CPU picking and the shader deform the
  same geometry. Animal recipe colours are sRGB, decoded once at emission.
  Inherited ear length/angle must transform the whole group about its hinge,
  not elongate each lining/tip independently; `check_fauna_geometry` tests contact.

- Articulated flight uses resource `wing_shoulder` and roles `flight_wing`,
  `flight_tip`, `flight_leg`. CUSTOM0 keeps the wrist/leg hinge; a cached per-body
  shoulder supplies its parent. CPU `deform` and the shader apply wrist, shoulder,
  body pitch in the same order. Blend `flight`/`wrist` on displayed time only;
  keep the blended pose for bounds/picking and never read models in `_animate`.
  Edit `build_animal_motion.py`, regenerate Blender/JSON and the Redot motion
  library together. `check_bird_flight` covers span, wrist attachment and fades.

- Terrain3D 1.1 `get_height()` is a raw vertex lookup. For render-ground
  placement use `get_surface_height()`; `check_terrain_upgrade` rejects the raw
  lookup on a fractional analytical plane. Asset setters are
  `set_texture_asset()` and `set_asset_name()` (the property is still `name`).
  Keep the custom soil shader's MAX_REGIONS consistent with material limits.
  Default tessellation stays 0; the optional bank-quality setting uses level 2
  and the native displacement atlas/geomorph (vertical offset bounded by 4 cm).
  Cache only static world detail in that buffer: Terrain3D refreshes it on camera
  snaps, not arbitrary uniform changes. Apply interpolated water/snow/habitat
  masks live in the vertex shader and derive normals from the same masked field.
  Call public `snap()` when enabling/reconfiguring a stationary buffer. Never
  turn presentation displacement into an authoritative bank, ravine or obstacle.
  Particle grass and static-level ocean remain isolated render studies, not
  established performance improvements or ecological/hydrological replacements.

- Terrain3D `cast_shadows` uses the RenderingServer enum (not the identically
  numbered GeometryInstance3D enum; typed GDScript rejects the latter). Keep
  terrain shadow coverage separate from near-detail coverage: atmosphere gets
  world extent, far shadow distance is extent-derived, first cascade stays 28 m.
  Check low-sun occlusion at near AND distant receivers, plus an unoccluded
  overhead-sun control. Don't darken global sunlight to hide a local shadow gap.

- Low-deck sky and cloud caster share one HDR field (`cloud_deck.gd`), updated
  on submitted weather time or asynchronous noise completion, never camera
  motion. A large shadow-only plane needs subdivisions and sufficient native
  pancake depth; preserve near/far and opaque/no-caster controls. Reset ambient
  after set_season in direct-light assays: that method restores natural ambient.
  Measure the cloud field viewport separately from world/composition GPU times.
  Volumetrics are a switchable coarse native Forward+ effect, on by default;
  suppress them for soil diagnostics without losing the user's preference.
