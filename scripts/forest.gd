extends Node3D

# Composition root: model owns state, views read it, controls request changes.
var settings: ForestSettings = load("res://data/forest.tres")
var land := ForestLandscape.new(settings)
var water := ForestWatershed.new(land)
var groundcover := ForestGroundcover.new(water)
var trees := ForestTrees.new(land)
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
var vegetation_accum := 0.0
var achieved_speed := 0.0
var speed_window_wall := 0.0
var speed_window_clock := 0.0
var cancelled_request_s := 0.0
var ecology_accum := 0.0
var total_wall := 0.0
var capture_dir := ""
var capture_step := 0
var capture_pending := false
var walkthrough := false
var simulation_usec := 0
var simulation_steps := 0
var normal_fps := 0.0
var accelerated_fps := 0.0
var accelerated_achieved_speed := 0.0
var accelerated_start_wall := 0.0
var accelerated_start_clock := 0.0
var season_preview := 0
var paused_before_preview := false


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
	vegetation.build(land, water, groundcover, trees)
	vegetation.refresh_plants()
	vegetation.refresh_trees(_display_climate())
	atmosphere.set_season(_display_climate())
	add_child(water_view)
	water_view.configure(water)
	add_child(dam_view)
	dam_view.configure(barrier, settings.dam_height)
	add_child(hud)
	hud.configure(settings)
	hud.rain_requested.connect(_toggle_rain)
	hud.dam_requested.connect(_toggle_dam)
	hud.pause_requested.connect(_toggle_pause)
	hud.speed_requested.connect(_set_speed)
	hud.view_requested.connect(camera.view)
	hud.season_requested.connect(_cycle_season)
	_refresh_hud()
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
		accumulator += dt * sim_speed
		var budget_start := Time.get_ticks_usec()
		# Keep debt rather than changing physics/dropping requested model time.
		while accumulator >= settings.water_step and Time.get_ticks_usec() - budget_start < 6000:
			var started := Time.get_ticks_usec()
			var climate := ForestClimate.sample(
				water.clock, settings.start_day, settings.latitude_deg
			)
			water.native.set_evaporation(settings.evaporation_m_s * climate.evaporation)
			water.step(settings.water_step, false)
			ecology_accum += settings.water_step
			if ecology_accum >= settings.ecology_interval:
				water.sync_fields()
				groundcover.step(ecology_accum, water)
				trees.step(ecology_accum, water)
				ecology_accum = 0.0
			simulation_usec += Time.get_ticks_usec() - started
			simulation_steps += 1
			accumulator -= settings.water_step
	speed_window_wall += dt
	if speed_window_wall >= 0.5:
		achieved_speed = (water.clock - speed_window_clock) / speed_window_wall
		speed_window_wall = 0
		speed_window_clock = water.clock
	water_view.advance_display(dt)
	render_accum += dt
	if render_accum >= settings.water_display_interval_s:
		render_accum = fmod(render_accum, settings.water_display_interval_s)
		water.sync_fields()
		water_view.refresh()
	vegetation_accum += dt
	if vegetation_accum >= .5:
		vegetation_accum = 0
		vegetation.refresh_plants()
		vegetation.refresh_trees(_display_climate())
		atmosphere.set_season(_display_climate())
		_refresh_hud()
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
		KEY_T:
			_cycle_season()
		KEY_M:
			hud.toggle_map()


func _toggle_rain() -> void:
	water.raining = not water.raining
	atmosphere.set_rain(water.raining)
	_refresh_hud()
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
	_refresh_hud()
	hud.notice(
		(
			"В русле появилась преграда. Наблюдаем верхний бьеф."
			if barrier_enabled
			else "Преграда убрана. Удержанная вода может уйти вниз."
		)
	)


func _toggle_pause() -> void:
	if season_preview != 0:
		season_preview = 0
		paused = true
	paused = not paused
	hud.set_paused(paused)
	_refresh_hud()


func _display_climate() -> Dictionary:
	if season_preview != 0:
		var day: float = [0, 20, 125, 200, 275][season_preview]
		return ForestClimate.sample(0, day, settings.latitude_deg)
	return ForestClimate.sample(water.clock, settings.start_day, settings.latitude_deg)


func _cycle_season() -> void:
	if season_preview == 0:
		paused_before_preview = paused
	season_preview = (season_preview + 1) % 5
	paused = true if season_preview != 0 else paused_before_preview
	hud.set_paused(paused)
	vegetation.refresh_trees(_display_climate())
	atmosphere.set_season(_display_climate())
	_refresh_hud()
	hud.notice(
		(
			"Просмотр сезона на паузе. T — следующий; после осени вернётся текущая дата."
			if season_preview != 0
			else "Текущая дата возвращена. Запасы и возраст деревьев не менялись."
		)
	)


func _refresh_hud() -> void:
	hud.refresh(
		water,
		vegetation,
		groundcover,
		barrier_enabled,
		sim_speed,
		achieved_speed,
		trees,
		_display_climate(),
		season_preview != 0
	)


