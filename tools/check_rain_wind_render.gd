extends SceneTree

var viewport := SubViewport.new()
var particles := GPUParticles3D.new()
var wind := ForestWindField.new()
var material := ShaderMaterial.new()
var output := "res://artifacts/fronts"


func _initialize() -> void:
	create_timer(45).timeout.connect(func(): quit(1))
	_run.call_deferred()


func centroid(image: Image) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).r > .5:
				total += Vector2(x, y)
				count += 1
	assert(count > 0, "Actual particle remains visible")
	return total / count


func drift(label: String, origin_x: float, attenuation: float, spatial: bool) -> float:
	wind.shelter.fill(Color(attenuation, 100, 0))
	wind.shelter_texture.update(wind.shelter)
	wind.apply(material)
	material.set_shader_parameter("spatial_wind_enabled", spatial)
	particles.position = Vector3(origin_x, 10, 128)
	particles.restart()
	particles.emitting = true
	for frame in 8:
		await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var before := centroid(image)
	image.save_png(output.path_join(label + "-before.png"))
	for frame in 30:
		await RenderingServer.frame_post_draw
	image = viewport.get_texture().get_image()
	var after := centroid(image)
	image.save_png(output.path_join(label + "-after.png"))
	return after.x - before.x


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps = 60
	viewport.size = Vector2i(400, 256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	viewport.add_child(env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 100
	camera.position = Vector3(128, 100, 128)
	camera.rotation.x = -PI * .5
	viewport.add_child(camera)
	camera.make_current()
	var settings := ForestSettings.new()
	settings.extent = 256
	wind.configure(settings)
	# Opposite air velocities in the same world, away from the interface.
	for z in wind.resolution:
		for x in wind.resolution:
			wind.current.set_pixel(x, z, Color(10 if x < wind.resolution / 2 else -10, 0, 0))
	wind.previous = wind.current.duplicate()
	wind.current_texture.update(wind.current)
	wind.previous_texture.update(wind.previous)
	wind.blend = 1
	material.shader = load("res://shaders/precipitation.gdshader")
	material.set_shader_parameter("fall_speed", 0.0)
	material.set_shader_parameter("spatial_rain", false)
	particles.process_material = material
	particles.amount = 1
	particles.lifetime = 10
	particles.use_fixed_seed = true
	particles.seed = 2913
	particles.visibility_aabb = AABB(Vector3(-100, -30, -100), Vector3(200, 60, 200))
	var mesh := SphereMesh.new()
	mesh.radius = .7
	mesh.height = 1.4
	var display := StandardMaterial3D.new()
	display.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	display.vertex_color_use_as_albedo = true
	mesh.material = display
	particles.draw_pass_1 = mesh
	viewport.add_child(particles)
	var east := await drift("east", 102, 1, true)
	var west := await drift("west", 154, 1, true)
	var sheltered := await drift("sheltered", 102, .2, true)
	var control := await drift("disabled", 102, 1, false)
	assert(east > 4 and west < -4, "Actual shader samples opposing local velocities")
	assert(sheltered > 0 and sheltered < east * .6, "Canopy shelter reduces actual particle drift")
	assert(absf(control) < 1, "Disabled local wind rejects the drift criterion")
	var report := {
		"passed": true,
		"east_drift_px": east,
		"west_drift_px": west,
		"sheltered_drift_px": sheltered,
		"disabled_drift_px": control,
		"actual_precipitation_shader": true
	}
	FileAccess.open(output.path_join("rain-wind.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "\t")
	)
	print("RAIN_WIND_RENDER ", JSON.stringify(report))
	quit()
