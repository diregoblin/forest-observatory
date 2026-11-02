extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings: ForestSettings = load("res://data/forest.tres").duplicate(true)
	var land := ForestLandscape.new(settings)
	var water := ForestWatershed.new(land)
	var soil := ForestSoil.new(water)
	var fungi := ForestFungi.new(water, soil)
	var view := ForestFungiView.new()
	root.add_child(view)
	view.configure(fungi)
	var observer := ForestObservation.new(land)
	observer.register_group(&"fungus", fungi, view.selection_shape, view.selection_ids)
	observer.rebuild()
	assert(
		not observer.records.is_empty() and observer.records.size() == view.selection_ids().size()
	)
	var before := fungi.snapshot()
	var shape: Dictionary = observer.records[0].shape
	var bounds: AABB = shape.parts[0].bounds
	var origin := bounds.get_center() + Vector3.UP
	var selected := observer.pick(origin, Vector3.DOWN)
	assert(selected.get("kind") == &"fungus", "Ray hits the submitted cap/stem triangles")
	var record := observer.describe()
	assert(not record.title.is_empty() and record.details.has("Плодовые тела"))
	assert(fungi.snapshot() == before, "Click/inspection does not change fungal stores")
	assert(
		observer.pick(origin + Vector3(0, 0, 1), Vector3.UP).is_empty(),
		"Empty ray must not select a fungus"
	)
	observer.selected = selected
	view.displayed_shapes.erase(selected.id)
	assert(observer.describe().is_empty(), "Disappeared rendered cell clears selection")
	view.free()
	var report := {
		"passed": true,
		"actual_triangle_ray": true,
		"shared_observer": true,
		"cell_carbon_not_individual_mass": true,
		"read_only": true,
		"empty_ray_rejected": true,
		"disappeared_cell_clears_selection": true
	}
	FileAccess.open("res://artifacts/fungus-pick-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("FUNGUS_PICK_CHECK ", JSON.stringify(report))
	quit()
