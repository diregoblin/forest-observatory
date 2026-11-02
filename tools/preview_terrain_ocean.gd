extends "res://tools/preview_ground_turf.gd"


func _initialize() -> void:
	output = "res://artifacts/terrain-ocean"
	super._initialize()


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
	var climate := ForestClimate.sample(0, 155, 60, 12)
	climate.cloud_cover = .18
	climate.weather_time_s = 0.0
	scene.atmosphere.set_season(climate)
	scene.atmosphere.rain_particles.emitting = false
	scene.painterly_style.set_mode(2)
	var point := Vector3(scene.land.channel_x(250), 0, 250)
	point.y = scene.terrain.data.get_surface_height(point) + .8
	scene.camera.position = point + Vector3(10, 4, 15)
	scene.camera.look_at(point)
	# The ocean is a separate static-level visual example, never a new water solver.
	scene.water_view.visible = false
	var before := await photo("01-without-ocean", true)
	var ocean: ShaderMaterial = (
		load("res://addons/terrain_3d/extras/shaders/M_ocean.tres").duplicate(true)
	)
	ocean.set_shader_parameter("sea_level", point.y)
	ocean.set_shader_parameter("height_scale", .25)
	ocean.set_shader_parameter("time_scale", .1)
	scene.terrain.ocean_material = ocean
	scene.terrain.light_target = scene.atmosphere.sun
	scene.terrain.ocean_enabled = true
	var after := await photo("02-native-ocean-demo-only", true)
	var change := difference(before, after)
	assert(change > .001)
	assert(model_bytes() == frozen)
	var report := {
		"passed": true,
		"unchanged_models": true,
		"ocean_mean_rgb_difference": change,
		"sea_level_m": point.y,
		"ocean_enabled_only_in_fixture": true,
		"boundary":
		(
			"Native ocean clipmap with static sea level and TIME-driven waves, "
			+ "not our physical river or a new water simulation."
		)
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("TERRAIN_OCEAN ", JSON.stringify(report))
	scene.free()
	quit()
