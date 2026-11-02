extends SceneTree


## CPU-only inventory of the actual meshes and initial seeded population.
## No scene, GPU frame, simulation advance, or user save is loaded.
func _initialize() -> void:
	assert(DisplayServer.get_name() == "headless", "Budget audit must be headless")
	var settings: ForestSettings = load("res://data/forest.tres").duplicate(true)
	var land := ForestLandscape.new(settings)
	var trees := ForestTrees.new(land)
	var counts := PackedInt32Array()
	counts.resize(settings.plants.size())
	for species in trees.species:
		counts[species] += 1
	var report := {
		"boundary": "CPU geometry inventory, not a GPU profiler or reconstructed failed world",
		"display": DisplayServer.get_name(),
		"initial_individuals": trees.species.size(),
		"initial_vertices_per_geometry_pass": 0,
		"initial_triangles_per_geometry_pass": 0,
		"indexed_vertices_same_geometry": 0,
		"species": []
	}
	for s in settings.plants.size():
		var definition: ForestPlantDefinition = settings.plants[s]
		var mesh := ForestPlantMeshBuilder.build(definition)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var triangles := (indices.size() if not indices.is_empty() else vertices.size()) / 3
		var surface := SurfaceTool.new()
		surface.create_from(mesh, 0)
		surface.index()
		var indexed := surface.commit()
		var indexed_arrays := indexed.surface_get_arrays(0)
		var unique: PackedVector3Array = indexed_arrays[Mesh.ARRAY_VERTEX]
		var indexed_indices: PackedInt32Array = indexed_arrays[Mesh.ARRAY_INDEX]
		# Compare corners, not only triangle counts. ArrayMesh normal packing can
		# introduce another quantization on re-commit; record it, do not hide it.
		assert(indexed_indices.size() == triangles * 3)
		var position_error := 0.0
		var normal_error := 0.0
		var color_error := 0.0
		for corner in indexed_indices.size():
			var original := corner if indices.is_empty() else indices[corner]
			var replacement := indexed_indices[corner]
			position_error = maxf(
				position_error,
				arrays[Mesh.ARRAY_VERTEX][original].distance_to(
					indexed_arrays[Mesh.ARRAY_VERTEX][replacement]
				)
			)
			normal_error = maxf(
				normal_error,
				arrays[Mesh.ARRAY_NORMAL][original].distance_to(
					indexed_arrays[Mesh.ARRAY_NORMAL][replacement]
				)
			)
			var before: Color = arrays[Mesh.ARRAY_COLOR][original]
			var after: Color = indexed_arrays[Mesh.ARRAY_COLOR][replacement]
			color_error = maxf(
				color_error,
				maxf(
					absf(before.r - after.r),
					maxf(
						absf(before.g - after.g),
						maxf(absf(before.b - after.b), absf(before.a - after.a))
					)
				)
			)
		assert(position_error < .00001 and normal_error < .002 and color_error < .005)
		var item := {
			"id": str(definition.species_id),
			"initial_count": counts[s],
			"vertices_each": vertices.size(),
			"triangles_each": triangles,
			"is_indexed": not indices.is_empty(),
			"indexed_vertices_each": unique.size(),
			"indexing_max_position_error": position_error,
			"indexing_max_normal_error": normal_error,
			"indexing_max_color_error": color_error,
			"initial_vertices": counts[s] * vertices.size(),
			"initial_triangles": counts[s] * triangles
		}
		report.species.append(item)
		report.initial_vertices_per_geometry_pass += item.initial_vertices
		report.initial_triangles_per_geometry_pass += item.initial_triangles
		report.indexed_vertices_same_geometry += counts[s] * unique.size()
	report.species.sort_custom(func(a, b): return a.initial_vertices > b.initial_vertices)
	var path := "res://artifacts/render-budget.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--budget-output="):
			path = arg.trim_prefix("--budget-output=")
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("RENDER_BUDGET ", JSON.stringify(report))
	quit()
