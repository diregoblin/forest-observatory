extends "res://modules/fluid/fluid_simulation.gd"

## Laboratory adapter for the unchanged Night Shift GPU solver. The four-layer
## slab is independent of ForestWatershed; there is no mass/terrain coupling yet.
## Unit scale, SI lengths; source pressure scaling is particle-scale similarity,
## not calibrated continuum water under refinement.
func set_particles() -> void:
	positions.clear()
	var gap: float = derived.spacing
	var columns := ceili(sqrt(float(count) / 4.0))
	var rows_z := ceili(float(count) / (4 * columns))
	var origin := Vector3(
		(length - columns * gap) / 2 + gap / 2,
		radius + .18,
		(width - rows_z * gap) / 2 + gap / 2
	)
	for i in count:
		var p := origin + Vector3(i % columns, i / (columns * rows_z), (i / columns) % rows_z) * gap
		positions.append(Vector4(p.x, p.y, p.z, 0))
	rebuild_buffers()
	# Upstream's small-vessel scene assumes an untranslated MultiMesh. Our patch
	# has a forest-world translation, while its culling box remains local.
	var particles := %MultiMeshInstance3D as MultiMeshInstance3D
	particles.multimesh.custom_aabb = AABB(Vector3.ZERO, settings.room_size)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Visualization only. Water mode hides this mesh and consumes the position RID.
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = 2 * radius
	sphere.radial_segments = 6
	sphere.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.14, .52, .61)
	material.roughness = .22
	sphere.material = material
	particles.multimesh.mesh = sphere