func _set_speed(value: float) -> void:
	sim_speed = value
	# A new tempo replaces unserved demand at the previous tempo, not model state.
	var fractional := fmod(accumulator, settings.water_step)
	cancelled_request_s += accumulator - fractional
	accumulator = fractional


func _capture_sequence() -> void:
	if capture_pending:
		return
	if total_wall > 3 and capture_step == 0:
		await _save_frame("01-valley.png")
		camera.view(2)
		capture_step = 1
	elif total_wall > 5 and capture_step == 1:
		normal_fps = Engine.get_frames_per_second()
		await _save_frame("02-creek.png")
		camera.view(3)
		_toggle_dam()
		_toggle_rain()
		sim_speed = 60
		accelerated_start_wall = total_wall
		accelerated_start_clock = water.clock
		capture_step = 2
	elif total_wall > 23 and capture_step == 2:
		await _save_frame("03-rain-dam.png")
		accelerated_fps = Engine.get_frames_per_second()
		accelerated_achieved_speed = (
			(water.clock - accelerated_start_clock) / (total_wall - accelerated_start_wall)
		)
		paused = true
		hud.set_paused(true)
		capture_step = 3
	elif total_wall > 27 and capture_step == 3:
		camera.view(1)
		if water.raining:
			_toggle_rain()
		_cycle_season()
		await _save_frame("04-winter.png")
		capture_step = 4
	elif total_wall > 29 and capture_step == 4:
		_cycle_season()
		await _save_frame("05-spring.png")
		capture_step = 5
	elif total_wall > 31 and capture_step == 5:
		_cycle_season()
		await _save_frame("06-summer.png")
		capture_step = 6
	elif total_wall > 33 and capture_step == 6:
		_cycle_season()
		hud.toggle_map()
		_refresh_hud()
		await _save_frame("07-autumn-water.png")
		capture_step = 7
	elif total_wall > 35 and capture_step == 7:
		_cycle_season()
		_write_report("runtime.json")
		capture_step = 8
		if not walkthrough:
			get_tree().quit()


func _save_frame(filename: String) -> void:
	DirAccess.make_dir_recursive_absolute(capture_dir)
	capture_pending = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_dir.path_join(filename))
	capture_pending = false
	print("CAPTURE ", filename)


func _write_report(filename: String) -> void:
	water.sync_fields()
	var min_depth := INF
	for h in water.depth:
		min_depth = minf(min_depth, h)
	var report := {
		"engine": Engine.get_version_info(),
		"terrain_class": terrain.get_class(),
		"regions": terrain.data.get_region_count(),
		"trees": vegetation.tree_count,
		"water_volume": water.volume(),
		"soil_volume_m3": water.soil_volume,
		"hydrology": water.stats,
		"resolution": water.resolution,
		"cell_size_m": water.cell_size,
		"requested_speed": sim_speed,
		"achieved_model_s_per_wall_s": achieved_speed,
		"pending_model_s": accumulator,
		"cancelled_tempo_demand_s": cancelled_request_s,
		"accelerated_achieved_model_s_per_wall_s": accelerated_achieved_speed,
		"balance_error": water.balance_error(),
		"min_depth": min_depth,
		"plant_ticks": groundcover.ticks,
		"tree_ticks": trees.ticks,
		"living_trees": trees.alive.count(1),
		"tree_deaths": trees.deaths,
		"tree_transpired_m3": trees.transpired_m3,
		"calendar": _display_climate(),
		"season_preview": season_preview,
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
	var saved := water.save_state(dest.trim_suffix(".json") + ".water.bin")
	assert(saved == OK)


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
	accumulator = 100.25
	hud.speed_requested.emit(8)
	assert(sim_speed == 8)
	assert(
		accumulator == 0.25 and cancelled_request_s == 100.0,
		"new tempo cancels old demand, not model time"
	)
	sim_speed = 2
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	_unhandled_input(key)
	assert(barrier_enabled)
	_unhandled_input(key)
	assert(not barrier_enabled)
	var model_before: Dictionary = water.native.snapshot()
	var trees_before: Dictionary = trees.snapshot()
	for i in 5:
		hud.season_requested.emit()
		assert(season_preview == (i + 1) % 5)
		if season_preview != 0:
			assert(paused)
	assert(not paused, "preview restores the prior pause state")
	assert(
		water.native.snapshot() == model_before and trees.snapshot() == trees_before,
		"season preview does not age trees or alter water"
	)
	hud.toggle_map()
	assert(hud.hydro_map.visible)
	hud.toggle_map()
	assert(not hud.hydro_map.visible)
	var file := FileAccess.open("res://artifacts/controls.json", FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"passed": true,
				"season_preview_read_only": true,
				"water_map_toggle": true,
				"scope": "Scene signals and key handler; not physical mouse/keyboard input"
			}
		)
	)
	print("CONTROLS_CHECK passed")
