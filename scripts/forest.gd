extends Node3D
# Inline capture/control fixtures are included in this composition root.
# gdlint: disable=max-file-lines

const WORLD_SAVE := "user://observatory-world-v1.bin"

# Composition root: model owns state, views read it, controls request changes.
var settings: ForestSettings = load("res://data/forest.tres").duplicate(true)
var ecology_clock := ForestEcologyClock.new(settings)
var weather := ForestWeather.new(settings)
var land := ForestLandscape.new(settings)
var water := ForestWatershed.new(land)
var soil := ForestSoil.new(water)
var groundcover := ForestGroundcover.new(water)
var trees := ForestTrees.new(land, soil)
var fungi := ForestFungi.new(water, soil)
var animals := ForestAnimals.new(land, trees, water, soil)
var habitat := ForestHabitat.new(trees, water, soil, animals)
var animals_view := ForestAnimalsView.new()
var habitat_view := ForestHabitatView.new()
var observation := ForestObservation.new(land)
var selection_marker := MeshInstance3D.new()
var fungi_view := ForestFungiView.new()
var barrier := land.channel_barrier()
var barrier_enabled := false
var terrain := ForestTerrainView.new()
var camera := ForestObserverCamera.new()
var vegetation := ForestVegetation.new()
var water_view := ForestWaterView.new()
var turf_cards = preload("res://scripts/turf_cards.gd").new()
var atmosphere := ForestAtmosphere.new()
var painterly_style = preload("res://scripts/painterly_style.gd").new()
var hud := ForestHud.new()
var soil_layer_visibility := {}
var soil_layer_fog_enabled := false
var dam_view := ForestBarrierView.new()
var sim_speed := settings.initial_speed
var paused := false
var render_accum := 0.0
var vegetation_accum := 0.0
var soil_display_accum := 0.25
var soil_display_tick := -1
var water_display_tick := -1
var habitat_display_tick := -1
var achieved_speed := 0.0
var speed_window_wall := 0.0
var speed_window_clock := 0.0
var cancelled_request_s := 0.0
var total_wall := 0.0
var capture_dir := ""
var capture_step := 0
var capture_pending := false
var animal_view_cursors := {}  # Presentation-only cycling, never model state.
var walkthrough := false
var simulation_usec := 0
var simulation_steps := 0
var tick_profile_usec := {}  # Last completed tick; read only after joining owner.
var ecology_usec := 0
var normal_fps := 0.0
var accelerated_fps := 0.0
var accelerated_achieved_speed := 0.0
var accelerated_start_wall := 0.0
var accelerated_start_clock := 0.0
var season_preview := 0
var paused_before_preview := false
var cycle_check := false
var fungi_check := false
var understory_check := false
var model_thread := Thread.new()
var model_work_active := false
var last_process_usec := 0
var use_model_worker := false
# Two committed intervals cover worker latency; never read a half-written model.
var presentation_frames: Array[Dictionary] = []
var presentation_weather: ForestWeather
var presentation_tick := -1
var presentation_s := 0.0
var presentation_active_wall := 0.0
var presentation_dispatch_wall := 0.0
var presentation_rate := 1.0


