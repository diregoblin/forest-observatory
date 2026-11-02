extends "res://tools/preview_ground_turf.gd"


func _initialize() -> void:
	output = "res://artifacts/understory-live"
	super._initialize()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.hud.visible = false
	Engine.max_fps = 15
	var frozen := model_bytes()
	scene.camera.view(2)
	await photo("creek-pixel", true)
	var shown := []
	for name in ["meadowsweet", "balsam", "raspberry", "male_fern", "wood_sorrel"]:
		var chosen := -1
		for i in scene.trees.species.size():
			var definition: ForestPlantDefinition = scene.settings.plants[scene.trees.species[i]]
			if definition.species_id == name and scene.trees.alive[i]:
				if (
					scene.water.depth[scene.water.index_at(
						scene.trees.positions[i].x, scene.trees.positions[i].z
					)]
					< .02
				):
					chosen = i
					break
		assert(chosen >= 0)
		var point: Vector3 = scene.trees.positions[chosen]
		var geometry: Dictionary = scene.vegetation.selection_geometry[scene.trees.species[chosen]]
		var height: float = geometry.bounds.size.y * scene.trees.size[chosen]
		var target := point + Vector3.UP * height * .45
		var distance := clampf(height * 2.3, .45, 3)
		scene.camera.position = target + Vector3(distance * .6, distance * .3, distance)
		scene.camera.look_at(target)
		scene.turf_cards.set_process(true)
		await photo("plant-" + name, true)
		shown.append({"id": chosen, "species": name, "height": height})
	# Presentation palette switches must not invent another world.
	scene.painterly_style.set_mode(1)
	scene.camera.view(2)
	await photo("creek-painterly", true)
	assert(model_bytes() == frozen)
	assert(scene.vegetation.impostor_assets.size() == scene.settings.plants.size())
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(
			{
				"passed": true,
				"unchanged_models": true,
				"renderer": RenderingServer.get_current_rendering_method(),
				"atlas_species": scene.vegetation.impostor_assets.size(),
				"shown": shown,
				"boundary": "Paused real forest, not a performance or aged-ecosystem run."
			},
			"  "
		)
	)
	print("UNDERSTORY_LIVE PASS ", JSON.stringify(shown))
	scene.free()
	quit()
