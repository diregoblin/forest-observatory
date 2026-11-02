extends SceneTree

var output := (
	"/run/media/pavel/Storage/Yandex.Disk/OpenClaw-workspace/"
	+ "output/forest-optimization-20261101-v2"
)


func _initialize() -> void:
	var capture := OS.get_cmdline_user_args().has("--capture-baseline")
	var path := output.path_join("fungus-baseline.bin")
	var baseline: Dictionary = {} if capture else FileAccess.open(path, FileAccess.READ).get_var()
	var view := ForestFungiView.new()
	var rows := []
	for name in ["fairy_ring", "boletus_edulis", "chanterelle"]:
		var definition: ForestFungusDefinition = load("res://data/fungi/%s.tres" % name)
		var batch := view._make_batch(definition)
		var arrays := batch.multimesh.mesh.surface_get_arrays(0)
		if capture:
			baseline[name] = arrays
		else:
			var old: Array = baseline[name]
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
		assert(view.mesh_faces.back() == batch.multimesh.mesh.get_faces())
		rows.append(
			{
				"species": name,
				"vertices": arrays[Mesh.ARRAY_VERTEX].size(),
				"triangles": batch.multimesh.mesh.get_faces().size() / 3
			}
		)
	if capture:
		FileAccess.open(path, FileAccess.WRITE).store_var(baseline)
	view.bodies.free()
	view.free()
	(
		FileAccess
		. open(
			output.path_join("fungi-%s.json" % ("before" if capture else "after")), FileAccess.WRITE
		)
		. store_string(JSON.stringify(rows, "  "))
	)
	print("FUNGUS_GEOMETRY passed ", JSON.stringify(rows))
	quit()
