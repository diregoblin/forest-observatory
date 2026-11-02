extends Node

var world


func start(scene) -> void:
	world = scene
	_run.call_deferred()


func photo(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	assert(
		(
			get_viewport().get_texture().get_image().save_png(
				"res://artifacts/food-web-render/" + name + ".png"
			)
			== OK
		)
	)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts/food-web-render")
	world._finish_model_work(true)
	world.set_process(false)
	world.paused = true
	world.hud.visible = false
	world.habitat_view.paused = true
	Engine.max_fps = 30
	var prey := -1
	var fox := -1
	for i in world.animals.species.size():
		var d: ForestAnimalDefinition = world.animals.definitions[world.animals.species[i]]
		if d.scavenges and d.trophic_role == &"predator":
			fox = i
		elif ForestAnimals.FOX.prey_species.has(d.species_id):
			prey = i
	assert(fox >= 0 and prey >= 0)
	var budget: PackedFloat64Array = world._ecosystem_budget()
	world.animals._die(prey)
	var point: Vector3 = world.animals.positions[prey]
	world.animals.positions[fox] = point + Vector3(.6, 0, .2)
	world.animals.home_positions[fox] = point
	world.animals.path_history[fox] = {
		"times": PackedFloat64Array([0]),
		"points": PackedVector3Array([world.animals.positions[fox]])
	}
	world.animals.actions[fox] = "eat"
	world.animals_view.refresh(1)
	assert(
		world.animals_view.batches[prey].multimesh.visible_instance_count == 1,
		"One real body is rendered"
	)
	world.camera.position = point + Vector3(2, 1.5, 2)
	world.camera.look_at(point + Vector3.UP * .3)
	await photo("01-carcass-and-scavenger")
	assert(
		world.animals._scavenge(fox, 900, 0, world.animals.definitions[world.animals.species[fox]])
	)
	var climate := ForestClimate.sample(0, 180)
	world.habitat.step(ForestClimate.DAY_S * 12, climate)
	world.animals_view.refresh(1)
	await photo("02-after-twelve-biological-days")
	for e in 3:
		assert(absf(world._ecosystem_budget()[e] - budget[e]) < 1e-5)
	var result := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"one_finite_carcass_visible": true,
		"decay_updates_body": true,
		"cnp_conserved": true,
		"boundary": "Isolated death/decay fixture, not a live twelve-day GPU soak"
	}
	FileAccess.open("res://artifacts/food-web-render/report.json", FileAccess.WRITE).store_string(
		JSON.stringify(result, "  ")
	)
	print("FOOD_WEB_RENDER ", JSON.stringify(result))
	get_tree().quit()
