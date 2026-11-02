# Current Linux/Redot checkpoint — 2026-10-31

The historical notes below describe earlier presets and runs. Current preset:
9,766 fluid + 11,110 boundary samples, nominal 4 L, radius 2 mm, one step/tick.
Budget is now 40,000 with release-safe count/fit validation. The original main
scene and baked torus SDF are preserved; the old statement that the main scene
has no bake is superseded by the supplied archive.

Boundary motion is rigid and one-way. The owned provider caches static states
and transforms moving samples/velocities on GPU. Drive the vessel before
`sim_step`; call `update_motion(dt)` after externally scripted movement, or use
its earlier-priority physics update. Angular velocity uses world coordinates.
Keep the simulation at unit scale; moving the whole simulation frame is not
implemented as an accelerating reference frame. Changing boundary sample count
requires registration/buffer rebuild at a scene reset. Existing SDF metadata is
prepared on rebuild; moving static SDF nodes during a run is unsupported.

A conservative vessel AABB skips the contact hash walk only for points too far
from all boundary spheres. Bounds track geometry, vessel and simulation transforms.
Unknown providers retain the original walk.

Boundary-only bounds are built for each actual hash bucket, including hash
collisions. Exact ordered-float atomic extrema plus an outward margin permit
contact buckets to be skipped only when none of their spheres can touch. This
adds 32 bytes/hash bucket (1,336,064 bytes at the normal batch).

The 128-entry fluid-neighbor cache has an exact full-walk overflow path.
`tools/benchmark.gd` profiles the real scene; the removed legacy profiler's
`profiler_mode` flag is retained only for source compatibility and has no effect.

Water mode is optional, Forward+ only, using actual GPU positions. High is the
default; L switches quality in the demo without changing the solver. Low quarter-size / High half-size
depth/thickness reconstruction has screen-space limits: visible splat structure,
edge artifacts, approximate transparency ordering, no offscreen reflection,
no foam or separate fluid phase. Visual radius does not change collision radius.

Five single-phase liquids live in `liquids/*.tres`: relative viscosity and
optical tint, common density/gravity/support/pressure. `apply_liquid(profile)`
changes viscosity without resetting state. These are gameplay approximations,
not calibrated continuum materials or coexisting/immiscible phases. Settings
are instance-local; radius changes reset the scene with those local settings.

See [latest update](../../docs/LIQUIDS_AND_PERF_2026-10-31_RU.md) and [current review](../../docs/OPTIMIZATION_2026-10-31_RU.md) and
[root launcher/controls](../../README.md).

---

# Single-step small-room checkpoint

Run `res://scenes/fluid_small_room.tscn` (F6). Original example and verified metric example are preserved. Obsolete meter_room files were removed.

The main scene assigns `res://settings/fluid_small_room.tres` to the simulation; the room reads the same resource. The module has no dependency on this preset. Coefficients are derived in `res://modules/fluid/fluid_settings.gd`. Room dimensions and vessel scale do not depend on particle radius.

For q = radius / 0.1 m (verified metric reference):
- support = 8 * radius;
- number density = 19.53125 / q^3;
- count = round(volume * number density), budget 20000;
- pressure = 128 * q^2;
- viscosity coefficient = 2.5 * user viscosity / q;
- spacing = number_density^(-1/3).

One full SPH step runs per physics tick. No adaptive substeps or new velocity limits. The previous fixed-world-stiffness scheme and its 50 substeps were removed.

In the existing unweighted equations, pressure acceleration scales as pressure/radius, and viscous decay rate as viscosity_coefficient*radius. These new factors preserve the particle-scale force response at the same timestep. The old fixed pressure and inverse-cube viscosity scaling made this response faster at smaller radii.

This is particle-scale similarity, NOT constant continuum material properties under resolution refinement: acoustic speed and effective kinematic viscosity decrease with radius. Gravity remains an independent world acceleration (1 m/s^2 here); room/vessel geometry stays fixed. Full dynamical similarity or stability at arbitrary fill heights/impacts is not claimed.

At 2 mm: 2048 fluid particles, nominal volume 0.8388608 litres, h=0.016 m, density=2441406.25, pressure=0.0512, viscosity coefficient=125 (UI multiplier 1). Boundary radius defaults to fluid radius; sample count follows area / (0.5*pi*boundary_radius^2), producing 11110 vessel samples. Wall inset is a separate geometry setting, 0.0006 m.

Validation:
- coefficient/count assertions pass for 1/2/4 mm (16384/2048/256 particles at the same nominal volume);
- 2048 particles: 60 FPS, one step, no nonfinite values; RMS speed 0.00422 m/s after 14.5 simulation seconds;
- tests/scenes/fluid_small_8000.tscn: 8000 fluid + 11110 boundary samples, one step; average 60 FPS, 1% low 28 FPS, worst frame 37.8 ms in a 10-second editor/debug run with vsync; RMS speed about 0.0099 m/s at 10.5 simulation seconds, no nonfinite values;
- original reference hashes match. Existing integer-division warnings remain.

UI sim_step measures CPU submission/readback, not GPU time. These short drop tests do not prove long-term vessel retention or identical fluid motion. Static mesh collision uses a native editor-baked GPUParticlesCollisionSDF3D texture. Moving small vessels and 1 mm GPU dynamics remain unvalidated.

Initial fluid is a deterministic lattice above the vessel, not a continuous emitter. Count, smoothing, density and pressure UI fields are derived/read-only. Change volume for count; changing Radius regenerates the scene. An assertion rejects combinations above budget. User viscosity is a relative multiplier.


## Static mesh collision (native Godot bake)

1. Open scenes/fluid_small_room.tscn. Put static mesh models under StaticGeometry (nested imported scenes work).
2. Select StaticGeometry/CollisionSDF, open the 3D workspace and click Bake SDF. Save the EXR next to this scene, and save the scene.
3. Repeat the bake after changing static geometry or SDF bounds/resolution/thickness. There is no automatic runtime baking.
4. CollisionSDF must enclose the relevant objects and liquid contacts. Its default volume is 0.25 x 1 x 0.25 m; adjust Size/Position if expanding the room. Its volume may be independent of the simulation room.

Godot bakes visible MeshInstance3D descendants of the SDF node's parent matching Bake Mask. Keep moving meshes and boundary-particle vessels outside StaticGeometry. Correct mesh normals matter. Native Thickness is an inward extrusion measured in voxel widths internally; default 1.0, not a metre-wide fluid clearance. Thin surfaces/detail require sufficient resolution. The default 512 along the longest axis gives approximately 1.95 mm cells for a 1 m volume.

The module samples native distances in metres and accounts for the SDF node's transform and the baked grid's rounded dimensions. The SDF node supports rotation, translation and uniform scale relative to the simulation; its source meshes may have nonuniform scale. Keep the simulation itself at unit scale for metre-based parameters.

Empty Texture means no static-mesh SDF collisions (warning at startup). It never falls back to an old texture. Room walls retain their exact analytic box contacts; the vessel retains boundary-sphere contacts. The empty main scene deliberately has no bake; tests/scenes/static_sdf.tscn contains a separately baked rotated shelf and scaled sphere.

SDF collision sweeps the movement segment to avoid tunneling through thin surfaces. These are collision samples, not extra SPH force steps. There is no speed cap. Pressure, viscosity and one SPH step per physics tick remain unchanged.

The experimental runtime SDF generator was removed; only Godot's native editor bake is used.
