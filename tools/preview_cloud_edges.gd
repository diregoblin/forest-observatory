extends "res://tools/preview_ground_turf.gd"

const ANIMAL_DEFINITION = preload("res://scripts/animal_definition.gd")
const BEFORE := (
	"/run/media/pavel/Storage/tmp/forest-sky-hare-20261102/" + "shaders/painterly_sky.gdshader"
)


func _initialize() -> void:
	output = "res://artifacts/cloud-edges"
	super._initialize()


func capture(label: String) -> Image:
	scene.painterly_style._process(0)
	for frame in 6:
		await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	assert(result.save_png(output.path_join(label + ".png")) == OK)
	return result


func reference_path() -> String:
	return BEFORE


func extra_captures() -> void:
	pass


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1200, 720)
	Engine.max_fps = 15
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.capture_dir = ""
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.atmosphere.set_process(false)
	scene.hud.visible = false
	var frozen := model_bytes()
	var current: Shader = scene.painterly_style.sky_material.shader
	var previous := Shader.new()
	previous.code = FileAccess.get_file_as_string(reference_path())
	assert(not previous.code.is_empty())
	scene.camera.position = Vector3(200, scene.land.height_at(200, 196) + 2.0, 196)
	var camera_point: Vector3 = scene.camera.position
	scene.camera.look_at(camera_point + Vector3(0, .06, -1))
	var report := {
		"passed": false, "cases": [], "renderer": RenderingServer.get_current_rendering_method()
	}
	assert(report.renderer == "forward_plus")
	for condition in [
		["day", .20, 12.0],
		["broken", .48, 12.0],
		["sunset", .65, 20.5],
		["overcast", .95, 12.0],
		["night", .75, 1.0]
	]:
		var climate := ForestClimate.sample(0, 155, 60, condition[2])
		climate.cloud_cover = condition[1]
		climate.weather_time_s = 0.0
		scene.atmosphere.set_season(climate)
		scene.atmosphere.rain_particles.emitting = false
		for mode in [2, 1] if condition[0] == "day" else [2]:
			scene.painterly_style.set_mode(mode)
			scene.painterly_style.sky_material.shader = previous
			var before := await capture("%s-%d-before" % [condition[0], mode])
			scene.painterly_style.sky_material.shader = current
			var after := await capture("%s-%d-after" % [condition[0], mode])
			var change := difference(before, after)
			assert(change > .0001)
			report.cases.append(
				{"condition": condition[0], "style": mode, "visible_difference": change}
			)
	# Different bearings and zenith expose projection seams and lattice directions.
	var day := ForestClimate.sample(0, 155, 60, 12)
	day.cloud_cover = .48
	day.weather_time_s = 0.0
	scene.atmosphere.set_season(day)
	for bearing in 4:
		scene.camera.rotation = Vector3(.5, bearing * PI / 2.0 + .01, 0)
		await capture("bearing-%d-after" % bearing)
	scene.camera.rotation = Vector3(PI / 2.0 - .01, 0, 0)
	await capture("zenith-after")
	await extra_captures()
	assert(model_bytes() == frozen)
	report.passed = true
	report.unchanged_models = true
	report.boundary = (
		"Paused real Forward+ scene; cloud shape/palette inspection, "
		+ "not FPS or volumetric weather."
	)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("CLOUD_EDGES ", JSON.stringify(report))
	scene.free()
	quit()
