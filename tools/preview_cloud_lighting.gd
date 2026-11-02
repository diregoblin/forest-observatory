extends "res://tools/preview_ground_turf.gd"

var cloud: MeshInstance3D


func _initialize() -> void:
	output = "res://artifacts/cloud-lighting"
	create_timer(180).timeout.connect(func(): quit(1))
	_run.call_deferred()


func photo_cloud(label: String) -> void:
	scene.painterly_style._process(0)
	await photo(label, true)
	print("CLOUD_FRAME ", label, " ", JSON.stringify(phases[-1]))


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene._finish_model_work(true)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.hud.visible = false
	Engine.max_fps = 30
	assert(scene.atmosphere.volumetric_enabled)
	assert(scene.atmosphere.world_env.volumetric_fog_enabled)
	assert(scene.hud.volumetric_button.button_pressed)
	scene.atmosphere.set_volumetric_enabled(false)
	var frozen := model_bytes()
	var climate := ForestClimate.sample(0, 155, 60, 12)
	climate.cloud_cover = .65
	climate.weather_time_s = 0.0
	climate.sun_elevation = deg_to_rad(38)
	scene.atmosphere.set_season(climate)
	scene.atmosphere.rain_particles.emitting = false
	cloud = scene.atmosphere.cloud_deck
	cloud.submit(climate, scene.atmosphere.sun.global_basis.z)
	cloud.configure_sky(scene.painterly_style.sky_material)
	scene.camera.view(1)
	cloud.visible = false
	await photo_cloud("01-valley-before")
	cloud.visible = true
	await photo_cloud("02-valley-after")
	climate.weather_time_s = 180.0
	scene.atmosphere.set_season(climate)
	await photo_cloud("03-valley-moved")
	var point := Vector3(235, 0, 225)
	point.y = scene.terrain.data.get_surface_height(point)
	scene.camera.position = point + Vector3(0, 1.5, 3)
	scene.camera.look_at(point + Vector3(0, .15, 0))
	for frame in 25:
		await RenderingServer.frame_post_draw
	scene.turf_cards.set_process(false)
	for weight in [0.0, 1.0]:
		scene.turf_cards.material.set_shader_parameter("root_lighting_strength", weight)
		await photo_cloud("04-grass-%d" % int(weight))
	# A real, resource-driven grove; no extra decorative ray occluders.
	var trees: Array[Vector3] = []
	for id in scene.trees.positions.size():
		var definition: ForestPlantDefinition = scene.settings.plants[scene.trees.species[id]]
		if (
			definition.growth_form == &"tree"
			and scene.trees.size[id] * definition.reference_height_m > 6
		):
			trees.append(scene.trees.positions[id])
	var best := -1
	for p in trees:
		var count := 0
		for q in trees:
			if p.distance_squared_to(q) < 400:
				count += 1
		if count > best:
			best = count
			point = p
	climate.cloud_cover = .35
	climate.sun_elevation = deg_to_rad(25)
	scene.atmosphere.set_season(climate)
	scene.atmosphere.set_cloud_shadows_enabled(false)
	var toward_sun: Vector3 = scene.atmosphere.sun.global_basis.z
	toward_sun.y = 0
	toward_sun = toward_sun.normalized()
	scene.camera.position = point - toward_sun * 10
	scene.camera.position.y = scene.terrain.data.get_surface_height(scene.camera.position) + 1.7
	scene.camera.look_at(scene.camera.position + toward_sun * 20 + Vector3.UP * 3)
	scene.atmosphere.set_volumetric_enabled(false)
	await photo_cloud("05-rays-before")
	scene.atmosphere.set_volumetric_enabled(true)
	await photo_cloud("06-coarse-volumetric")
	for step in 3:
		scene.camera.position += scene.camera.basis.x * .06
		await photo_cloud("07-ray-motion-%d" % step)
	var costs := []
	for volumetric in [false, true, false, true]:
		scene.atmosphere.set_volumetric_enabled(volumetric)
		costs.append(await benchmark(climate, volumetric, false))
	scene.atmosphere.set_volumetric_enabled(false)
	scene.camera.view(1)
	for shadows in [false, true, false, true]:
		scene.atmosphere.set_cloud_shadows_enabled(shadows)
		costs.append(await benchmark(climate, false, shadows))
	scene.atmosphere.set_cloud_shadows_enabled(true)
	scene.atmosphere.set_volumetric_enabled(true)
	scene.hud.visible = true
	scene.hud.set_options_open(true)
	for frame in 4:
		await RenderingServer.frame_post_draw
	assert(scene.hud.volumetric_button.button_pressed)
	for button in [
		scene.hud.volumetric_button, scene.hud.cloud_shadows_button, scene.hud.grass_lighting_button
	]:
		await click(button)
		await click(button)
	scene.hud.set_options_open(false)
	scene.hud.visible = false
	assert(scene.atmosphere.world_env.volumetric_fog_enabled)
	assert(scene.atmosphere.cloud_deck.shadows_enabled)
	assert(scene.turf_cards.material.get_shader_parameter("root_lighting_strength") == 1.0)
	scene.atmosphere.set_volumetric_enabled(true)
	scene._toggle_soil_layers()
	assert(not scene.atmosphere.world_env.volumetric_fog_enabled)
	scene._toggle_soil_layers()
	assert(scene.atmosphere.world_env.volumetric_fog_enabled)
	scene.hud.visible = true
	scene.hud.set_options_open(true)
	await photo_cloud("08-options")
	assert(model_bytes() == frozen)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(
			{
				"passed": true,
				"phases": phases,
				"costs": costs,
				"actual_gui_toggles": true,
				"volumetric_default_on": true,
				"diagnostic_suppresses_volume": true,
				"unchanged_models": true
			},
			"  "
		)
	)
	scene.free()
	quit()


func click(button: CheckButton) -> void:
	var before := button.button_pressed
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = root.get_final_transform() * button.get_global_rect().get_center()
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	assert(button.button_pressed != before, "Checkbox must react through the actual GUI input path")
	if button == scene.hud.volumetric_button:
		assert(scene.atmosphere.world_env.volumetric_fog_enabled == button.button_pressed)
	elif button == scene.hud.cloud_shadows_button:
		assert(scene.atmosphere.cloud_deck.shadows_enabled == button.button_pressed)
	else:
		assert(
			(
				scene.turf_cards.material.get_shader_parameter("root_lighting_strength")
				== float(button.button_pressed)
			)
		)


func benchmark(climate: Dictionary, volume: bool, shadows: bool) -> Dictionary:
	var times: Array[float] = []
	var field_times: Array[float] = []
	for frame in 24:
		climate.weather_time_s += 1.0 / 30.0
		scene.atmosphere.set_season(climate)
		scene.painterly_style._process(0)
		await RenderingServer.frame_post_draw
		if frame >= 8:
			var world: float = scene.painterly_style.pixel_renderer.frame_times().gpu_ms
			var field: float = RenderingServer.viewport_get_measured_render_time_gpu(
				cloud.field.get_viewport_rid()
			)
			times.append(world + field)
			field_times.append(field)
	times.sort()
	field_times.sort()
	var result := {
		"volumetric": volume,
		"cloud_shadows": shadows,
		"gpu_ms_median": times[8],
		"field_gpu_ms_median": field_times[8],
		"gpu_ms_min": times[0],
		"gpu_ms_max": times[-1]
	}
	print("CLOUD_COST ", JSON.stringify(result))
	return result