func _ready() -> void:
	Engine.max_fps = 60
	use_model_worker = DisplayServer.get_name() != "headless"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_dir = arg.trim_prefix("--capture=")
		if arg == "--walkthrough":
			walkthrough = true
		if arg == "--cycle-check":
			# Isolated render assay, not the shipped periods. No file/config mutation.
			cycle_check = true
			settings.day_speed_multiplier = ForestClimate.DAY_S / 20.0
			settings.year_speed_multiplier = ForestClimate.YEAR_S / 60.0
			settings.ecology_step_s = .1
		if arg == "--fungi-check":
			fungi_check = true
		if arg == "--understory-check":
			understory_check = true
	settings.validate()
	trees.mycorrhiza = fungi
	trees.habitat = habitat
	animals.habitat = habitat
	animals.establish_homes()
	groundcover.bind_plants(trees)
	add_child(camera)
	camera.configure(land, barrier)
	add_child(atmosphere)
	atmosphere.configure(settings.extent)
	atmosphere.attach_observer(camera)
	add_child(terrain)
	terrain.configure(land, camera)
	terrain.refresh_ecology(soil, water, groundcover)
	terrain.refresh_traffic(habitat)
	add_child(vegetation)
	vegetation.observer = camera
	vegetation.build(land, water, groundcover, trees, terrain.data.get_surface_height)
	vegetation.refresh_trees(_display_climate())
	add_child(fungi_view)
	fungi_view.configure(fungi)
	add_child(animals_view)
	animals_view.configure(animals)
	add_child(habitat_view)
	habitat_view.configure(habitat, camera, terrain)
	observation.register_group(&"plant", trees, vegetation.selection_shape)
	observation.register_group(
		&"animal", animals, animals_view.selection_shape, Callable(), animals_view.display_shape
	)
	observation.register_group(
		&"fungus", fungi, fungi_view.selection_shape, fungi_view.selection_ids
	)
	var ring := TorusMesh.new()
	ring.inner_radius = .94
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 8
	selection_marker.mesh = ring
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(.91, .83, .43)
	selection_marker.material_override = ring_material
	selection_marker.visible = false
	add_child(selection_marker)
	atmosphere.set_season(_display_climate())
	add_child(painterly_style)
	painterly_style.configure(atmosphere, vegetation, camera)
	if OS.get_cmdline_user_args().has("--baseline-style"):
		painterly_style.set_enabled(false)
	elif OS.get_cmdline_user_args().has("--painterly-style"):
		painterly_style.set_enabled(true)
	add_child(water_view)
	water_view.configure(water)
	terrain.configure_bank_display(water_view)
	add_child(turf_cards)
	turf_cards.configure(terrain, camera, vegetation, water_view, painterly_style)
	add_child(dam_view)
	dam_view.configure(barrier, settings.dam_height)
	add_child(hud)
	hud.configure(settings, animals.definitions)
	hud.style_button.visible = painterly_style.debug_controls_enabled
	hud.volumetric_button.set_pressed_no_signal(atmosphere.volumetric_enabled)
	hud.shadow_quality_selector.select(
		hud.shadow_quality_selector.get_item_index(atmosphere.shadow_filter_quality)
	)
	hud.configure_fungi(fungi, camera)
	hud.options_toggled.connect(
		func(open: bool):
			if open:
				camera.moving = false
				camera.stop_following()
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	)
	hud.style_button.text = "Вид · %s · F8" % painterly_style.mode_title()
	hud.style_requested.connect(painterly_style.cycle_mode)
	painterly_style.mode_changed.connect(
		func(title: String): hud.style_button.text = "Вид · %s · F8" % title
	)
	hud.rain_requested.connect(_toggle_rain)
	hud.dam_requested.connect(_toggle_dam)
	hud.pause_requested.connect(_toggle_pause)
	hud.frame_limit_requested.connect(_toggle_frame_limit)
	hud.bank_relief_requested.connect(terrain.set_bank_relief_enabled)
	hud.grass_lighting_requested.connect(
		func(value: bool):
			turf_cards.material.set_shader_parameter("root_lighting_strength", float(value))
	)
	hud.cloud_shadows_requested.connect(atmosphere.set_cloud_shadows_enabled)
	hud.volumetric_requested.connect(atmosphere.set_volumetric_enabled)
	hud.shadow_quality_requested.connect(atmosphere.set_shadow_filter_quality)
	hud.speed_requested.connect(_set_speed)
	hud.view_requested.connect(_view)
	hud.season_requested.connect(_cycle_season)
	hud.save_requested.connect(_save_world)
	hud.load_requested.connect(_load_world)
	hud.soil_layers_requested.connect(_toggle_soil_layers)
	hud.fungi_map_requested.connect(_toggle_fungi_map)
	hud.soil_layers.layer_requested.connect(_select_soil_layer)
	hud.soil_layers.cover_requested.connect(_apply_soil_layer_visibility)
	hud.observation_panel.follow_requested.connect(_set_camera_follow)
	hud.observation_panel.close_requested.connect(
		func():
			_finish_model_work(true)
			observation.selected.clear()
			_refresh_observation()
	)
	_refresh_hud()
	camera.view(1)
	if fungi_check:
		paused = true
		hud.set_paused(true)
		_view(4)
		hud.toggle_fungi_map()
	if understory_check:
		paused = true
		hud.set_paused(true)
		_view(5)
	print(
		"FOREST_READY Redot=",
		Engine.get_version_info().string,
		" terrain=",
		terrain.get_class(),
		" trees=",
		vegetation.tree_count
	)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if OS.get_cmdline_user_args().has("--habitat-render-check"):
		capture_dir = ""
		var habitat_probe = load("res://tools/check_habitat_render.gd").new()
		add_child(habitat_probe)
		habitat_probe.start.call_deferred(self)
	if OS.get_cmdline_user_args().has("--place-memory-render-check"):
		capture_dir = ""
		var place_probe = load("res://tools/check_place_memory_render.gd").new()
		add_child(place_probe)
		place_probe.start.call_deferred(self)
	if OS.get_cmdline_user_args().has("--soil-layers-render-check"):
		capture_dir = ""
		var soil_probe = load("res://tools/check_soil_layers_render.gd").new()
		add_child(soil_probe)
		soil_probe.start.call_deferred(self)
	if OS.get_cmdline_user_args().has("--food-web-render-check"):
		capture_dir = ""
		var food_probe = load("res://tools/check_food_web_render.gd").new()
		add_child(food_probe)
		food_probe.start.call_deferred(self)
	if OS.get_cmdline_user_args().has("--presentation-check"):
		capture_dir = ""
		var probe = load("res://tools/check_presentation.gd").new()
		add_child(probe)
		probe.start.call_deferred(self)
	if DisplayServer.get_name() == "headless":
		if OS.get_cmdline_user_args().has("--check-fungi-maps"):
			return  # The standalone map check owns its asynchronous scene lifetime.
		if OS.get_cmdline_user_args().has("--probe-habitat-year"):
			var year_probe = load("res://tools/probe_habitat_year.gd").new()
			add_child(year_probe)
			year_probe.start.call_deferred(self)
			return
		if OS.get_cmdline_user_args().has("--check-worker"):
			load("res://tools/check_worker.gd").run(self)
		if OS.get_cmdline_user_args().has("--check-soil-layers"):
			load("res://tools/check_soil_layers.gd").run_world(self)
		if OS.get_cmdline_user_args().has("--check-food-web"):
			load("res://tools/check_food_web.gd").run(self)
		if OS.get_cmdline_user_args().has("--check-boars"):
			load("res://tools/check_boars.gd").run(self)
		if OS.get_cmdline_user_args().has("--check-controls"):
			_check_controls()
		if OS.get_cmdline_user_args().has("--check-world"):
			load("res://tools/check_world.gd").run(self)
		_write_report("headless-smoke.json")
		get_tree().quit()


func _process(dt: float) -> void:
	var frame_started := Time.get_ticks_usec()
	vegetation.advance_weather(0.0 if paused else dt)
	habitat_view.advance_display()
	total_wall += dt
	if not paused:
		presentation_active_wall += dt
	var threaded := use_model_worker
	if threaded:
		_finish_model_work(false)
		if not model_work_active:
			_capture_presentation()
		if not paused:
			ecology_clock.request(dt * sim_speed)
		_advance_presentation(dt)
		if model_work_active:
			speed_window_wall += dt
			# The worker exclusively owns all models until the coupled tick completes.
			# Keep drawing the submitted scene and moving the camera; no partial reads.
			water_view.advance_display(0.0 if paused else dt)
			terrain.advance_ecology_display(dt)
			last_process_usec = Time.get_ticks_usec() - frame_started
			return
	elif not paused:
		_advance_world(dt * sim_speed)
	# Lighting is presentation: sample between model ticks at render cadence.
	atmosphere.set_season(_display_climate())
	if not threaded:
		animals_view.refresh(clampf(ecology_clock.pending_s / settings.ecology_step_s, 0, 1))
	terrain.set_surface_season(_display_climate())
	habitat_view.set_weather_time(_display_climate().get("weather_time_s", 0.0))
	_refresh_observation()
	speed_window_wall += dt
	if speed_window_wall >= 0.5:
		achieved_speed = (water.clock - speed_window_clock) / speed_window_wall
		speed_window_wall = 0
		speed_window_clock = water.clock
	water_view.advance_display(0.0 if paused else dt)
	terrain.advance_ecology_display(dt)
	soil_display_accum += dt
	if soil_display_accum >= 1.0 and soil_display_tick != ecology_clock.ticks:
		soil_display_tick = ecology_clock.ticks
		soil_display_accum = fmod(soil_display_accum, 1.0)
		terrain.refresh_ecology(soil, water, groundcover)
		terrain.refresh_traffic(habitat)
	vegetation.set_weather(_display_climate())
	water_view.material_override.set_shader_parameter(
		"rainfall", _display_climate().get("rain_fraction", 0.0)
	)
	water_view.material_override.set_shader_parameter(
		"weather_time", _display_climate().get("weather_time_s", 0.0)
	)
	terrain.material.set_shader_param("snow_water_m", weather.snow_water_m)
	vegetation.advance_display(dt, _display_climate())
	fungi_view.advance_display()
	render_accum += dt
	if (
		render_accum >= settings.water_display_interval_s
		and water_display_tick != ecology_clock.ticks
	):
		water_display_tick = ecology_clock.ticks
		render_accum = fmod(render_accum, settings.water_display_interval_s)
		water.sync_fields()
		water_view.refresh()
		terrain.sync_bank_water()
	vegetation_accum += dt
	if vegetation_accum >= .5 and habitat_display_tick != ecology_clock.ticks:
		habitat_display_tick = ecology_clock.ticks
		vegetation_accum = 0
		fungi.sync_fields()
		habitat_view.paused = paused
		habitat_view.refresh(_display_climate())
		_refresh_hud()
	if capture_dir != "":
		_capture_sequence()
	var display_has_room: bool = (
		presentation_frames.is_empty()
		or presentation_frames[-1].end_s - presentation_s < settings.ecology_step_s * 2.5
	)
	if threaded and not paused and display_has_room and ecology_clock.step():
		model_work_active = true
		presentation_dispatch_wall = presentation_active_wall
		var climate := ecology_clock.sample()
		if model_thread.start(_coupled_tick.bind(climate)) != OK:
			model_work_active = false
			_coupled_tick(climate)
	last_process_usec = Time.get_ticks_usec() - frame_started


