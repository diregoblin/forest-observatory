extends SceneTree

## Before/after corner-level check against the saved pre-optimization meshes.
const BASELINE := (
	"/run/media/pavel/Storage/Yandex.Disk/OpenClaw-workspace/"
	+ "output/forest-gpu-guard-20261101/mesh-baseline.bin"
)


func _initialize() -> void:
	var config: ForestSettings = load("res://data/forest.tres")
	var capture := OS.get_cmdline_user_args().has("--capture-baseline")
	var baseline: Dictionary = (
		{} if capture else FileAccess.open(BASELINE, FileAccess.READ).get_var()
	)
	var vertices := 0
	var old_vertices := 0
	var triangles := 0
	for definition in config.plants:
		var mesh := ForestPlantMeshBuilder.build(definition)
		var arrays := mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var corners := indices.size() if not indices.is_empty() else points.size()
		if capture:
			assert(indices.is_empty())
			baseline[definition.species_id] = arrays
			continue
		var before: Array = baseline[definition.species_id]
		assert(not indices.is_empty(), "Every optimized species must be indexed")
		assert(corners == before[Mesh.ARRAY_VERTEX].size())
		var tags := ForestPlantMeshBuilder.triangle_foliage(mesh)
		assert(tags.size() == corners / 3)
		for corner in corners:
			var vertex := indices[corner]
			assert(points[vertex] == before[Mesh.ARRAY_VERTEX][corner])
			assert(
				(
					arrays[Mesh.ARRAY_NORMAL][vertex].distance_to(before[Mesh.ARRAY_NORMAL][corner])
					< .00001
				)
			)
			assert(arrays[Mesh.ARRAY_COLOR][vertex] == before[Mesh.ARRAY_COLOR][corner])
			assert(tags[corner / 3] == (1 if before[Mesh.ARRAY_COLOR][corner].a < .5 else 0))
		vertices += points.size()
		old_vertices += corners
		triangles += corners / 3
	if capture:
		FileAccess.open(BASELINE, FileAccess.WRITE).store_var(baseline)
		print("BASELINE_CAPTURED ", baseline.size())
	else:
		_check_indexed_tag_order()
		_check_spatial_batches(config)
		var report := {
			"passed": true,
			"species": config.plants.size(),
			"unique_vertices": vertices,
			"old_vertices": old_vertices,
			"triangles_unchanged": triangles,
			"corner_positions_normals_colors_and_foliage": true
		}
		report["spatial_batches_shared_mesh_material_bounds_and_model_unchanged"] = true
		(
			FileAccess
			. open("res://artifacts/render-geometry-check.json", FileAccess.WRITE)
			. store_string(JSON.stringify(report, "  "))
		)
		print("RENDER_GEOMETRY_CHECK ", JSON.stringify(report))
	quit()


func _check_indexed_tag_order() -> void:
	# Deliberately reversed triangle order rejects the old colors[::3] reader.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[
			Vector3(0, 0, 0),
			Vector3(1, 0, 0),
			Vector3(0, 1, 0),
			Vector3(2, 0, 0),
			Vector3(3, 0, 0),
			Vector3(2, 1, 0)
		]
	)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(
		[
			Color(1, 1, 1, 1),
			Color(1, 1, 1, 1),
			Color(1, 1, 1, 1),
			Color(1, 1, 1, 0),
			Color(1, 1, 1, 0),
			Color(1, 1, 1, 0)
		]
	)
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([3, 4, 5, 0, 1, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	assert(ForestPlantMeshBuilder.triangle_foliage(mesh) == PackedByteArray([1, 0]))
	assert(PackedByteArray([0, 1]) != ForestPlantMeshBuilder.triangle_foliage(mesh))


func _check_spatial_batches(config: ForestSettings) -> void:
	var settings: ForestSettings = config.duplicate(true)
	settings.tree_attempts = 0
	settings.water_resolution = 4
	settings.headwater_length = settings.extent
	settings.headwater_width = settings.extent
	settings.plants = [config.plants[0].duplicate(true)]
	var land := ForestLandscape.new(settings)
	var water := ForestWatershed.new(land)
	var trees := ForestTrees.new(land)
	trees._append(0, Vector3(64, 0, 64), 1, 10)
	trees._append(0, Vector3(400, 0, 400), 1, 10)
	var before := trees.snapshot()
	var view := ForestVegetation.new()
	view.build(land, water, ForestGroundcover.new(water), trees)
	view.refresh_trees(ForestClimate.sample(0, 200))
	assert(view.tree_groups.size() == 2)
	assert(view.batch_for(0) != view.batch_for(1))
	assert(view.batch_for(0).multimesh.mesh == view.batch_for(1).multimesh.mesh)
	assert(view.batch_for(0).material_override == view.batch_for(1).material_override)
	# Both origin drag and whole-valley bounds would fail this independent check.
	assert(view.batch_bounds[view.member_groups[1]].position.x > 350)
	assert(view.batch_bounds[view.member_groups[1]].position.z > 350)
	assert(view.batch_bounds[view.member_groups[1]].size.x < 100)
	assert(trees.snapshot() == before)
	# Appending in another chunk doesn't replace existing batches or stable slots.
	var first := view.batch_for(0)
	var id := trees._append(0, Vector3(250, 0, 250), .2, 0)
	view.refresh_trees(ForestClimate.sample(0, 200))
	assert(view.tree_groups.size() == 3 and view.batch_for(0) == first)
	assert(view.member_slots[0] == 0 and view.member_slots[id] == 0)
	assert(view.selection_shape(id).bounds == view.batch_bounds[view.member_groups[id]])
	view.free()
