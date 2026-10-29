extends Node3D

# Composition root: model owns state, views read it, controls request changes.
var settings: ForestSettings = load("res://data/forest.tres")
var land := ForestLandscape.new(settings)
var water := ForestWatershed.new(land)
var groundcover := ForestGroundcover.new(water)
var barrier := land.channel_barrier()
var barrier_enabled := false
var terrain := ForestTerrainView.new()
var camera := ForestObserverCamera.new()
var vegetation := ForestVegetation.new()
var water_view := ForestWaterView.new()
var atmosphere := ForestAtmosphere.new()
var hud := ForestHud.new()
var dam_view := ForestBarrierView.new()
var sim_speed := 2.0
var paused := false
var accumulator := 0.0
var render_accum := 0.0
var total_wall := 0.0
var capture_dir := ""
var capture_step := 0
var walkthrough := false
var simulation_usec := 0
var simulation_steps := 0
var normal_fps := 0.0
var accelerated_fps := 0.0


func _ready() -> void:
	settings.validate()
	Engine.max_fps = 40
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_dir = arg.trim_prefix("--capture=")
		if arg == "--walkthrough":
			walkthrough = true
	add_child(camera)
	camera.configure(land, barrier)
	add_child(atmosphere)
	atmosphere.configure()
	atmosphere.attach_observer(camera)
	add_child(terrain)
	terrain.configure(land, camera)
	add_child(vegetation)
	vegetation.build(land, water, groundcover)
	vegetation.refresh_plants()
	add_child(water_view)
	water_view.configure(water)
	add_child(dam_view)
	dam_view.configure(barrier, settings.dam_height)
	add_child(hud)
	hud.configure(settings)
	hud.rain_requested.connect(_toggle_rain)
	hud.dam_requested.connect(_toggle_dam)
	hud.pause_requested.connect(_toggle_pause)
	hud.speed_requested.connect(func(value: float): sim_speed = value)
	hud.view_requested.connect(camera.view)
	hud.refresh(water, vegetation, groundcover, barrier_enabled)
	camera.view(1)
	print(
		"FOREST_READY Redot=",
		Engine.get_version_info().string,
		" terrain=",
		terrain.get_class(),
		" trees=",
		vegetation.tree_count
	)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if DisplayServer.get_name() == "headless":
		if OS.get_cmdline_user_args().has("--check-controls"):
			_check_controls()
		_write_report("headless-smoke.json")
		get_tree().quit()


func _process(dt: float) -> void:
	total_wall += dt
	if not paused:
		accumulator += minf(dt, .15) * sim_speed
		var steps := 0
		while accumulator >= settings.water_step and steps < 6:
			var started := Time.get_ticks_usec()
			water.step(settings.water_step)
			groundcover.step(settings.water_step, water)
			simulation_usec += Time.get_ticks_usec() - started
			simulation_steps += 1
			accumulator -= settings.water_step
			steps += 1
	render_accum += dt
	if render_accum > .25:
		render_accum = 0
		water_view.refresh()
		vegetation.refresh_plants()
		hud.refresh(water, vegetation, groundcover, barrier_enabled)
	if capture_dir != "":
		_capture_sequence()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_1:
			camera.view(1)
		KEY_2:
			camera.view(2)
		KEY_3:
			camera.view(3)
		KEY_R:
			_toggle_rain()
		KEY_B:
			_toggle_dam()
		KEY_SPACE:
			_toggle_pause()
		KEY_F:
			hud.visible = not hud.visible


func _toggle_rain() -> void:
	water.raining = not water.raining
	atmosphere.set_rain(water.raining)
	hud.refresh(water, vegetation, groundcover, barrier_enabled)
	hud.notice(
		(
			"Начался дождь: почва впитывает воду, низины собирают сток."
			if water.raining
			else "Дождь закончился. Ручей продолжает стекать."
		)
	)


func _toggle_dam() -> void:
	barrier_enabled = not barrier_enabled
	water.set_barrier(barrier, barrier_enabled)
	dam_view.visible = barrier_enabled
	hud.refresh(water, vegetation, groundcover, barrier_enabled)
	hud.notice(
		(
			"В русле появилась преграда. Наблюдаем верхний бьеф."
			if barrier_enabled
			else "Преграда убрана. Удержанная вода может уйти вниз."
		)
	)


func _toggle_pause() -> void:
	paused = not paused
	hud.set_paused(paused)


func _capture_sequence() -> void:
	if total_wall > 3 and capture_step == 0:
		_save_frame("01-valley.png")
		camera.view(2)
		capture_step = 1
	elif total_wall > 5 and capture_step == 1:
		normal_fps = Engine.get_frames_per_second()
		_save_frame("02-creek.png")
		camera.view(3)
		_toggle_dam()
		_toggle_rain()
		sim_speed = 8
		capture_step = 2
	elif total_wall > 23 and capture_step == 2:
		_save_frame("03-rain-dam.png")
		accelerated_fps = Engine.get_frames_per_second()
		paused = true
		hud.set_paused(true)
		capture_step = 3
	elif total_wall > 27 and capture_step == 3:
		_write_report("runtime.json")
		capture_step = 4
		if not walkthrough:
			get_tree().quit()


func _save_frame(filename: String) -> void:
	DirAccess.make_dir_recursive_absolute(capture_dir)
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(capture_dir.path_join(filename))
	print("CAPTURE ", filename)


func _write_report(filename: String) -> void:
	var min_depth := INF
	for h in water.depth:
		min_depth = minf(min_depth, h)
	var report := {
		"engine": Engine.get_version_info(),
		"terrain_class": terrain.get_class(),
		"regions": terrain.data.get_region_count(),
		"trees": vegetation.tree_count,
		"water_volume": water.volume(),
		"balance_error": water.balance_error(),
		"min_depth": min_depth,
		"plant_ticks": groundcover.ticks,
		"model_time": water.clock,
		"dam": barrier_enabled,
		"raining": water.raining,
		"fps": Engine.get_frames_per_second(),
		"fps_normal": normal_fps,
		"fps_accelerated": accelerated_fps,
		"gpu_frame_ms":
		RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		"render_cpu_frame_ms":
		RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),
		"scene_primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"average_simulation_step_ms": float(simulation_usec) / maxf(1.0, simulation_steps) / 1000.0,
		"renderer": RenderingServer.get_current_rendering_method()
	}
	var dest := (
		"res://artifacts/".path_join(filename)
		if capture_dir == ""
		else capture_dir.path_join(filename)
	)
	var f := FileAccess.open(dest, FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))


func _check_controls() -> void:
	hud.rain_button.pressed.emit()
	assert(water.raining)
	hud.rain_button.pressed.emit()
	assert(not water.raining)
	hud.dam_button.pressed.emit()
	assert(barrier_enabled and water.barriers.size() == 1)
	hud.dam_button.pressed.emit()
	assert(not barrier_enabled and water.barriers.is_empty())
	hud.pause_button.pressed.emit()
	assert(paused)
	hud.pause_button.pressed.emit()
	assert(not paused)
	var position_before := camera.position
	hud.view_requested.emit(3)
	assert(camera.position != position_before)
	hud.speed_requested.emit(8)
	assert(sim_speed == 8)
	sim_speed = 2
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	_unhandled_input(key)
	assert(barrier_enabled)
	_unhandled_input(key)
	assert(not barrier_enabled)
	var file := FileAccess.open("res://artifacts/controls.json", FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"passed": true,
				"scope": "Scene signals and key handler; not physical mouse/keyboard input"
			}
		)
	)
	print("CONTROLS_CHECK passed")
