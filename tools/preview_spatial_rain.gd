extends "res://tools/preview_ground_turf.gd"

var frames := 0
var gpu_error := Vector2.ZERO


func _initialize() -> void:
	output = "res://artifacts/spatial-rain"
	create_timer(150).timeout.connect(func(): quit(1))
	_run.call_deferred()


func climate_at(t: float) -> Dictionary:
	var climate: Dictionary = scene.weather.sample(ForestClimate.sample(0, 160, 60, 12), t)
	climate.front_forced = 1
	climate.front_forced_until_s = 10000.0
	climate.cloud_cover = .96
	climate.precipitation_potential_m_s = scene.settings.rainfall_m_s
	climate.precipitation_m_s = scene.settings.rainfall_m_s
	climate.rain_fraction = 1.0
	climate.temperature_c = 18.0
	climate.wind_m_s = 2.0
	return climate


func submit(climate: Dictionary) -> void:
	scene.atmosphere.set_season(climate)
	scene.vegetation.wind.submitted_weather = climate
	scene.vegetation.wind.advance(.1, climate.wind_direction * climate.wind_m_s)
	scene.vegetation.wind.apply(scene.atmosphere.rain_particles.process_material)
	scene.atmosphere.rain_particles.process_material.set_shader_parameter(
		"wind_ground", scene.water_view.material_override.get_shader_parameter("bed_map")
	)
	scene.atmosphere.rain_particles.process_material.set_shader_parameter(
		"wind_ground_enabled", true
	)
	scene.painterly_style._process(0)
	scene.water_view.material_override.set_shader_parameter("rainfall", climate.rain_fraction)
	scene.water_view.material_override.set_shader_parameter("weather_time", climate.weather_time_s)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(960, 600)
	Engine.max_fps = 20
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.capture_dir = ""
	scene._finish_model_work(true)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.hud.visible = false
	scene.atmosphere.rain_particles.speed_scale = 1
	var frozen := model_bytes()
	var deck = scene.atmosphere.cloud_deck
	var climate := climate_at(0)
	submit(climate)
	var probe := SubViewport.new()
	probe.size = Vector2i(8, 8)
	probe.disable_3d = true
	probe.use_hdr_2d = true
	probe.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(probe)
	var rect := ColorRect.new()
	rect.size = Vector2(8, 8)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
uniform sampler2D cloud_map : filter_linear, repeat_disable;
uniform sampler2D rain_mask : filter_linear, repeat_disable;
uniform vec2 deck_uv;
uniform vec2 rain_uv;
void fragment() { COLOR = vec4(texture(cloud_map,deck_uv).r, texture(rain_mask,rain_uv).r,0,1); }
"""
	material.shader = shader
	material.set_shader_parameter("cloud_map", deck.field.get_texture())
	material.set_shader_parameter("rain_mask", deck.rain_mask)
	rect.material = material
	probe.add_child(rect)
	for time in [0.0, 97.0]:
		climate = climate_at(time)
		submit(climate)
		for p in [Vector2(2, 2), Vector2(258, 258), Vector2(178, 286), Vector2(510, 510)]:
			material.set_shader_parameter(
				"deck_uv", Vector2.ONE * .5 + (p - Vector2.ONE * 256) / deck.clouds.span_m
			)
			material.set_shader_parameter("rain_uv", p / scene.settings.extent)
			for frame in 3:
				await RenderingServer.frame_post_draw
			var pixel := probe.get_texture().get_image().get_pixel(4, 4)
			var density: float = deck.clouds.native.sample_density(
				p.x, p.y, scene.settings.extent, climate.cloud_offset_m
			)
			var weight: float = deck.clouds.local_weight(p, climate)
			print(
				"RAIN_GPU_SAMPLE ", time, " ", p, " ", pixel, " expected=", Vector2(density, weight)
			)
			gpu_error.x = maxf(gpu_error.x, absf(pixel.r - density))
			gpu_error.y = maxf(gpu_error.y, absf(pixel.g - weight))
	assert(
		gpu_error.x < .005 and gpu_error.y < .002, "Rendered cloud/rain fields match model samples"
	)
	probe.queue_free()
	# Fixed observer: choose a boundary crossing, then follow its cloud in model time.
	var point := Vector2(256, 256)
	var dry_time := -1.0
	var wet_time := -1.0
	for t in range(0, 1000, 4):
		var weight: float = deck.clouds.local_weight(point, climate_at(t))
		if weight == 0:
			dry_time = t
		if weight > .8 and dry_time >= 0:
			wet_time = t
			break
	assert(wet_time > dry_time)
	var base := Vector3(point.x, scene.land.height_at(point.x, point.y), point.y)
	scene.camera.position = base + Vector3(0, 3, 0)
	scene.camera.look_at(base + Vector3(20, 10, -60))
	climate = climate_at(wet_time)
	submit(climate)
	for frame in 30:
		await RenderingServer.frame_post_draw
	var with_drops := await photo("01-rain-forest", true)
	scene.atmosphere.rain_particles.visible = false
	scene.atmosphere.rain_particles.emitting = false
	for frame in 30:
		await RenderingServer.frame_post_draw
	var without_drops := await photo("02-same-clouds-without-drops", true)
	var drop_change := difference(with_drops, without_drops)
	assert(drop_change > .00005, "Known-wrong hidden drops must visibly differ")
	scene.atmosphere.rain_particles.visible = true
	scene.atmosphere.rain_particles.emitting = true
	scene.camera.position = base + Vector3(0, 38, 55)
	scene.camera.look_at(base + Vector3(0, 45, -70))
	for i in 60:
		var t := lerpf(dry_time - 12, wet_time + 12, float(i) / 59)
		submit(climate_at(t))
		for frame in 2:
			await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		assert(image.save_png(output.path_join("frame-%03d.png" % i)) == OK)
		frames += 1
	assert(model_bytes() == frozen, "Weather rendering and photographs cannot advance reserves")
	var report := {
		"passed": true,
		"frames": frames,
		"density_gpu_error": gpu_error.x,
		"drop_control_image_difference": drop_change,
		"rain_mask_gpu_error": gpu_error.y,
		"dry_time_s": dry_time,
		"wet_time_s": wet_time,
		"model_unchanged": true,
		"phases": phases
	}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("SPATIAL_RAIN_RENDER ", JSON.stringify(report))
	scene.free()
	quit()
