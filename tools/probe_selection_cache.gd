extends "res://tools/check_animals.gd"


func _run() -> void:
	create_timer(20).timeout.connect(func(): quit(1))
	var legacy := GDScript.new()
	legacy.source_code = (
		FileAccess
		. get_file_as_string(
			"/run/media/pavel/Storage/tmp/forest-surface-hitches-20261101/before/animals_view.gd"
		)
		. replace("class_name ForestAnimalsView\n", "")
	)
	assert(legacy.reload() == OK)
	var rows := []
	for resource in ["hare", "bank_vole", "fox", "boar"]:
		var w := chamber()
		var d: ForestAnimalDefinition = load("res://data/animals/%s.tres" % resource).duplicate(
			true
		)
		d.initial_count = 1
		w.animals = ForestAnimals.new(w.animals.land, w.plants, w.water, w.soil, [d])
		var current := ForestAnimalsView.new()
		var old = legacy.new()
		root.add_child(current)
		root.add_child(old)
		current.configure(w.animals)
		old.configure(w.animals)
		assert(current.selection_shape(0) == old.selection_shape(0))
		var samples := []
		for variant in [old, current, old]:
			var values := []
			for batch in 5:
				var started := Time.get_ticks_usec()
				for call in 12:
					variant.selection_shape(0)
				values.append((Time.get_ticks_usec() - started) / 12.0)
			samples.append(values)
		rows.append({"species": resource, "usec_per_call_ABA": samples})
		current.free()
		old.free()
	var report := {
		"passed": true,
		"rows": rows,
		"same_geometry": true,
		"boundary": "CPU exact posed picking geometry on the same frozen individual; not game FPS"
	}
	FileAccess.open("res://artifacts/selection-cache-ab.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("SELECTION_CACHE_AB ", JSON.stringify(report))
	quit()