func _finish_model_work(wait: bool) -> void:
	if model_work_active and (wait or not model_thread.is_alive()):
		model_thread.wait_to_finish()
		model_work_active = false
		_capture_presentation()


func _capture_presentation() -> void:
	assert(not model_work_active)
	if presentation_tick == ecology_clock.ticks:
		return
	presentation_tick = ecology_clock.ticks
	var frame := animals_view.capture_frame()
	var interval := presentation_active_wall - presentation_dispatch_wall
	if use_model_worker and interval > .000001 and not presentation_frames.is_empty():
		var produced: float = frame.end_s - presentation_frames[-1].end_s
		if produced > 0:
			var rate := produced / interval
			# Measure worker time only: include neither request debt nor buffer-full idle.
			presentation_rate = rate
	presentation_frames.append(frame)
	# Independent weather sampler owns a committed copy, including snow/overrides.
	presentation_weather = ForestWeather.new(settings)
	assert(presentation_weather.restore(weather.snapshot()))
	while presentation_frames.size() > 4:
		presentation_frames.pop_front()


func _advance_presentation(dt := 0.0) -> void:
	if presentation_frames.is_empty():
		return
	if not paused:
		# Dispatch consumes pending time before the tick finishes. Its sum remains
		# continuous; one extra interval buffers worker latency, not future physics.
		var requested := ecology_clock.elapsed_s + ecology_clock.pending_s
		var target := minf(
			maxf(0, requested - 2 * settings.ecology_step_s), presentation_frames[-1].end_s
		)
		# Unserved request debt is not a render clock. Limit playback by elapsed
		# frame time and measured committed production, even after hours of debt.
		var advance := dt * minf(sim_speed, presentation_rate)
		var remaining := maxf(0, target - presentation_s)
		var available: float = maxf(0, presentation_frames[-1].end_s - presentation_s)
		# A late completion must not exhaust the buffer and then freeze the sun.
		# Far from its end playback is linear; near it approach without extrapolation.
		presentation_s += minf(remaining, minf(available * (1.0 - exp(-dt * 4.0)), advance))
	_draw_presentation()
	var climate := _display_climate()
	atmosphere.set_season(climate)
	terrain.set_surface_season(climate)
	# These are presentation-only uniforms; busy workers must not freeze ripples.
	water_view.material_override.set_shader_parameter("rainfall", climate.get("rain_fraction", 0.0))
	water_view.material_override.set_shader_parameter(
		"weather_time", climate.get("weather_time_s", 0.0)
	)
	if camera.followed_id >= 0:
		var shape := animals_view.display_shape(camera.followed_id)
		if not shape.is_empty():
			camera.track_displayed(shape.bounds.get_center())


func _draw_presentation() -> void:
	while presentation_frames.size() > 1 and presentation_frames[0].end_s < presentation_s:
		presentation_frames.pop_front()
	var frame: Dictionary = presentation_frames[0]
	var alpha := clampf((presentation_s - frame.end_s + frame.step_s) / frame.step_s, 0, 1)
	animals_view.advance_display(frame, alpha, true)


func _reset_presentation() -> void:
	presentation_frames.clear()
	presentation_tick = -1
	presentation_rate = sim_speed
	presentation_dispatch_wall = presentation_active_wall
	animals_view.captured_frame = {}
	presentation_s = maxf(
		0,
		(
			ecology_clock.elapsed_s
			- settings.ecology_step_s
			+ minf(ecology_clock.pending_s, settings.ecology_step_s)
		)
	)
	_capture_presentation()


func _exit_tree() -> void:
	_finish_model_work(true)


func _advance_world(dt: float) -> void:
	_finish_model_work(true)
	ecology_clock.request(dt)
	var started := Time.get_ticks_usec()
	# One debt/budget for all models. Complete a coupled tick before starting
	# another: performance limits may slow the world, never separate its clocks.
	while Time.get_ticks_usec() - started < 6000 and ecology_clock.step():
		_coupled_tick(ecology_clock.sample())


