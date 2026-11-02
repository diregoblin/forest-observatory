extends "res://tools/preview_ground_turf.gd"


func _initialize() -> void:
	output = "res://artifacts/fauna-live"
	super._initialize()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene._finish_model_work(true)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.camera.near = .01
	scene.hud.visible = false
	Engine.max_fps = 20
	var frozen := model_bytes()
	var shown := []
	for species in scene.animals.definitions.size():
		var id := -1
		for i in scene.animals.species.size():
			if scene.animals.species[i] == species and scene.animals.alive[i]:
				id = i
				break
		assert(id >= 0)
		var bounds: AABB = scene.animals_view.display_shape(id).bounds
		var target := bounds.get_center()
		var distance := maxf(.25, bounds.size.length() * 1.6)
		scene.camera.position = target + Vector3(distance * .6, distance * .2, distance)
		scene.camera.look_at(target)
		var name: String = scene.animals.definitions[species].display_name
		await photo("animal-%d" % species, true)
		assert(not scene.animals_view.selection_shape(id).is_empty())
		shown.append({"name": name, "id": id, "bounds": str(bounds)})
	assert(model_bytes() == frozen)
	var report := {
		"passed": true,
		"unchanged_models": true,
		"shown": shown,
		"boundary":
		"Paused real population in the forest, not animal-scale-normalized studio props or an FPS run."
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("FAUNA_LIVE PASS ", JSON.stringify(report))
	scene.free()
	quit()
