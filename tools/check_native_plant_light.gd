extends SceneTree

const ANIMAL_DEFINITION = preload("res://scripts/animal_definition.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var native = ClassDB.instantiate(&"ForestPlantLightNative")
	assert(native != null)
	# Independent definition check: a live taller crown shades the lower plant;
	# a dead crown must not. A constant/full-light implementation fails this case.
	var pair: Dictionary = native.compute(
		PackedInt32Array([0, 0]),
		PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
		PackedFloat64Array([2, 1]),
		PackedByteArray([1, 1]),
		PackedFloat64Array([1]),
		PackedFloat64Array([1])
	)
	assert(pair.light[0] == 1.0 and pair.light[1] == exp(-PI * 4 / 256.0))
	pair = native.compute(
		PackedInt32Array([0, 0]),
		PackedVector3Array([Vector3.ZERO, Vector3.ZERO]),
		PackedFloat64Array([2, 1]),
		PackedByteArray([0, 1]),
		PackedFloat64Array([1]),
		PackedFloat64Array([1])
	)
	assert(pair.light[1] == 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8173
	var cases := 0
	for count in [0, 1, 15, 16, 17, 127, 4096]:
		var species := PackedInt32Array()
		var points := PackedVector3Array()
		var sizes := PackedFloat64Array()
		var alive := PackedByteArray()
		var heights := PackedFloat64Array([1, 5, 15])
		var crowns := PackedFloat64Array([.12, 1.3, 3.1])
		for tie in [false, true]:
			species.clear()
			points.clear()
			sizes.clear()
			alive.clear()
			for i in count:
				species.append(0 if tie else i % 3)
				points.append(
					(
						Vector3.ZERO
						if tie
						else Vector3(rng.randf_range(-64, 64), 0, rng.randf_range(-64, 64))
					)
				)
				sizes.append(1 if tie else rng.randf_range(0, 4))
				alive.append(int(i % 7 != 0))
			var expected := reference(species, points, sizes, alive, heights, crowns)
			var actual: Dictionary = native.compute(species, points, sizes, alive, heights, crowns)
			assert(actual == expected, "Exact numerical/tie-order equivalence")
			cases += 1
	# Read-only computation on the actual default forest, without advancing it.
	var scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	var trees = scene.trees
	var heights := PackedFloat64Array()
	var crowns := PackedFloat64Array()
	for d in scene.settings.plants:
		heights.append(d.reference_height_m)
		crowns.append(d.crown_radius_m)
	trees._update_light_reference()
	var frozen: Dictionary = trees.snapshot()
	var actual: Dictionary = native.compute(
		trees.species, trees.positions, trees.size, trees.alive, heights, crowns
	)
	assert(actual.light == trees.light and actual.columns == trees._column_cover)
	assert(trees.snapshot() == frozen, "Read-only light calculation on unchanged input")
	var bad: PackedInt32Array = trees.species.duplicate()
	bad[0] = heights.size()
	assert(
		native.compute(bad, trees.positions, trees.size, trees.alive, heights, crowns).is_empty()
	)
	assert(
		(
			native
			. compute(trees.species, PackedVector3Array(), trees.size, trees.alive, heights, crowns)
			. is_empty()
		)
	)
	var invalid: PackedFloat64Array = heights.duplicate()
	invalid[0] = NAN
	assert(
		(
			native
			. compute(trees.species, trees.positions, trees.size, trees.alive, invalid, crowns)
			. is_empty()
		)
	)
	var report := {
		"passed": true, "synthetic_cases": cases, "real_plants": trees.species.size(), "exact": true
	}
	FileAccess.open("res://artifacts/native-plant-light-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("NATIVE_PLANT_LIGHT ", JSON.stringify(report))
	scene.free()
	quit()


func reference(
	species: PackedInt32Array,
	points: PackedVector3Array,
	sizes: PackedFloat64Array,
	alive: PackedByteArray,
	heights: PackedFloat64Array,
	crowns: PackedFloat64Array
) -> Dictionary:
	var columns := {}
	var actual_heights := PackedFloat64Array()
	var light := PackedFloat64Array()
	light.resize(species.size())
	for i in species.size():
		actual_heights.append(sizes[i] * heights[species[i]])
		var cell := Vector2i(int(points[i].x / 16), int(points[i].z / 16))
		if not columns.has(cell):
			columns[cell] = []
		columns[cell].append(i)
	var cover_by_column := {}
	for key in columns:
		var column: Array = columns[key]
		column.sort_custom(func(a: int, b: int): return actual_heights[a] > actual_heights[b])
		var cover := 0.0
		for i in column:
			light[i] = exp(-cover)
			if alive[i]:
				cover += PI * pow(crowns[species[i]] * sizes[i], 2) / 256.0
		cover_by_column[key] = cover
	return {"light": light, "columns": cover_by_column}