func _coupled_tick(climate: Dictionary) -> void:
	# No nodes, rendering, input or shared RNG here. One owner for the entire tick.
	var tick_started := Time.get_ticks_usec()
	climate = weather.step(settings.ecology_step_s, climate)
	water.native.set_evaporation(settings.evaporation_m_s * climate.evaporation)
	water.raining = climate.rain_fraction > .01
	water.step(settings.ecology_step_s, false, climate.liquid_m_s)
	simulation_usec += Time.get_ticks_usec() - tick_started
	simulation_steps += 1
	water.sync_fields()
	var biological_dt := settings.ecology_step_s * settings.year_speed_multiplier
	var profile := {"weather_water": Time.get_ticks_usec() - tick_started}
	var mark := Time.get_ticks_usec()
	soil.step(biological_dt, water, climate)
	profile.soil = Time.get_ticks_usec() - mark
	tick_started = Time.get_ticks_usec()
	trees.step(biological_dt, water, maxf(0, water.clock - trees.water_elapsed_s), climate)
	ecology_usec += Time.get_ticks_usec() - tick_started
	profile.plants = Time.get_ticks_usec() - tick_started
	mark = Time.get_ticks_usec()
	fungi.step(biological_dt, water, climate)
	profile.fungi = Time.get_ticks_usec() - mark
	mark = Time.get_ticks_usec()
	habitat.step(biological_dt, climate)
	profile.habitat = Time.get_ticks_usec() - mark
	mark = Time.get_ticks_usec()
	animals.step(biological_dt)
	profile.animals = Time.get_ticks_usec() - mark
	mark = Time.get_ticks_usec()
	groundcover.step(biological_dt, water)
	profile.groundcover = Time.get_ticks_usec() - mark
	tick_profile_usec = profile


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hud.soil_layers.visible:
			return
		_finish_model_work(true)
		if not camera.moving and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			var renderer = painterly_style.pixel_renderer
			if not renderer.contains_screen_point(event.position):
				return
			observation.rebuild()
			observation.pick(
				renderer.ray_origin(event.position), renderer.ray_normal(event.position)
			)
			_refresh_observation()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_1:
			camera.view(1)
		KEY_2:
			camera.view(2)
		KEY_3:
			camera.view(3)
		KEY_4:
			_view(4)
		KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			_view(event.physical_keycode - KEY_1 + 1)
		KEY_C:
			_set_camera_follow(camera.followed_id < 0)
		KEY_F5:
			_save_world()
		KEY_F9:
			_load_world()
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
		KEY_G:
			_toggle_fungi_map()
		KEY_V:
			_toggle_soil_layers()


func _toggle_fungi_map() -> void:
	_finish_model_work(true)
	hud.toggle_fungi_map()


func _toggle_soil_layers() -> void:
	_finish_model_work(true)
	var layers := hud.soil_layers
	layers.visible = not layers.visible
	atmosphere.set_diagnostic_enabled(layers.visible)
	if layers.visible:
		soil_layer_fog_enabled = atmosphere.world_env.fog_enabled
		atmosphere.world_env.fog_enabled = false
		hud.fungi_map.visible = false
		for view in [vegetation, water_view, fungi_view, habitat_view, animals_view]:
			soil_layer_visibility[view] = view.visible
		_refresh_soil_layers()
	else:
		atmosphere.world_env.fog_enabled = soil_layer_fog_enabled
		terrain.set_soil_layer(null, false)
	_apply_soil_layer_visibility()
	_refresh_observation()


func _select_soil_layer(index: int) -> void:
	_finish_model_work(true)
	hud.soil_layers.selected = index
	hud.soil_layers.selector.select(index)
	_refresh_soil_layers()


func _refresh_soil_layers() -> void:
	if hud.soil_layers.visible:
		hud.soil_layers.refresh(soil, water)
		terrain.set_soil_layer(hud.soil_layers.field_texture, true)
		var parameters := hud.soil_layers.display_parameters()
		for key in parameters:
			terrain.material.set_shader_param(key, parameters[key])


func _apply_soil_layer_visibility() -> void:
	var hide_cover := hud.soil_layers.visible and hud.soil_layers.hide_cover.button_pressed
	for view in soil_layer_visibility:
		view.visible = false if hide_cover else soil_layer_visibility[view]
	if not hud.soil_layers.visible:
		soil_layer_visibility.clear()


func _view(index: int) -> void:
	_finish_model_work(true)
	camera.stop_following()
	if index >= 5 and index - 5 < animals.definitions.size():
		var definition_id := index - 5
		var cursor: int = animal_view_cursors.get(definition_id, -1)
		var animal_id := -1
		for offset in animals.species.size():
			var id := (cursor + 1 + offset) % animals.species.size()
			if animals.alive[id] and animals.species[id] == definition_id:
				animal_id = id
				break
		if animal_id < 0:
			hud.notice("Живых животных этой группы сейчас нет")
			return
		animal_view_cursors[definition_id] = animal_id
		var height: float = animals.definitions[definition_id].selection_height_m
		var target: Vector3 = animals.positions[animal_id] + Vector3.UP * height * .44
		camera.position = target + Vector3(3.2, 2.2, 4.5) * clampf(height, .18, 1.2)
		camera.look_at(target)
		camera.yaw = camera.rotation.y
		camera.pitch = camera.rotation.x
		observation.selected = {"kind": &"animal", "id": animal_id}
		_refresh_observation()
	elif index == 4:
		camera.view_plot(fungi.observation_center())
	elif index == 5 + animals.definitions.size():
		observation.selected.clear()
		_refresh_observation()
		camera.view_spring()
	else:
		camera.view(index)


func _toggle_rain() -> void:
	_finish_model_work(true)
	var precipitating: bool = weather.sample(ecology_clock.sample()).precipitation_m_s > 1e-9
	weather.toggle(precipitating)
	if presentation_weather != null:
		assert(presentation_weather.restore(weather.snapshot()))
	var climate := weather.sample(ecology_clock.sample())
	water.raining = climate.rain_fraction > .01
	atmosphere.set_season(_display_climate())
	_refresh_hud()
	hud.notice(
		(
			"Осадки включены до следующего погодного фронта."
			if not precipitating
			else "Осадки выключены до следующего погодного фронта. Ручей продолжает стекать."
		)
	)


func _toggle_dam() -> void:
	_finish_model_work(true)
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
	_finish_model_work(true)
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
	if use_model_worker and presentation_weather != null:
		return presentation_weather.sample(ecology_clock._sample_at(presentation_s), presentation_s)
	return weather.sample(
		ecology_clock.presentation_sample(),
		maxf(
			0,
			(
				ecology_clock.elapsed_s
				- settings.ecology_step_s
				+ minf(ecology_clock.pending_s, settings.ecology_step_s)
			)
		)
	)


func _cycle_season() -> void:
	_finish_model_work(true)
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
	terrain.set_surface_season(_display_climate())
	atmosphere.rain_particles.speed_scale = 0.0 if paused else 1.0
	habitat_view.paused = paused
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
	hud.refresh_fungi(fungi_view)
	_refresh_soil_layers()
	var counts := PackedInt32Array()
	counts.resize(animals.definitions.size())
	for id in animals.species.size():
		if animals.alive[id]:
			counts[animals.species[id]] += 1
	var lines := PackedStringArray()
	for s in animals.definitions.size():
		var d = animals.definitions[s]
		lines.append("%s: %d" % [d.get_meta(&"population_label", d.display_name), counts[s]])
	hud.animal_label.text = " · ".join(lines) + "\nРодилось: %d" % animals.births
	_refresh_observation()


