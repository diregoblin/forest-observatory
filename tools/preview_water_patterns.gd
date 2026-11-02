extends "res://tools/preview_ground_turf.gd"


func _initialize() -> void:
	output = "res://artifacts/water-patterns"
	create_timer(90).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1200, 720)
	Engine.max_fps = 20
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene._finish_model_work(true)
	scene.capture_dir = ""
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.hud.visible = false
	var frozen := model_bytes()
	var material: ShaderMaterial = scene.water_view.material_override
	var current: Shader = material.shader
	var previous := Shader.new()
	previous.code = FileAccess.get_file_as_string(
		"/run/media/pavel/Storage/tmp/forest-water-patterns-20261103/water.gdshader"
	)
	assert(not previous.code.is_empty())
	var point := Vector3(scene.land.channel_x(256), 0, 256)
	var index: int = scene.water.index_at(point.x, point.z)
	point.y = scene.water.bed[index] + scene.water.depth[index] + .045
	var cases := []
	for condition in [
		["day-dry", 12.0, 0.0],
		["day-rain", 12.0, 1.0],
		["sunset", 19.0, 0.0],
		["night-rain", 1.0, 1.0]
	]:
		var climate := ForestClimate.sample(0, 155, 60, condition[1])
		climate.cloud_cover = .50 if condition[2] > 0 else .18
		climate.weather_time_s = 13.25
		scene.atmosphere.set_season(climate)
		scene.atmosphere.rain_particles.emitting = false
		material.set_shader_parameter("weather_time", 13.25)
		material.set_shader_parameter("rainfall", condition[2])
		for camera_name in ["near", "far"]:
			if camera_name == "near":
				scene.camera.position = point + Vector3(0, 2.4, 9)
				scene.camera.look_at(point + Vector3(0, 0, -3))
			else:
				scene.camera.position = point + Vector3(0, 35, 55)
				scene.camera.look_at(point)
			var label: String = condition[0] + "-" + camera_name
			material.shader = previous
			var before := await photo(label + "-before", true)
			material.shader = current
			var after := await photo(label + "-after", true)
			cases.append({"label": label, "difference": difference(before, after)})
	# Motion, especially independent births/fades rather than synchronized rings.
	scene.camera.position = point + Vector3(0, 2.4, 9)
	scene.camera.look_at(point + Vector3(0, 0, -3))
	var climate := ForestClimate.sample(0, 155, 60, 12)
	climate.cloud_cover = .5
	scene.atmosphere.set_season(climate)
	scene.atmosphere.rain_particles.emitting = false
	material.set_shader_parameter("rainfall", 1.0)
	for step in 4:
		material.set_shader_parameter("weather_time", 13.25 + step * .21)
		await photo("rain-motion-%d" % step, true)
	assert(model_bytes() == frozen)
	var report := {
		"passed": true,
		"unchanged_models": true,
		"cases": cases,
		"phases": phases,
		"boundary":
		"Paused Forward+ near/far images and short phase sequence, not FPS or physical wave validation."
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("WATER_PATTERNS ", JSON.stringify(report))
	scene.free()
	quit()
