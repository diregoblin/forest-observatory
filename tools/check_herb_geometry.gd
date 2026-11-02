extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: ForestSettings = load("res://data/forest.tres")
	var records := []
	for definition in settings.plants:
		if not definition.modules.any(func(m): return m.shape != "mesh"):
			continue
		definition.validate()
		var source := []
		for m in definition.modules:
			source.append(var_to_bytes(m.mesh.surface_get_arrays(0)))
		var mesh := ForestPlantMeshBuilder.build(definition)
		var middle := ForestPlantMeshBuilder.build(definition, true)
		assert(middle.get_faces().size() < mesh.get_faces().size())
		var copy: ForestPlantDefinition = definition.duplicate()
		copy.species_id = &"unseen_botanical_species"
		assert(
			(
				var_to_bytes(mesh.surface_get_arrays(0))
				== var_to_bytes(ForestPlantMeshBuilder.build(copy).surface_get_arrays(0))
			)
		)
		var arrays := mesh.surface_get_arrays(0)
		var cards := 0
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			assert(arrays[Mesh.ARRAY_VERTEX][i].is_finite())
			assert(arrays[Mesh.ARRAY_NORMAL][i].is_normalized())
			if arrays[Mesh.ARRAY_TEX_UV][i].y > 2.5:
				cards += 1
				assert(arrays[Mesh.ARRAY_COLOR][i].a < .5)
				assert(
					Rect2(Vector2.ZERO, Vector2.ONE * 1.00001).has_point(
						arrays[Mesh.ARRAY_TEX_UV2][i]
					)
				)
		assert(cards > 0)
		var tags := ForestPlantMeshBuilder.triangle_foliage(mesh)
		assert(tags.has(0) and tags.has(1))
		var uvs := ForestPlantMeshBuilder.triangle_uvs(mesh)
		assert(uvs.size() == mesh.get_faces().size())
		var clear := false
		var solid := false
		for y in range(1, 64, 3):
			for x in range(1, 64, 3):
				var uv := Vector2(x / 64.0, y / 64.0)
				var hit := ForestPlantMeshBuilder.mask_hit(definition, uv)
				clear = clear or not hit
				solid = solid or hit
		assert(clear and solid, "Leaf mask must contain air as well as leaf")
		var bytes_before: PackedByteArray = (
			definition.canopy_texture.get_image().get_data().duplicate()
		)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/foliage.gdshader")
		ForestPlantMeshBuilder.set_canopy_material(definition, mat)
		assert(mat.get_shader_parameter("canopy_enabled") == true)
		assert(definition.canopy_texture.get_image().get_data() == bytes_before)
		for i in definition.modules.size():
			assert(source[i] == var_to_bytes(definition.modules[i].mesh.surface_get_arrays(0)))
		records.append(
			{
				"id": definition.species_id,
				"near_triangles": mesh.get_faces().size() / 3,
				"mid_triangles": middle.get_faces().size() / 3,
				"card_vertices": cards
			}
		)
	assert(records.size() == 10)
	FileAccess.open("res://artifacts/herb-geometry-check.json", FileAccess.WRITE).store_string(
		JSON.stringify({"passed": true, "species": records, "identity_independent": true}, "  ")
	)
	print("HERB_GEOMETRY_CHECK PASS ", JSON.stringify(records))
	quit()