func _set_camera_follow(enabled: bool) -> void:
	_finish_model_work(true)
	camera.stop_following()
	if enabled:
		var selected := observation.selected
		var id: int = selected.get("id", -1)
		if selected.get("kind") != &"animal" or id < 0 or not animals.alive[id]:
			hud.notice("Выбери живое животное мышью или через «Точки наблюдения»")
		else:
			var shape := animals_view.display_shape(id)
			if not shape.is_empty():
				camera.follow(id, shape.bounds.get_center())
	_refresh_observation()


func _refresh_observation() -> void:
	if not is_instance_valid(hud.observation_panel) or not hud.observation_panel.is_inside_tree():
		return
	var record := observation.describe()
	if camera.followed_id >= 0:
		if (
			record.get("kind") != &"animal"
			or record.get("id", -1) != camera.followed_id
			or not record.get("alive", false)
		):
			camera.stop_following()
		else:
			var shape := animals_view.display_shape(camera.followed_id)
			if shape.is_empty():
				camera.stop_following()
			else:
				camera.track_displayed(shape.bounds.get_center())
	hud.observation_panel.show_record(record, camera.followed_id >= 0)
	if hud.soil_layers.visible:
		hud.observation_panel.visible = false
	hud.notes_container.visible = record.is_empty() and not hud.soil_layers.visible
	selection_marker.visible = not record.is_empty() and not hud.soil_layers.visible
	if record.is_empty():
		return
	var bounds := observation.bounds()
	var center := bounds.get_center()
	selection_marker.position = Vector3(
		center.x, land.height_at(center.x, center.z) + .06, center.z
	)
	var radius := maxf(.35, maxf(bounds.size.x, bounds.size.z) * .55)
	selection_marker.scale = Vector3(radius, .2, radius)


func _world_models() -> Dictionary:
	# Dependency order matters for both a load and its rollback.
	return {
		"water": water.native,
		"soil": soil,
		"plants": trees,
		"fungi": fungi,
		"clock": ecology_clock,
		"weather": weather,
		"animals": animals,
		"habitat": habitat
	}


func _world_configuration() -> Dictionary:
	return {
		"seed": settings.seed,
		"landscape_revision": 2,
		"spring":
		[
			settings.spring_enabled,
			settings.spring_fraction,
			settings.spring_mouth_fraction,
			settings.spring_flow_m3_s,
			settings.ravine_depth_m,
			settings.ravine_half_width_m
		],
		"extent": settings.extent,
		"grid": settings.water_resolution,
		"day_multiplier": settings.day_speed_multiplier,
		"year_multiplier": settings.year_speed_multiplier,
		"step": settings.ecology_step_s
	}


func _world_snapshot() -> Dictionary:
	_finish_model_work(true)
	# A saved follow anchor and camera must refer to the same committed view.
	if use_model_worker and not presentation_frames.is_empty():
		_draw_presentation()
	else:
		animals_view.refresh(clampf(ecology_clock.pending_s / settings.ecology_step_s, 0, 1))
	_refresh_observation()
	return ForestWorldState.capture(
		_world_models(),
		_world_configuration(),
		{
			"paused": paused,
			"sim_speed": sim_speed,
			"raining": water.raining,
			"barrier": barrier_enabled,
			"season_preview": season_preview,
			"paused_before_preview": paused_before_preview,
			"camera_position": camera.position,
			"camera_rotation": camera.rotation,
			"camera_follow_id": camera.followed_id,
			"camera_follow_point": camera.followed_point,
			"selection": observation.selected.duplicate(),
			"presentation":
			(
				{"time_s": presentation_s, "frames": presentation_frames.duplicate(true)}
				if use_model_worker
				else {}
			)
		}
	)


# Explicit preflight rejection is the atomic-load contract.
# gdlint: disable=max-returns
func _restore_world(state: Dictionary) -> bool:
	_finish_model_work(true)
	var scene: Variant = state.get("scene")
	if not scene is Dictionary:
		return false
	for key in ["paused", "raining", "barrier", "paused_before_preview"]:
		if not scene.get(key) is bool:
			return false
	if not (scene.get("sim_speed") is float or scene.get("sim_speed") is int):
		return false
	if not is_finite(scene.sim_speed) or scene.sim_speed <= 0:
		return false
	if (
		not scene.get("season_preview") is int
		or scene.season_preview < 0
		or scene.season_preview > 4
	):
		return false
	for key in ["camera_position", "camera_rotation"]:
		if not scene.get(key) is Vector3 or not scene[key].is_finite():
			return false
	if not scene.get("selection") is Dictionary:
		return false
	var follow_id: Variant = scene.get("camera_follow_id", -1)
	var follow_point: Variant = scene.get("camera_follow_point", Vector3.ZERO)
	if (
		not follow_id is int
		or follow_id < -1
		or not follow_point is Vector3
		or not follow_point.is_finite()
	):
		return false
	if follow_id >= 0:
		var animal_state: Dictionary = state.get("models", {}).get("animals", {})
		if (
			scene.selection.get("kind") != &"animal"
			or scene.selection.get("id") != follow_id
			or follow_id >= animal_state.get("alive", []).size()
			or not animal_state.alive[follow_id]
		):
			return false
	var saved_display: Variant = scene.get("presentation", {})
	if not _valid_saved_presentation(saved_display, state):
		return false
	if not _compatible_world_state(state):
		return false
	if not ForestWorldState.restore(_world_models(), _world_configuration(), state):
		return false
	soil_display_tick = -1
	water_display_tick = -1
	habitat_display_tick = -1
	water.sync_fields()
	water.raining = scene.raining
	barrier_enabled = scene.barrier
	# Native crests were restored together with model reserves; reconstruct only
	# facade bookkeeping, never silently rerun/advance the hydraulic model.
	water.barriers.clear()
	if barrier_enabled:
		water.barriers.append(barrier)
	paused = scene.paused
	sim_speed = scene.sim_speed
	season_preview = scene.season_preview
	paused_before_preview = scene.paused_before_preview
	camera.position = scene.camera_position
	camera.rotation = scene.camera_rotation
	camera.yaw = camera.rotation.y
	camera.pitch = camera.rotation.x
	camera.followed_id = follow_id
	camera.followed_point = follow_point
	observation.selected = scene.selection.duplicate()
	groundcover.bind_plants(trees)
	_reset_presentation()
	if not saved_display.is_empty():
		presentation_s = saved_display.time_s
		presentation_frames.assign(saved_display.frames.duplicate(true))
	vegetation.membership_count = -1
	terrain.refresh_ecology(soil, water, groundcover)
	vegetation.refresh_trees(_display_climate())
	fungi.sync_fields()
	fungi_view.refresh()
	animals_view.rebuild()
	habitat_view.paused = paused
	habitat_view.refresh(_display_climate())
	if use_model_worker:
		_draw_presentation()
	else:
		animals_view.refresh(clampf(ecology_clock.pending_s / settings.ecology_step_s, 0, 1))
	water_view.refresh(true)
	dam_view.visible = barrier_enabled
	atmosphere.set_rain(water.raining)
	atmosphere.set_season(_display_climate())
	hud.set_paused(paused)
	speed_window_wall = 0
	speed_window_clock = water.clock
	achieved_speed = 0
	_refresh_hud()
	return true


