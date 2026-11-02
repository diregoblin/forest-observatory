extends "res://tools/preview_cloud_edges.gd"


func _initialize() -> void:
	super._initialize()
	output = "res://artifacts/cloud-softness"


func reference_path() -> String:
	return "/run/media/pavel/Storage/tmp/forest-soft-clouds-20261103/shaders/painterly_sky.gdshader"


func extra_captures() -> void:
	var cloud = scene.atmosphere.cloud_deck
	var material: ShaderMaterial = cloud.shadow_material
	var current: Shader = material.shader
	var previous := Shader.new()
	previous.code = FileAccess.get_file_as_string(
		"/run/media/pavel/Storage/tmp/forest-soft-clouds-20261103/shaders/cloud_shadow.gdshader"
	)
	assert(not previous.code.is_empty())
	var climate := ForestClimate.sample(0, 155, 60, 12)
	climate.cloud_cover = .65
	climate.weather_time_s = 180.0
	climate.sun_elevation = deg_to_rad(45)
	scene.atmosphere.set_season(climate)
	scene.atmosphere.rain_particles.emitting = false
	scene.painterly_style.set_mode(2)
	scene.camera.view(1)
	scene.atmosphere.sun.light_angular_distance = 0.0
	material.shader = previous
	await capture("valley-shadow-before")
	scene.atmosphere.sun.light_angular_distance = 1.5
	material.shader = current
	await capture("valley-shadow-after")
	# A short, paused move exposes crawl/pepper at fractional shadow borders.
	for step in 3:
		scene.camera.position += scene.camera.basis.x * .2
		await capture("shadow-motion-%d" % step)
	# Isolate actual shadow-map coverage on a neutral receiver. No atmosphere,
	# ambient or vegetation can fake the intermediate direct-light control.
	scene.atmosphere.set_volumetric_enabled(false)
	var env: Environment = scene.atmosphere.world_env
	env.ambient_light_energy = 0
	env.fog_enabled = false
	env.glow_enabled = false
	env.ssao_enabled = false
	scene.atmosphere.sun.light_energy = 1
	for view in [scene.terrain, scene.vegetation, scene.animals_view, scene.turf_cards,
		scene.habitat_view, scene.fungi_view, scene.water_view, scene.dam_view]:
		view.visible = false
	scene.painterly_style.set_process(false)
	var receiver := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 24
	receiver.mesh = plane
	receiver.position = Vector3(256, 20, 256)
	receiver.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var neutral := StandardMaterial3D.new()
	neutral.albedo_color = Color(.9, .9, .9)
	receiver.material_override = neutral
	scene.add_child(receiver)
	scene.camera.position = receiver.position + Vector3(0, 24, 12)
	scene.camera.look_at(receiver.position)
	var levels := []
	for value in [0.0, 1.0]:
		var constant := Image.create(2, 2, false, Image.FORMAT_RF)
		constant.fill(Color(value, value, value))
		material.set_shader_parameter("cloud_field_map", ImageTexture.create_from_image(constant))
		var image := await capture("coverage-%.3f" % value)
		var mean := 0.0
		for y in range(image.get_height() / 2 - 40, image.get_height() / 2 + 40):
			for x in range(image.get_width() / 2 - 40, image.get_width() / 2 + 40):
				var c := image.get_pixel(x, y)
				mean += (c.r + c.g + c.b) / (3.0 * 80 * 80)
		levels.append(mean)
	assert(levels[0] > .3 and levels[1] < .02)
	# A known straight cloud edge, centred by independent sun-ray projection.
	# Its transition must broaden with finite solar size, not global dimming.
	var edge := Image.create(2, 2, false, Image.FORMAT_RF)
	edge.fill(Color.BLACK)
	for y in 2:
		edge.set_pixel(1, y, Color.WHITE)
	material.set_shader_parameter("cloud_field_map", ImageTexture.create_from_image(edge))
	material.set_shader_parameter("cloud_cover", .65625)  # Half coverage at field=.5.
	var direction: Vector3 = scene.atmosphere.sun.global_basis.z
	receiver.position = cloud.position - direction * ((cloud.height - 20.0) / direction.y)
	scene.camera.position = receiver.position + Vector3(0, 24, 12)
	scene.camera.look_at(receiver.position)
	var counts := []
	for angle in [0.0, 1.5]:
		scene.atmosphere.sun.light_angular_distance = angle
		var image := await capture("penumbra-%.1f" % angle)
		var intermediate := 0
		for y in range(image.get_height() / 2 - 40, image.get_height() / 2 + 40):
			for x in range(image.get_width() / 2 - 120, image.get_width() / 2 + 120):
				var c := image.get_pixel(x, y)
				var value := (c.r + c.g + c.b) / 3.0
				if value > .10 and value < .70:
					intermediate += 1
		counts.append(intermediate)
	assert(counts[1] > counts[0] * 2 + 50, "Finite sun must broaden the isolated cloud penumbra")
	print("CLOUD_PENUMBRA ", JSON.stringify({"clear_blocked": levels, "intermediate_pixels": counts}))
	receiver.queue_free()
