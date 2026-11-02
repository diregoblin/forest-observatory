extends "res://tools/preview_ground_turf.gd"

var samples := []
var marker: MeshInstance3D
var fixed := {}


func _initialize() -> void:
	output = "res://artifacts/terrain-shadows"
	create_timer(90).timeout.connect(func(): quit(1))
	_run.call_deferred()


func setup_shadows(corrected: bool, disabled := false) -> void:
	var light = scene.atmosphere.sun
	for key in fixed:
		light.set(key, fixed[key])
	if not corrected:
		light.directional_shadow_max_distance = 280
		light.directional_shadow_split_1 = .1
		light.directional_shadow_split_2 = .2
		light.directional_shadow_split_3 = .5
		light.directional_shadow_fade_start = .8
	scene.terrain.cast_shadows = 0 if disabled else (2 if corrected else 1)


func capture(label: String, probe := true) -> float:
	scene.painterly_style._process(0)
	for frame in 10:
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.save_png(output.path_join(label + ".png")) == OK)
	var luminance := 0.0
	if probe:
		var pixel: Vector2 = scene.camera.unproject_position(marker.position)
		for y in range(int(pixel.y) - 4, int(pixel.y) + 5):
			for x in range(int(pixel.x) - 4, int(pixel.x) + 5):
				var color := image.get_pixel(x, y)
				luminance += (color.r + color.g + color.b) / (3.0 * 81.0)
	samples.append({"label": label, "probe_mean": luminance})
	return luminance


func climate_for(phase: String) -> Dictionary:
	var climate := ForestClimate.sample(0, 155, 60, 12)
	climate.cloud_cover = 0.0
	climate.weather_time_s = 0.0
	climate.sun_elevation = deg_to_rad(60.0 if phase == "noon" else 5.0)
	climate.sun_azimuth = deg_to_rad(85.0 if phase == "dawn" else 275.0)
	return climate


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
	var frozen := model_bytes()
	for view in [scene.vegetation, scene.animals_view, scene.turf_cards, scene.habitat_view, scene.fungi_view, scene.water_view]:
		view.visible = false
	scene.painterly_style.set_mode(0)
	for key in ["directional_shadow_max_distance", "directional_shadow_split_1", "directional_shadow_split_2", "directional_shadow_split_3", "directional_shadow_fade_start"]:
		fixed[key] = scene.atmosphere.sun.get(key)
	assert(is_equal_approx(fixed.directional_shadow_max_distance, scene.settings.extent * 1.6))
	assert(is_equal_approx(fixed.directional_shadow_split_1 * fixed.directional_shadow_max_distance, 28.0))
	marker = MeshInstance3D.new()
	var quad := QuadMesh.new()
	marker.mesh = quad
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.9, .9, .9)
	material.roughness = 1
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker.material_override = material
	scene.add_child(marker)
	var point := Vector3(256, 0, 256)
	point.y = scene.terrain.data.get_surface_height(point)
	for near in [true, false]:
		quad.size = Vector2.ONE * (3 if near else 12)
		marker.position = point + Vector3.UP * (3 if near else 8)
		for phase in ["dawn", "dusk", "noon"]:
			scene.atmosphere.set_season(climate_for(phase))
			scene.atmosphere.rain_particles.emitting = false
			# Isolate direct solar occlusion, not ambient tint or sky reflection.
			scene.atmosphere.sun.light_energy = 1.0
			scene.atmosphere.world_env.ambient_light_energy = 0.0
			scene.atmosphere.world_env.background_mode = Environment.BG_COLOR
			scene.atmosphere.world_env.background_color = Color.BLACK
			scene.atmosphere.world_env.fog_enabled = false
			scene.atmosphere.world_env.glow_enabled = false
			var direction: Vector3 = scene.atmosphere.sun.global_basis.z.normalized()
			marker.look_at(marker.position - direction, Vector3.UP)
			var horizontal := Vector3(direction.x, 0, direction.z).normalized()
			scene.camera.position = marker.position + horizontal * (9 if near else 330) + Vector3.UP * (1 if near else 200)
			scene.camera.fov = 70 if near else 40
			scene.camera.look_at(marker.position)
			# Geometric heightfield oracle is independent of shadow-map rendering.
			var blocked := false
			for distance in range(2, 512):
				var ray := marker.position + direction * distance
				if ray.x < 1 or ray.z < 1 or ray.x > 510 or ray.z > 510:
					break
				if scene.terrain.data.get_surface_height(ray) > ray.y:
					blocked = true
					break
			assert(blocked == (phase != "noon"))
			var prefix: String = ("near-" if near else "far-") + phase
			setup_shadows(false)
			var old := await capture(prefix + "-before")
			setup_shadows(true)
			var corrected := await capture(prefix + "-after")
			setup_shadows(true, true)
			var no_occluder := await capture(prefix + "-no-terrain-shadow")
			assert(no_occluder > .4, "Known-wrong absent terrain must admit direct sun")
			if blocked:
				assert(corrected < .02)
				assert(old < .02 if near else old > .4, "Reproduce the legacy 280 m receiver cutoff")
			else:
				assert(absf(corrected - no_occluder) < .01)
	setup_shadows(true)
	marker.visible = false
	scene.camera.fov = 70
	scene.camera.view(1)
	scene.atmosphere.world_env.background_mode = Environment.BG_SKY
	scene.atmosphere.world_env.fog_enabled = true
	scene.atmosphere.world_env.glow_enabled = true
	for view in [scene.vegetation, scene.animals_view, scene.turf_cards, scene.habitat_view, scene.fungi_view, scene.water_view]:
		view.visible = true
	scene.painterly_style.set_mode(2)
	for phase in ["dawn", "dusk", "noon"]:
		scene.atmosphere.displayed_weather.clear()
		scene.atmosphere.set_season(climate_for(phase))
		scene.atmosphere.rain_particles.emitting = false
		setup_shadows(false)
		await capture("forest-" + phase + "-before", false)
		setup_shadows(true)
		await capture("forest-" + phase + "-after", false)
	var below := climate_for("dusk")
	below.sun_elevation = deg_to_rad(-2)
	scene.atmosphere.set_season(below)
	assert(scene.atmosphere.sun.light_energy == 0.0)
	assert(model_bytes() == frozen)
	var report := {"passed": true, "settings": fixed, "near_far_oracle_controls": true,
		"near_cascade_extent_m": 28, "unchanged_models": true, "below_horizon_direct_energy": 0,
		"samples": samples, "boundary": "Paused Forward+ terrain-shadow test, not a performance benchmark; no user saves."}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("TERRAIN_SHADOWS ", JSON.stringify(report))
	scene.free()
	quit()