func _valid_saved_presentation(display: Variant, state: Dictionary) -> bool:
	if not display is Dictionary:
		return false
	if display.is_empty():
		return true
	if not display.get("time_s") is float or not is_finite(display.time_s) or display.time_s < 0:
		return false
	if not display.get("frames") is Array or display.frames.is_empty() or display.frames.size() > 4:
		return false
	var models: Variant = state.get("models", {})
	if (
		not models is Dictionary
		or not models.get("clock") is Dictionary
		or not models.get("animals") is Dictionary
	):
		return false
	var ticks: Variant = models.clock.get("ticks")
	var population: Variant = models.animals.get("species")
	if not ticks is int or not population is PackedInt32Array:
		return false
	var previous := -INF
	for frame in display.frames:
		if not ForestAnimalsView.valid_frame(frame, population.size()):
			return false
		if (
			frame.step_s != settings.ecology_step_s
			or frame.end_s < previous
			or frame.end_s > ticks * settings.ecology_step_s + 1e-8
		):
			return false
		previous = frame.end_s
	return display.time_s <= previous + 1e-8


func _compatible_world_state(state: Dictionary) -> bool:
	# Reject cross-model inconsistencies before applying any participant.
	var models: Variant = state.get("models")
	if not models is Dictionary:
		return false
	for key in _world_models():
		if not models.get(key) is Dictionary:
			return false
	var reference: Dictionary = water.native.snapshot()
	for field in ["bed", "sources", "source_weights", "options"]:
		if models.water.get(field) != reference[field]:
			return false
	var selection: Dictionary = state.scene.selection
	if not selection.is_empty():
		if (
			selection.size() != 2
			or selection.get("kind") not in observation.groups
			or not selection.get("id") is int
			or selection.id < 0
		):
			return false
		var selected_model := "plants" if selection.kind == &"plant" else "animals"
		if selection.kind == &"fungus":
			if selection.id >= fungi.positions.size():
				return false
		elif (
			not models[selected_model].get("positions") is PackedVector3Array
			or selection.id >= models[selected_model].positions.size()
		):
			return false
	if not models.clock.get("ticks") is int or models.clock.ticks < 0:
		return false
	var water_s: float = models.clock.ticks * settings.ecology_step_s
	var biological_s: float = water_s * settings.year_speed_multiplier
	for value in [
		models.water.get("time_s"),
		models.plants.get("water_elapsed_s"),
		models.weather.get("elapsed_s")
	]:
		if not _same_time(value, water_s):
			return false
	for value in [
		models.soil.get("time_s"),
		models.plants.get("elapsed_s"),
		models.fungi.get("elapsed_s"),
		models.animals.get("elapsed_s"),
		models.habitat.get("elapsed_s")
	]:
		if not _same_time(value, biological_s):
			return false
	var patches: Variant = models.soil.get("patches")
	var expected: Array = soil.snapshot().patches
	if not patches is Array or patches.size() != expected.size():
		return false
	for i in patches.size():
		if not patches[i] is Dictionary:
			return false
		for key in ["n", "dx", "ox", "oz"]:
			if patches[i].get(key) != expected[i][key]:
				return false
	return true


func _same_time(value: Variant, expected: float) -> bool:
	return (
		(value is float or value is int)
		and is_finite(value)
		and absf(value - expected) <= 1e-8 * maxf(1, expected)
	)


func _save_world() -> void:
	var error := ForestWorldState.write(WORLD_SAVE, _world_snapshot())
	hud.notice(
		(
			"Мир сохранён: растения, почва, грибы и животные."
			if error == OK
			else "Не удалось сохранить мир: %s" % error_string(error)
		)
	)


func _load_world() -> void:
	var restored := _restore_world(ForestWorldState.read(WORLD_SAVE))
	hud.notice(
		(
			"Мир восстановлен. Продолжаем с того же состояния."
			if restored
			else "Сохранение не найдено или несовместимо. Текущий мир не изменён."
		)
	)


func _ecosystem_budget() -> PackedFloat64Array:
	var total := PackedFloat64Array([0, 0, 0])
	for model in [soil, trees, fungi, habitat]:
		var metrics: Dictionary = model.metrics()
		total[0] += metrics.carbon_kg
		total[1] += metrics.nitrogen_kg
		total[2] += metrics.phosphorus_kg
	for i in animals.species.size():
		total[0] += animals.biomass_c[i] + animals.gestation_c[i]
		total[1] += animals.biomass_n[i] + animals.gestation_n[i]
		total[2] += animals.biomass_p[i] + animals.gestation_p[i]
	total[0] += (
		soil.metrics().respired_kg_c
		+ fungi.metrics().respired_kg_c
		+ animals.respired_c_kg
		+ habitat.respired_kg_c
		- trees.photosynthesized_kg_c
	)
	return total


func _toggle_frame_limit() -> void:
	# Presentation only: never alter model steps, requested speed or saved worlds.
	Engine.max_fps = 30 if Engine.max_fps == 60 else 60
	hud.frame_limit_button.text = "Лимит кадров · %d FPS" % Engine.max_fps


func _set_speed(value: float) -> void:
	_finish_model_work(true)
	assert(is_finite(value) and value > 0)
	sim_speed = value
	# Discard unserved old-tempo work, not model state or the visible sun phase.
	cancelled_request_s += ecology_clock.cancel_excess_request()
	speed_window_wall = 0.0
	speed_window_clock = water.clock
	achieved_speed = 0.0
	_refresh_hud()


