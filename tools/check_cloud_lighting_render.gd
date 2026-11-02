extends "res://tools/preview_ground_turf.gd"

var cloud
var marker := MeshInstance3D.new()
var samples := []


func _initialize() -> void:
	output = "res://artifacts/cloud-lighting-check"
	create_timer(150).timeout.connect(func(): quit(1))
	_run.call_deferred()


func probe(label: String, point: Vector3, casting: bool) -> float:
	marker.position = point
	marker.mesh.size = Vector2.ONE * (32 if label.begins_with("far") else 4)
	scene.camera.position = (
		point + (Vector3(0, 200, 330) if label.begins_with("far") else Vector3(0, 10, 6))
	)
	scene.camera.look_at(point)
	cloud.visible = casting
	for frame in 5:
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(output.path_join(label + ".png"))
	var mean := 0.0
	for y in range(446, 455):
		for x in range(716, 725):
			var c := image.get_pixel(x, y)
			mean += (c.r + c.g + c.b) / (3 * 81.0)
	samples.append({"label": label, "mean_rgb": mean, "point": point})
	print("CLOUD_PROBE ", JSON.stringify(samples[-1]))
	return mean


func field_at(image: Image, point: Vector3, direction: Vector3) -> float:
	# Independent ray/plane intersection, not a shadow-map lookup.
	var hit: Vector3 = point + direction * ((cloud.height - point.y) / direction.y)
	var uv: Vector2 = (
		(Vector2(hit.x, hit.z) - Vector2.ONE * cloud.extent * .5) / (cloud.extent * 8)
		+ Vector2.ONE * .5
	)
	var pixel: Vector2 = uv * Vector2(image.get_size()) - Vector2.ONE * .5
	var x := floori(pixel.x)
	var y := floori(pixel.y)
	return lerpf(
		lerpf(image.get_pixel(x, y).r, image.get_pixel(x + 1, y).r, pixel.x - x),
		lerpf(image.get_pixel(x, y + 1).r, image.get_pixel(x + 1, y + 1).r, pixel.x - x),
		pixel.y - y
	)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene._finish_model_work(true)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.turf_cards.set_process(false)
	scene.hud.visible = false
	scene.painterly_style.pixel_renderer.set_enabled(false)
	scene.painterly_style.set_process(false)
	Engine.max_fps = 20
	var frozen := model_bytes()
	var climate := ForestClimate.sample(0, 155, 60, 12)
	climate.cloud_cover = .65
	climate.weather_time_s = 180.0
	climate.sun_elevation = deg_to_rad(45)
	scene.atmosphere.set_season(climate)
	scene.atmosphere.rain_particles.emitting = false
	for view in [
		scene.terrain,
		scene.vegetation,
		scene.animals_view,
		scene.turf_cards,
		scene.habitat_view,
		scene.fungi_view,
		scene.water_view,
		scene.dam_view
	]:
		view.visible = false
	var env = scene.atmosphere.world_env
	env.ambient_light_energy = 0
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.fog_enabled = false
	env.glow_enabled = false
	env.ssao_enabled = false
	scene.atmosphere.sun.light_energy = 1
	cloud = scene.atmosphere.cloud_deck
	var surface := PlaneMesh.new()
	surface.size = Vector2.ONE * 4
	marker.mesh = surface
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.9, .9, .9)
	material.roughness = 1
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(marker)
	for frame in 10:
		await RenderingServer.frame_post_draw
	var field_image: Image = cloud.field.get_texture().get_image()
	var constant := Image.create(2, 2, false, Image.FORMAT_RF)
	constant.fill(Color.WHITE)
	cloud.shadow_material.set_shader_parameter(
		"cloud_field_map", ImageTexture.create_from_image(constant)
	)
	var point := Vector3(256, 20, 256)
	var clear := await probe("01-no-caster", point, false)
	var blocked := await probe("02-solid-caster", point, true)
	assert(
		clear > .3 and blocked < .02,
		"Opaque cloud plane must block the sun even in the near cascade"
	)
	env.ambient_light_energy = .35
	var ambient := await probe("03-ambient-preserved", point, true)
	assert(ambient > blocked + .05, "Clouds must not erase ambient light")
	env.ambient_light_energy = 0
	cloud.shadow_material.set_shader_parameter("cloud_field_map", cloud.field.get_texture())
	var direction: Vector3 = scene.atmosphere.sun.global_basis.z
	var extrema := [INF, -INF]
	var points := [Vector3.ZERO, Vector3.ZERO]
	for z in range(32, 480, 8):
		for x in range(32, 480, 8):
			var p := Vector3(x, 20, z)
			var value := field_at(field_image, p, direction)
			if value < extrema[0]:
				extrema[0] = value
				points[0] = p
			if value > extrema[1]:
				extrema[1] = value
				points[1] = p
	print("CLOUD_FIELD_RANGE ", extrema)
	assert(extrema[0] < .44 and extrema[1] > .55)
	var lit := await probe("04-field-clear", points[0], true)
	var shadow := await probe("05-field-shadow", points[1], true)
	assert(
		lit > .3 and shadow < .02, "World-projected field must agree with an independent sun ray"
	)
	var far_lit := await probe("far-field-clear", points[0], true)
	var far_shadow := await probe("far-field-shadow", points[1], true)
	assert(far_lit > .3 and far_shadow < .02)
	# Repeat the solid-occluder control at low sun from both sides.
	cloud.shadow_material.set_shader_parameter(
		"cloud_field_map", ImageTexture.create_from_image(constant)
	)
	for azimuth in [85.0, 275.0]:
		climate.sun_elevation = deg_to_rad(20)
		climate.sun_azimuth = deg_to_rad(azimuth)
		scene.atmosphere.set_season(climate)
		scene.atmosphere.sun.light_energy = 1
		env.ambient_light_energy = 0  # set_season restores natural ambient; this assay isolates direct light.
		var low_blocked := await probe("low-%d" % int(azimuth), point, true)
		assert(low_blocked < .02)
	cloud.shadow_material.set_shader_parameter("cloud_field_map", cloud.field.get_texture())
	var unchanged: Image = cloud.field.get_texture().get_image()
	assert(
		unchanged.get_data() == field_image.get_data(), "Camera movement cannot move cloud patterns"
	)
	climate.weather_time_s += 60
	scene.atmosphere.set_season(climate)
	for frame in 5:
		await RenderingServer.frame_post_draw
	assert(cloud.field.get_texture().get_image().get_data() != field_image.get_data())
	climate.sun_elevation = -.02
	scene.atmosphere.set_season(climate)
	assert(not cloud.visible and scene.atmosphere.sun.light_energy == 0)
	scene.painterly_style.set_mode(0)
	assert(
		not cloud.visible and cloud.field.render_target_update_mode == SubViewport.UPDATE_DISABLED
	)
	assert(model_bytes() == frozen)
	var report := {
		"passed": true,
		"direct_light_control": true,
		"near_far_and_low_sun": true,
		"ambient_preserved": true,
		"world_projection_oracle": true,
		"camera_independent": true,
		"clock_driven": true,
		"below_horizon_disabled": true,
		"baseline_disabled": true,
		"unchanged_models": true,
		"samples": samples
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	scene.free()
	quit()
