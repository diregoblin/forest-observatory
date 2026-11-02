extends "res://tools/preview_ground_turf.gd"

var shots := []


func _initialize() -> void:
	output = "res://artifacts/bank-relief"
	create_timer(100).timeout.connect(func(): quit(1))
	_run.call_deferred()


func capture(label: String) -> Image:
	scene.painterly_style._process(0)
	# No snap here: water/snow/diagnostic tests MUST work with a stationary cache.
	for frame in 7:
		await RenderingServer.frame_post_draw
	var times := []
	for frame in 8:
		await RenderingServer.frame_post_draw
		times.append(scene.painterly_style.pixel_renderer.frame_times().gpu_ms)
	var result := root.get_texture().get_image()
	assert(result.save_png(output.path_join(label + ".png")) == OK)
	times.sort()
	shots.append({"label": label, "gpu_ms_p50": times[times.size() / 2],
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
	return result


func flat_field(value: float) -> ImageTexture:
	var field := Image.create(2, 2, false, Image.FORMAT_RF)
	field.fill(Color(value, 0, 0))
	return ImageTexture.create_from_image(field)


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
	var climate := ForestClimate.sample(0, 155, 60, 12)
	climate.cloud_cover = .18
	climate.temperature_c = 14.0
	climate.weather_time_s = 0.0
	scene.atmosphere.set_season(climate)
	scene.atmosphere.rain_particles.emitting = false
	scene.terrain.set_surface_season(climate)
	scene.painterly_style.set_mode(0)
	var point := Vector3(222, 0, 306) # Dry sandy cell and its eight dry neighbours.
	point.y = scene.terrain.data.get_surface_height(point)
	assert(scene.land.habitat_at(point.x, point.z).w > .8)
	for dz in [-4, 0, 4]:
		for dx in [-4, 0, 4]:
			assert(scene.water.depth[scene.water.index_at(point.x + dx, point.z + dz)] < .0001)
	var heights := []
	for offset in [Vector3(.25, 0, .75), Vector3(4.6, 0, 5.4)]:
		heights.append(scene.terrain.data.get_surface_height(point + offset))
	for view in [scene.vegetation, scene.turf_cards, scene.animals_view, scene.habitat_view, scene.fungi_view]:
		view.visible = false
	scene.camera.position = point + Vector3(1.2, 0, 1.8)
	scene.camera.position.y = scene.terrain.data.get_surface_height(scene.camera.position) + .85
	scene.camera.look_at(point + Vector3(0, .02, 0))
	var terrain = scene.terrain
	var material = terrain.material
	assert(not terrain.bank_relief_enabled and terrain.tessellation_level == 0)
	await capture("00-default-off")
	# Exercise the real HUD -> composition -> terrain-quality route.
	scene.hud.bank_relief_button.button_pressed = true
	assert(terrain.bank_relief_enabled and terrain.tessellation_level == 2)
	material.set_shader_param("bank_relief_enabled", false)
	var zero := await capture("01-zero-offset")
	var repeat := await capture("01a-null-repeat")
	var null_change := difference(zero, repeat)
	material.set_shader_param("bank_relief_enabled", true)
	var relief := await capture("02-four-cm-bank")
	var effect := difference(zero, relief)
	assert(effect > maxf(.0001, null_change * 3.0))
	# Texture aliases and interpolation come from display state, not model reads.
	assert(material.get_shader_param("bank_water_current") == scene.water_view.depth_texture)
	material.set_shader_param("snow_water_m", .03)
	var snow := await capture("03-snow-on")
	material.set_shader_param("bank_relief_enabled", false)
	var snow_zero := await capture("03a-snow-off")
	var snow_change := difference(snow, snow_zero)
	assert(snow_change <= maxf(.0001, null_change * 3.0))
	material.set_shader_param("snow_water_m", 0.0)
	# Deliberately different previous/current fields: verify live interpolation,
	# not only a constant wet map. No camera movement or buffer invalidation.
	material.set_shader_param("bank_water_previous", flat_field(0.0))
	material.set_shader_param("bank_water_current", flat_field(.1))
	material.set_shader_param("bank_water_blend", 1.0)
	var wet_zero := await capture("04-wet-off")
	material.set_shader_param("bank_relief_enabled", true)
	var wet := await capture("04a-wet-on")
	var wet_change := difference(wet, wet_zero)
	assert(wet_change <= maxf(.0001, null_change * 3.0))
	material.set_shader_param("bank_water_blend", 0.0)
	var dry := await capture("04b-dry-live-interpolation")
	assert(difference(wet, dry) > maxf(.0001, null_change * 3.0))
	terrain.advance_ecology_display(0.0)
	var original_habitat: Texture2D = material.get_shader_param("habitat_map")
	var green := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	green.fill(Color(1, 0, 0, 0))
	material.set_shader_param("habitat_map", ImageTexture.create_from_image(green))
	var green_on := await capture("05-no-sand-on")
	material.set_shader_param("bank_relief_enabled", false)
	var green_off := await capture("05a-no-sand-off")
	var green_change := difference(green_on, green_off)
	assert(green_change <= maxf(.0001, null_change * 3.0))
	material.set_shader_param("habitat_map", original_habitat)
	var diagnostic := Image.create(2, 2, false, Image.FORMAT_RGB8)
	diagnostic.fill(Color(.2, .45, .8))
	terrain.set_soil_layer(ImageTexture.create_from_image(diagnostic), true)
	var map_zero := await capture("06-map-off")
	material.set_shader_param("bank_relief_enabled", true)
	var map := await capture("06a-map-on")
	var map_change := difference(map_zero, map)
	assert(map_change <= maxf(.0001, null_change * 3.0))
	terrain.set_soil_layer(null, false)
	for i in 12:
		scene.camera.position = point + Vector3(1.2 + i * .37, 0, 1.8 + i * 2.5)
		scene.camera.position.y = terrain.data.get_surface_height(scene.camera.position) + .85
		scene.camera.look_at(point)
		await capture("07-motion-%02d" % i)
	for view in [scene.vegetation, scene.turf_cards, scene.animals_view, scene.habitat_view, scene.fungi_view]:
		view.visible = true
	scene.camera.position = point + Vector3(2, 0, 6)
	scene.camera.position.y = terrain.data.get_surface_height(scene.camera.position) + 1.65
	scene.camera.look_at(point + Vector3(0, 1, -25))
	for i in 20:
		scene.turf_cards._process(0)
	await capture("08-forest-native")
	scene.painterly_style.set_mode(2)
	await capture("08a-forest-pixel")
	scene.hud.visible = true
	scene.hud.set_options_open(true)
	await capture("09-options")
	scene.hud.bank_relief_button.button_pressed = false
	assert(not terrain.bank_relief_enabled and terrain.tessellation_level == 0)
	scene.hud.bank_relief_button.button_pressed = true
	assert(terrain.bank_relief_enabled and terrain.tessellation_level == 2)
	assert(model_bytes() == frozen)
	var index := 0
	for offset in [Vector3(.25, 0, .75), Vector3(4.6, 0, 5.4)]:
		assert(terrain.data.get_surface_height(point + offset) == heights[index])
		index += 1
	var report := {"passed": true, "point": point, "max_offset_m": terrain.BANK_MAX_OFFSET_M,
		"effect": effect, "null_difference": null_change, "snow_difference": snow_change,
		"wet_difference": wet_change, "no_sand_difference": green_change,
		"diagnostic_difference": map_change, "unchanged_models": true,
		"unchanged_surface_heights": heights, "stationary_dynamic_masks": true,
		"hud_quality_toggle": true, "shots": shots,
		"boundary": "Short paused Forward+ comparison, not sustained FPS. No user saves."}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("BANK_RELIEF ", JSON.stringify(report))
	scene.free()
	quit()