func _capture_sequence() -> void:
	if capture_pending:
		return
	if understory_check:
		_capture_understory()
		return
	if fungi_check:
		if total_wall > 3 and capture_step == 0:
			await _save_frame("fungi-01-ground.png")
			capture_step = 1
		elif total_wall > 5 and capture_step == 1:
			var center := fungi.observation_center()
			var target := Vector3(center.x, land.height_at(center.x, center.y), center.y)
			camera.position = target + Vector3(0, 21, 10)
			camera.look_at(target)
			await _save_frame("fungi-02-overview.png")
			capture_step = 2
		elif total_wall > 7 and capture_step == 2:
			_write_report("fungi-runtime.json")
			get_tree().quit()
		return
	if cycle_check:
		_capture_time_cycle()
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
		_set_speed(60)
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
		_toggle_soil_layers()
		_select_soil_layer(ForestSoilLayers.SURFACE_WATER)
		_refresh_hud()
		await _save_frame("07-autumn-water.png")
		capture_step = 7
	elif total_wall > 35 and capture_step == 7:
		_cycle_season()
		_write_report("runtime.json")
		capture_step = 8
		if not walkthrough:
			get_tree().quit()


func _capture_understory() -> void:
	if total_wall < 3 + capture_step * 2:
		return
	var step := capture_step
	capture_step += 1
	capture_pending = true
	if step == 0:
		assert(await _showcase(&"animal", 0), "actual input selects rendered hare")
		await _save_frame("understory-01-hare.png")
	elif step == 1 or step == 2:
		var wanted := &"shrub" if step == 1 else &"herb"
		var id := -1
		for i in trees.species.size():
			var d: ForestPlantDefinition = settings.plants[trees.species[i]]
			if (
				d.growth_form == wanted
				and (step == 1 or d.life_cycle == &"annual")
				and trees.alive[i]
			):
				id = i
				break
		assert(id >= 0 and await _showcase(&"plant", id), "actual input selects rendered plant")
		await _save_frame("understory-%02d-%s.png" % [step + 1, wanted])
	elif step == 3:
		# Completed biological actions, not a staged animal reset or free food.
		var consumed_before: float = animals.consumed_cnp.x
		for i in 32:
			_advance_world(settings.ecology_step_s)
		assert(animals.consumed_cnp.x > consumed_before, "hare ate actual vegetation")
		vegetation.refresh_trees(_display_climate())
		animals_view.refresh(clampf(ecology_clock.pending_s / settings.ecology_step_s, 0, 1))
		assert(await _showcase(&"animal", 0))
		hud.observation_panel.details_toggle.button_pressed = true
		await _save_frame("understory-04-fed-hare.png")
		_write_report("understory-runtime.json")
	elif step == 4:
		observation.selected.clear()
		camera.view(1)
		await _save_frame("understory-05-valley.png")
		get_tree().quit()
	capture_pending = false


func _showcase(kind: StringName, id: int) -> bool:
	vegetation.refresh_trees(_display_climate())
	animals_view.refresh(clampf(ecology_clock.pending_s / settings.ecology_step_s, 0, 1))
	var shape: Dictionary = observation.groups[kind].shape.call(id)
	var bounds: AABB = shape.bounds
	var center := bounds.get_center()
	var distance := maxf(1.8, bounds.size.length() * 1.6)
	camera.position = center + Vector3(.6, .45, 1).normalized() * distance
	camera.look_at(center)
	camera.yaw = camera.rotation.y
	camera.pitch = camera.rotation.x
	observation.rebuild()
	# Let the presentation camera receive this viewpoint before testing input.
	await RenderingServer.frame_post_draw
	# Find a genuinely visible face, then use the engine input/GUI path.
	var faces: PackedVector3Array = shape.faces
	var target := Vector2(-1, -1)
	for j in range(0, faces.size(), 3):
		var point: Vector3 = shape.transform * ((faces[j] + faces[j + 1] + faces[j + 2]) / 3)
		var pixel: Vector2 = painterly_style.pixel_renderer.screen_position(point)
		if pixel.x < 520 or pixel.x > 1000 or pixel.y < 100 or pixel.y > 800:
			continue
		var picked := observation.pick(
			painterly_style.pixel_renderer.ray_origin(pixel),
			painterly_style.pixel_renderer.ray_normal(pixel)
		)
		if picked == {"kind": kind, "id": id}:
			target = pixel
			break
	observation.selected.clear()
	if target.x < 0:
		return false
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	# parse_input_event starts in window pixels; the viewport then applies stretch.
	event.position = get_viewport().get_final_transform() * target
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame
	return observation.selected == {"kind": kind, "id": id} and hud.observation_panel.visible


func _capture_time_cycle() -> void:
	var times := [1.0, 8.5, 10.5, 13.0, 20.0, 40.0, 60.5]
	var names := ["day", "dusk", "night", "dawn", "autumn", "winter", "next-year"]
	if capture_step >= times.size() or ecology_clock.elapsed_s < times[capture_step]:
		return
	await _save_frame("cycle-%02d-%s.png" % [capture_step, names[capture_step]])
	_write_report("cycle-%02d-%s.json" % [capture_step, names[capture_step]])
	capture_step += 1
	if capture_step == times.size():
		get_tree().quit()


func _save_frame(filename: String) -> void:
	_finish_model_work(true)
	DirAccess.make_dir_recursive_absolute(capture_dir)
	capture_pending = true
	var previous_pause := paused
	paused = true
	vegetation.refresh_trees(_display_climate())
	atmosphere.set_season(_display_climate())
	_refresh_hud()
	# Let changed HUD glyphs/sky settle as well as waiting for the submitted frame.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_dir.path_join(filename))
	paused = previous_pause
	capture_pending = false
	print("CAPTURE ", filename)


