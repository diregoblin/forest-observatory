extends SceneTree

var scene


func _initialize() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(960, 600)
	scene = load("res://scripts/forest.gd").new()
	root.add_child(scene)
	scene.capture_dir = ""
	scene.camera.set_process(false)
	scene.hud.visible = false
	Engine.max_fps = 20
	var wind: ForestWindField = scene.vegetation.wind
	var begin_wind := wind.elapsed_s
	var begin_ticks: int = scene.ecology_clock.ticks
	var busy := 0
	var completed := 0
	var previous_ticks: int = scene.presentation_tick
	var last_time := begin_wind
	for frame in 50:
		await RenderingServer.frame_post_draw
		if scene.model_work_active:
			busy += 1
		if scene.presentation_tick > previous_ticks:
			completed += 1
			previous_ticks = scene.presentation_tick
		assert(wind.elapsed_s > last_time)
		last_time = wind.elapsed_s
	scene.paused = true
	scene._finish_model_work(true)
	scene.set_process(false)
	assert(busy > 0 and completed > 0 and scene.ecology_clock.ticks > begin_ticks)
	var stopped := wind.elapsed_s
	var models := {}
	for key in scene._world_models():
		models[key] = scene._world_models()[key].snapshot()
	var frozen := var_to_bytes(models)
	for frame in 3:
		scene._process(.02)
		await RenderingServer.frame_post_draw
	assert(wind.elapsed_s == stopped and scene.wind_audio.stream_paused)
	models.clear()
	for key in scene._world_models():
		models[key] = scene._world_models()[key].snapshot()
	assert(frozen == var_to_bytes(models))
	# Validate the deferred preparation path used after the plant broad phase.
	var count := 0
	var pick_usec := 0
	for id in scene.vegetation.tree_count:
		var shape: Dictionary = scene.vegetation.selection_shape(id)
		if not shape.has("prepare_deform"):
			continue
		var deform: Callable = shape.prepare_deform.call()
		var a: Vector3 = deform.call(Vector3(0, 2, 0))
		assert(a.is_finite())
		var center: Vector3 = shape.bounds.get_center()
		var started := Time.get_ticks_usec()
		ForestObservation._shape_distance(shape, center + Vector3(0, 0, 20), Vector3.FORWARD, 40)
		pick_usec = maxi(pick_usec, Time.get_ticks_usec() - started)
		count += 1
		if count == 8:
			break
	assert(count == 8)
	var report := {
		"passed": true,
		"busy_frames": busy,
		"completion_frames": completed,
		"completed_ticks": scene.ecology_clock.ticks - begin_ticks,
		"wind_seconds": stopped - begin_wind,
		"paused_models_unchanged": true,
		"prepared_pick_shapes": count,
		"max_shape_pick_usec": pick_usec
	}
	FileAccess.open("res://artifacts/spatial-wind/live.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("WIND_LIVE ", JSON.stringify(report))
	scene.free()
	quit()
