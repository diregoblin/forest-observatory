extends "res://tools/check_animals.gd"

var output := (
	"/run/media/pavel/Storage/Yandex.Disk/OpenClaw-workspace/"
	+ "output/forest-optimization-20261101-v2"
)


func _initialize() -> void:
	create_timer(10).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _run() -> void:
	var capture := OS.get_cmdline_user_args().has("--capture-baseline")
	var baseline := {}
	var path := output.path_join("animal-baseline.bin")
	if not capture:
		baseline = FileAccess.open(path, FileAccess.READ).get_var()
	var meshes := []
	var timings := []
	var before_vertices := 0
	var after_vertices := 0
	for species_name in ["hare", "bank_vole", "fox"]:
		for phenotype in [.1, .9]:
			var chamber_state := chamber()
			var animals: ForestAnimals = chamber_state.animals
			animals.definitions[0] = load("res://data/animals/%s.tres" % species_name).duplicate(
				true
			)
			for key in animals.phenotypes[0]:
				animals.phenotypes[0][key] = phenotype
			animals.yaw[0] = .73
			var frozen := animals.snapshot()
			var view := ForestAnimalsView.new()
			view.transform = Transform3D(Basis(Vector3.UP, .42), Vector3(3, 7, -4))
			view.configure(animals)
			var mesh: ArrayMesh = view.batches[0].multimesh.mesh
			var arrays := mesh.surface_get_arrays(0)
			var key: String = species_name + str(phenotype)
			if capture:
				baseline[key] = arrays
			else:
				var old: Array = baseline[key]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				assert(indices.size() == old[Mesh.ARRAY_VERTEX].size())
				for corner in indices.size():
					var v := indices[corner]
					assert(
						(
							old[Mesh.ARRAY_VERTEX][corner].distance_to(arrays[Mesh.ARRAY_VERTEX][v])
							< .00001
						)
					)
					assert(
						(
							old[Mesh.ARRAY_NORMAL][corner].distance_to(arrays[Mesh.ARRAY_NORMAL][v])
							< .00001
						)
					)
					assert(old[Mesh.ARRAY_COLOR][corner] == arrays[Mesh.ARRAY_COLOR][v])
				before_vertices += old[Mesh.ARRAY_VERTEX].size()
				after_vertices += arrays[Mesh.ARRAY_VERTEX].size()
			var before_mesh := mesh.get_instance_id()
			var start := Time.get_ticks_usec()
			for frame in 300:
				view.refresh()
			if not capture:
				assert(view.last_gpu_writes == 0, "Unchanged display must not dirty the GPU")
			timings.append((Time.get_ticks_usec() - start) / 300.0)
			assert(view.batches[0].multimesh.mesh.get_instance_id() == before_mesh)
			assert(view.selection_shape(0).faces == mesh.get_faces())
			assert(
				(
					view.selection_shape(0).transform.origin.distance_to(
						view.transform * animals.display_position(0)
					)
					< .00001
				)
			)
			assert(animals.snapshot() == frozen)
			if not capture:
				view.transform.origin += Vector3(4, 1, -3)
				view.refresh()
				assert(view.last_gpu_writes == 0)
				assert(
					(
						view.selection_shape(0).transform.origin.distance_to(
							view.transform * animals.display_position(0)
						)
						< .00001
					)
				)
				animals.actions[0] = "sleep"
				view.refresh()
				assert(
					(
						view.last_gpu_writes == 1
						and view.selection_shape(0).bounds.size.y < mesh.get_aabb().size.y
					)
				)
				animals.alive[0] = 0
				view.refresh()
				assert(view.last_gpu_writes == 2, "Death changes pose and color exactly once")
				animals.killed_by[0] = 1
				view.refresh()
				assert(view.last_gpu_writes == 1 and view.selection_shape(0).is_empty())
				animals.alive[0] = frozen.alive[0]
				animals.killed_by[0] = frozen.killed_by[0]
				animals.actions[0] = frozen.actions[0]
				assert(animals.snapshot() == frozen)
				view.rebuild()
				assert(view.last_gpu_writes == 3 and not view.selection_shape(0).is_empty())
			meshes.append(
				{
					"species": species_name,
					"phenotype": phenotype,
					"vertices": arrays[Mesh.ARRAY_VERTEX].size(),
					"faces": mesh.get_faces().size() / 3
				}
			)
			view.free()
	if capture:
		FileAccess.open(path, FileAccess.WRITE).store_var(baseline)
	var report := {
		"passed": true,
		"capture": capture,
		"refresh_usec_each": timings,
		"before_vertices": before_vertices,
		"after_vertices": after_vertices,
		"meshes": meshes
	}
	(
		FileAccess
		. open(
			output.path_join("animal-%s.json" % ("before" if capture else "after")),
			FileAccess.WRITE
		)
		. store_string(JSON.stringify(report, "  "))
	)
	print("ANIMAL_RENDER ", JSON.stringify(report))
	quit()
