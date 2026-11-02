extends "res://tools/preview_ground_turf.gd"


func _initialize() -> void:
	output = "res://artifacts/terrain-upgrade/" + OS.get_environment("FOREST_TERRAIN_CASE")
	super._initialize()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene._finish_model_work(true)
	scene.capture_step = 8
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.turf_cards.set_process(false)
	scene.hud.visible = false
	Engine.max_fps = 20
	scene.terrain.advance_ecology_display(1)
	var frozen := model_bytes()
	var heights := []
	for p in [Vector3(200.25, 0, 196.75), Vector3(256.6, 0, 256.4), Vector3(255.75, 0, 200.3)]:
		var height: float = (
			scene.terrain.data.get_surface_height(p)
			if scene.terrain.data.has_method("get_surface_height")
			else scene.terrain.data.get_height(p)
		)
		heights.append(height)
	var climate := ForestClimate.sample(0, 155, 60, 12)
	climate.cloud_cover = .18
	climate.temperature_c = 14.0
	climate.weather_time_s = 0.0
	scene.atmosphere.set_season(climate)
	scene.atmosphere.rain_particles.emitting = false
	scene.terrain.set_surface_season(climate)
	var point := Vector3(200, scene.land.height_at(200, 196), 196)
	for mode in [2, 0]:
		scene.painterly_style.set_mode(mode)
		scene.camera.view(1)
		await photo("valley-%d" % mode, true)
		scene.camera.position = point + Vector3(0, 1.65, 0)
		scene.camera.look_at(point + Vector3(0, 1, -30))
		for i in 18:
			scene.turf_cards._process(0)
		await photo("grass-%d" % mode, true)
	# The same near ground view without geometry hiding the material.
	scene.vegetation.visible = false
	scene.turf_cards.visible = false
	scene.animals_view.visible = false
	scene.habitat_view.visible = false
	scene.fungi_view.visible = false
	scene.camera.position = point + Vector3(0, 1.4, 2.2)
	scene.camera.look_at(point)
	await photo("surface", true)
	scene.terrain.material.set_shader_param("snow_water_m", .03)
	await photo("snow", true)
	scene.terrain.material.set_shader_param("snow_water_m", 0.0)
	var diagnostic := Image.create(2, 2, false, Image.FORMAT_RGB8)
	diagnostic.fill(Color(.2, .45, .8))
	scene.terrain.set_soil_layer(ImageTexture.create_from_image(diagnostic), true)
	await photo("diagnostic", true)
	assert(model_bytes() == frozen)
	FileAccess.open(output.path_join("models.bin"), FileAccess.WRITE).store_buffer(frozen)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(frozen)
	var report := {
		"passed": true,
		"surface_heights": heights,
		"model_sha256": digest.finish().hex_encode(),
		"unchanged_models": true,
		"phases": phases,
		"boundary": "Paused presentation comparison, not sustained FPS; no user saves."
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("TERRAIN_UPGRADE ", JSON.stringify(report))
	scene.free()
	quit()
