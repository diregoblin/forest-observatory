extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config: ForestSettings = load("res://data/forest.tres")
	var report := {"passed": false, "woody_species": 0, "species": []}
	for definition in config.plants:
		print("CANOPY_SPECIES ", definition.species_id, " mask=", definition.canopy_texture)
		definition.validate()
		if definition.canopy_layers == 0:
			continue
		report.woody_species += 1
		var before := []
		for module in definition.modules:
			before.append(var_to_bytes(module.mesh.surface_get_arrays(0)))
		var mesh := ForestPlantMeshBuilder.build(definition)
		var source_bytes: PackedByteArray = (
			definition.canopy_texture.get_image().get_data().duplicate()
		)
		var original_hash := ForestPlantMeshBuilder.visual_hash(definition, mesh)
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/foliage.gdshader")
		ForestPlantMeshBuilder.set_canopy_material(definition, material)
		assert(definition.canopy_texture.get_image().get_data() == source_bytes)
		assert(ForestPlantMeshBuilder.visual_hash(definition, mesh) == original_hash)
		var mid := ForestPlantMeshBuilder.build(definition, true)
		assert(mid.get_faces().size() < mesh.get_faces().size())
		assert(
			(
				var_to_bytes(mesh.surface_get_arrays(0))
				== var_to_bytes(ForestPlantMeshBuilder.build(definition).surface_get_arrays(0))
			)
		)
		for i in definition.modules.size():
			assert(before[i] == var_to_bytes(definition.modules[i].mesh.surface_get_arrays(0)))
		var copy: ForestPlantDefinition = definition.duplicate()
		copy.species_id = &"unknown_third_species"
		assert(
			(
				var_to_bytes(mesh.surface_get_arrays(0))
				== var_to_bytes(ForestPlantMeshBuilder.build(copy).surface_get_arrays(0))
			)
		)
		var arrays := mesh.surface_get_arrays(0)
		var shell_vertices := 0
		var wood_vertices := 0
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			assert(arrays[Mesh.ARRAY_VERTEX][i].is_finite())
			assert(arrays[Mesh.ARRAY_NORMAL][i].is_finite())
			if arrays[Mesh.ARRAY_TEX_UV][i].y > .5:
				shell_vertices += 1
				assert(arrays[Mesh.ARRAY_COLOR][i].a < .5)
			elif arrays[Mesh.ARRAY_COLOR][i].a > .5:
				wood_vertices += 1
		assert(shell_vertices > 0 and wood_vertices > 0)
		var solid := false
		var clear := false
		for y in range(0, 512, 16):
			for x in range(0, 512, 16):
				var uv := Vector2((x + .5) / 512.0, (y + .5) / 512.0)
				var hit := ForestPlantMeshBuilder.mask_hit(definition, uv)
				assert(hit == ForestPlantMeshBuilder.mask_hit(definition, uv + Vector2(1, 1)))
				# A triangle at z=0, constant UV: prove the observer rejects a
				# known-transparent mask but accepts a solid one through the same path.
				if (hit and not solid) or (not hit and not clear):
					var shape := {
						"transform": Transform3D.IDENTITY,
						"bounds": AABB(Vector3(-1, -1, -.01), Vector3(2, 2, .02)),
						"faces":
						PackedVector3Array(
							[Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(0, 1, 0)]
						),
						"uvs":
						PackedVector3Array(
							[Vector3(uv.x, uv.y, 1), Vector3(uv.x, uv.y, 1), Vector3(uv.x, uv.y, 1)]
						),
						"accept_triangle_hit":
						func(coords: Vector2, shell: bool):
							# A triangle at z=0, constant UV: prove the observer rejects a
							# known-transparent mask but accepts a solid one through the same path.

							return not shell or ForestPlantMeshBuilder.mask_hit(definition, coords)
					}
					var distance := ForestObservation._shape_distance(
						shape, Vector3(0, 0, 1), Vector3.FORWARD, 10
					)
					assert((distance >= 0) == hit)
				if hit:
					solid = true
				else:
					clear = true
		assert(solid and clear)
		report.species.append(
			{
				"id": definition.species_id,
				"triangles": mesh.get_faces().size() / 3,
				"mid_triangles": mid.get_faces().size() / 3
			}
		)
	assert(report.woody_species == 20)
	report.passed = true
	FileAccess.open("res://artifacts/canopy-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("CANOPY_CHECK ", JSON.stringify(report))
	quit()
