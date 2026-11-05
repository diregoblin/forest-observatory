extends "res://tools/preview_ground_turf.gd"


func _initialize() -> void:
	output = "res://artifacts/fronts"
	create_timer(90).timeout.connect(func(): quit(1))
	_run.call_deferred()


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
	var frozen := model_bytes()
	var deck = scene.atmosphere.cloud_deck
	var p := Vector2(256, 256)
	var ground: float = scene.land.height_at(p.x, p.y)
	scene.camera.position = Vector3(256, ground + 35, 290)
	scene.camera.look_at(Vector3(100, ground + 55, 180))
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
void fragment(){ COLOR=vec4(texture(cloud_map,deck_uv).rg,texture(rain_mask,rain_uv).r,1); }
"""
	material.shader = shader
	material.set_shader_parameter("cloud_map", deck.field.get_texture())
	material.set_shader_parameter("rain_mask", deck.rain_mask)
	rect.material = material
	probe.add_child(rect)
	var error := Vector3.ZERO
	for t in [20.0, 60.0, 180.0]:
		var climate: Dictionary = scene.weather.sample(ForestClimate.sample(0, 180), t)
		scene.atmosphere.set_season(climate)
		scene.painterly_style._process(0)
		var fields := ForestWeatherFront.grid(climate, scene.settings.extent)
		for pos in [Vector2(2, 2), Vector2(258, 258), Vector2(178, 286), Vector2(510, 510)]:
			material.set_shader_parameter(
				"deck_uv", Vector2.ONE * .5 + (pos - Vector2.ONE * 256) / deck.clouds.span_m
			)
			material.set_shader_parameter("rain_uv", pos / scene.settings.extent)
			for frame in 3:
				await RenderingServer.frame_post_draw
			var actual := probe.get_texture().get_image().get_pixel(4, 4)
			var density: float = deck.clouds.native.sample_density(
				pos.x, pos.y, scene.settings.extent, climate.cloud_offset_m
			)
			var cover := ForestWeatherFront.value(fields.cloud_cover, pos, scene.settings.extent)
			var expected_mask := (
				ForestWindField.bilinear(deck.rain_mask.get_image(), pos / scene.settings.extent).x
			)
			error.x = maxf(error.x, absf(actual.r - density))
			error.y = maxf(error.y, absf(actual.g - cover))
			error.z = maxf(error.z, absf(actual.b - expected_mask))
		await photo("front-%03d" % int(t), true)
	assert(
		error.x < .005 and error.y < .003 and error.z < .002,
		"Actual field viewport has local cloud cover and rain"
	)
	assert(model_bytes() == frozen, "Front display cannot advance models")
	var report := {
		"passed": true,
		"density_gpu_error": error.x,
		"local_cover_gpu_error": error.y,
		"rain_mask_gpu_error": error.z,
		"models_unchanged": true,
		"phases": phases
	}
	FileAccess.open(output.path_join("render.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "\t")
	)
	print("FRONTS_RENDER ", JSON.stringify(report))
	scene.free()
	quit()