func _write_report(filename: String) -> void:
	_finish_model_work(true)
	water.sync_fields()
	var render_times: Dictionary = painterly_style.pixel_renderer.frame_times()
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
		"pending_model_s": ecology_clock.pending_s,
		"cancelled_tempo_demand_s": cancelled_request_s,
		"accelerated_achieved_model_s_per_wall_s": accelerated_achieved_speed,
		"balance_error": water.balance_error(),
		"min_depth": min_depth,
		"plant_ticks": groundcover.ticks,
		"tree_ticks": trees.ticks,
		"tree_elapsed_years": trees.elapsed_s / ForestClimate.YEAR_S,
		"tree_age_0": trees.age_years[0],
		"living_trees": trees.alive.count(1),
		"tree_deaths": trees.deaths,
		"fungi": fungi.metrics(),
		"soil_elements": soil.metrics(),
		"plants": trees.metrics(),
		"animals": animals.metrics(),
		"fungal_bodies": fungi_view.body_count,
		"fungal_groups": fungi_view.group_count,
		"tree_transpired_m3": trees.transpired_m3,
		"calendar": _display_climate(),
		"ecology_clock": ecology_clock.snapshot(),
		"ecology_elapsed_s": ecology_clock.elapsed_s,
		"day_speed_multiplier": settings.day_speed_multiplier,
		"year_speed_multiplier": settings.year_speed_multiplier,
		"day_water_s": settings.day_water_s(),
		"year_water_s": settings.year_water_s(),
		"season_preview": season_preview,
		"model_time": water.clock,
		"dam": barrier_enabled,
		"raining": water.raining,
		"fps": Engine.get_frames_per_second(),
		"fps_normal": normal_fps,
		"fps_accelerated": accelerated_fps,
		"gpu_frame_ms": render_times.gpu_ms,
		"render_cpu_frame_ms": render_times.cpu_ms,
		"render_viewports_ms": render_times,
		"render_style": painterly_style.mode_title(),
		"scene_primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"average_simulation_step_ms": float(simulation_usec) / maxf(1.0, simulation_steps) / 1000.0,
		"average_tree_step_ms": float(ecology_usec) / maxf(1.0, trees.ticks) / 1000.0,
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
	var fungal_file := FileAccess.open(dest.trim_suffix(".json") + ".fungi.bin", FileAccess.WRITE)
	fungal_file.store_var(fungi.snapshot())


func _check_controls() -> void:
	load("res://tools/check_camera_follow.gd").run(self)
	var before_frame_limit := _world_snapshot()
	hud.frame_limit_button.pressed.emit()
	assert(Engine.max_fps == 30 and hud.frame_limit_button.text == "Лимит кадров · 30 FPS")
	assert(_world_snapshot() == before_frame_limit, "Frame cap must not change the world")
	hud.frame_limit_button.pressed.emit()
	assert(Engine.max_fps == 60 and hud.frame_limit_button.text == "Лимит кадров · 60 FPS")
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
	ecology_clock.request(100.25)
	var phase_before := ecology_clock.presentation_sample()
	hud.speed_requested.emit(8)
	assert(sim_speed == 8)
	assert(
		ecology_clock.pending_s == .5 and cancelled_request_s == 99.75,
		"new tempo cancels old debt but retains the visible interpolation phase"
	)
	assert(ecology_clock.presentation_sample() == phase_before)
	_process(0)  # Complete the retained tick before testing fresh speed requests.
	# Same shared tick at all selected speeds; faster buttons need less wall time.
	for speed in [1.0, 8.0, 60.0, 600.0]:
		hud.speed_buttons[speed].pressed.emit()
		assert(sim_speed == speed and hud.speed_buttons[speed].button_pressed)
		var time_before := ecology_clock.elapsed_s
		var water_before := water.clock
		_process(settings.ecology_step_s / speed)
		assert(absf(ecology_clock.elapsed_s - time_before - settings.ecology_step_s) < 1e-8)
		assert(absf(water.clock - water_before - settings.ecology_step_s) < 1e-8)
		_check_clock_alignment()
	assert(hud.info.text.contains("Темп мира ×600"))
	assert(hud.calendar_label.text.contains("Сутки 0.4 с · год 4.0 с"))
	# Deliberately overloaded request: neither calendar nor ecology may outrun water.
	_process(1.0)
	assert(ecology_clock.pending_s > settings.ecology_step_s)
	_check_clock_alignment()
	var loaded_phase := ecology_clock.presentation_sample()
	hud.speed_buttons[1.0].pressed.emit()
	assert(ecology_clock.presentation_sample() == loaded_phase, "no backwards sun jump on slowdown")
	_toggle_pause()
	var paused_water: Dictionary = water.native.snapshot()
	var paused_clock := ecology_clock.snapshot()
	var paused_trees := trees.snapshot()
	var paused_fungi := fungi.snapshot()
	_process(2)
	assert(water.native.snapshot() == paused_water and trees.snapshot() == paused_trees)
	assert(ecology_clock.snapshot() == paused_clock, "pause freezes the shared clock and its debt")
	assert(fungi.snapshot() == paused_fungi, "pause freezes fungal carbon and time")
	_toggle_pause()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_B
	key.pressed = true
	_unhandled_input(key)
	assert(barrier_enabled)
	_unhandled_input(key)
	assert(not barrier_enabled)
	var model_before: Dictionary = water.native.snapshot()
	var trees_before: Dictionary = trees.snapshot()
	var clock_before := ecology_clock.snapshot()
	var fungi_before := fungi.snapshot()
	for i in 5:
		hud.season_requested.emit()
		assert(season_preview == (i + 1) % 5)
		if season_preview != 0:
			assert(paused)
	assert(not paused, "preview restores the prior pause state")
	assert(
		(
			water.native.snapshot() == model_before
			and trees.snapshot() == trees_before
			and ecology_clock.snapshot() == clock_before
			and fungi.snapshot() == fungi_before
		),
		"season preview does not age trees or alter water"
	)
	_toggle_soil_layers()
	assert(hud.soil_layers.visible)
	_toggle_soil_layers()
	assert(not hud.soil_layers.visible)
	hud.toggle_fungi_map()
	assert(hud.fungi_map.visible)
	hud.toggle_fungi_map()
	assert(not hud.fungi_map.visible)
	hud.view_requested.emit(4)
	assert(
		(
			camera.position.distance_to(
				Vector3(
					fungi.observation_center().x,
					land.height_at(fungi.observation_center().x, fungi.observation_center().y),
					fungi.observation_center().y
				)
			)
			< 20
		)
	)
	var file := FileAccess.open("res://artifacts/controls.json", FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"passed": true,
				"season_preview_read_only": true,
				"water_map_toggle": true,
				"shared_speed_water_sun_year_trees_and_fungi": true,
				"overload_clocks_remain_aligned": true,
				"speed_change_preserves_solar_phase": true,
				"pause_freezes_both_clocks": true,
				"frame_limit_toggle_preserves_world": true,
				"scope": "Scene signals and key handler; not physical mouse/keyboard input"
			}
		)
	)
	print("CONTROLS_CHECK passed")


func _check_clock_alignment() -> void:
	assert(absf(water.clock - ecology_clock.elapsed_s) < 1e-8)
	assert(absf(trees.water_elapsed_s - water.clock) < 1e-8)
	assert(absf(trees.elapsed_s - water.clock * settings.year_speed_multiplier) < 1e-5)
	assert(absf(fungi.elapsed_s - trees.elapsed_s) < 1e-5)
	assert(absf(animals.elapsed_s - trees.elapsed_s) < 1e-5)
	assert(absf(animals.solar_hour(animals.elapsed_s) - ecology_clock.sample().hour) < 1e-8)
