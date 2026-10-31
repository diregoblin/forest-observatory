extends Node3D

const WORLD_SAVE := "user://observatory-world-v1.bin"

# Composition root: model owns state, views read it, controls request changes.
var settings: ForestSettings = load("res://data/forest.tres").duplicate(true)
var ecology_clock := ForestEcologyClock.new(settings)
var land := ForestLandscape.new(settings)
var water := ForestWatershed.new(land)
var soil := ForestSoil.new(water)
var groundcover := ForestGroundcover.new(water)
var trees := ForestTrees.new(land, soil)
var fungi := ForestFungi.new(water, soil)
var animals := ForestAnimals.new(land, trees, water, soil)
var animals_view := ForestAnimalsView.new()
var observation := ForestObservation.new(land)
var selection_marker := MeshInstance3D.new()
var fungi_view := ForestFungiView.new()
var barrier := land.channel_barrier()
var barrier_enabled := false
var terrain := ForestTerrainView.new()
var camera := ForestObserverCamera.new()
var vegetation := ForestVegetation.new()
var water_view := ForestWaterView.new()
var atmosphere := ForestAtmosphere.new()
var hud := ForestHud.new()
var dam_view := ForestBarrierView.new()
var sim_speed := settings.initial_speed
var paused := false
var render_accum := 0.0
var vegetation_accum := 0.0
var achieved_speed := 0.0
var speed_window_wall := 0.0
var speed_window_clock := 0.0
var cancelled_request_s := 0.0
var total_wall := 0.0
var capture_dir := ""
var capture_step := 0
var capture_pending := false
var walkthrough := false
var simulation_usec := 0
var simulation_steps := 0
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


func _ready() -> void:
	Engine.max_fps = 40
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
	groundcover.bind_plants(trees)
	add_child(camera)
	camera.configure(land, barrier)
	add_child(atmosphere)
	atmosphere.configure()
	atmosphere.attach_observer(camera)
	add_child(terrain)
	terrain.configure(land, camera)
	add_child(vegetation)
	vegetation.build(land, water, groundcover, trees)
	vegetation.refresh_trees(_display_climate())
	add_child(fungi_view)
	fungi_view.configure(fungi)
	add_child(animals_view)
	animals_view.configure(animals)
	observation.register_group(&"plant", trees, vegetation.selection_shape)
	observation.register_group(&"animal", animals, animals_view.selection_shape)
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
	add_child(water_view)
	water_view.configure(water)
	add_child(dam_view)
	dam_view.configure(barrier, settings.dam_height)
	add_child(hud)
	hud.configure(settings)
	hud.configure_fungi(fungi)
	hud.rain_requested.connect(_toggle_rain)
	hud.dam_requested.connect(_toggle_dam)
	hud.pause_requested.connect(_toggle_pause)
	hud.speed_requested.connect(_set_speed)
	hud.view_requested.connect(_view)
	hud.season_requested.connect(_cycle_season)
	hud.save_requested.connect(_save_world)
	hud.load_requested.connect(_load_world)
	hud.observation_panel.close_requested.connect(
		func():
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
	if DisplayServer.get_name() == "headless":
		if OS.get_cmdline_user_args().has("--check-controls"):
			_check_controls()
		if OS.get_cmdline_user_args().has("--check-world"):
			load("res://tools/check_world.gd").run(self)
		_write_report("headless-smoke.json")
		get_tree().quit()


func _process(dt: float) -> void:
	total_wall += dt
	if not paused:
		_advance_world(dt * sim_speed)
	# Lighting is presentation: sample between model ticks at render cadence.
	atmosphere.set_season(_display_climate())
	animals_view.refresh(clampf(ecology_clock.pending_s / settings.ecology_step_s, 0, 1))
	_refresh_observation()
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
		vegetation.refresh_trees(_display_climate())
		fungi.sync_fields()
		fungi_view.refresh()
		_refresh_hud()
	if capture_dir != "":
		_capture_sequence()


func _advance_world(dt: float) -> void:
	ecology_clock.request(dt)
	var started := Time.get_ticks_usec()
	# One debt/budget for all models. Complete a coupled tick before starting
	# another: performance limits may slow the world, never separate its clocks.
	while Time.get_ticks_usec() - started < 6000 and ecology_clock.step():
		var tick_started := Time.get_ticks_usec()
		var climate := ecology_clock.sample()
		water.native.set_evaporation(settings.evaporation_m_s * climate.evaporation)
		water.step(settings.ecology_step_s, false)
		simulation_usec += Time.get_ticks_usec() - tick_started
		simulation_steps += 1
		water.sync_fields()
		var biological_dt := ecology_clock.biological_step_s()
		soil.step(biological_dt, water)
		tick_started = Time.get_ticks_usec()
		trees.step(biological_dt, water, maxf(0, water.clock - trees.water_elapsed_s))
		ecology_usec += Time.get_ticks_usec() - tick_started
		fungi.step(biological_dt, water, ecology_clock.sample())
		animals.step(biological_dt)
		groundcover.step(biological_dt, water)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not camera.moving and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			observation.rebuild()
			observation.pick(
				camera.project_ray_origin(event.position), camera.project_ray_normal(event.position)
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
		KEY_5:
			_view(5)
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
		KEY_M:
			hud.toggle_map()
		KEY_G:
			hud.toggle_fungi_map()


func _view(index: int) -> void:
	if index == 5 and not animals.positions.is_empty():
		var target: Vector3 = animals.positions[0] + Vector3.UP * .4
		camera.position = target + Vector3(3.2, 2.2, 4.5)
		camera.look_at(target)
		camera.yaw = camera.rotation.y
		camera.pitch = camera.rotation.x
	elif index == 4:
		camera.view_plot(fungi.observation_center())
	else:
		camera.view(index)


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
	return ecology_clock.presentation_sample()


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
	hud.refresh_fungi(fungi_view)
	hud.animal_label.text = "Зайцы: %d · выбери ЛКМ для справки" % animals.alive.count(1)
	_refresh_observation()


func _refresh_observation() -> void:
	if not is_instance_valid(hud.observation_panel) or not hud.observation_panel.is_inside_tree():
		return
	var record := observation.describe()
	hud.observation_panel.show_record(record)
	hud.notes_container.visible = record.is_empty()
	selection_marker.visible = not record.is_empty()
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
		"animals": animals
	}


func _world_configuration() -> Dictionary:
	return {
		"seed": settings.seed,
		"extent": settings.extent,
		"grid": settings.water_resolution,
		"day_multiplier": settings.day_speed_multiplier,
		"year_multiplier": settings.year_speed_multiplier,
		"step": settings.ecology_step_s
	}


func _world_snapshot() -> Dictionary:
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
			"selection": observation.selected.duplicate()
		}
	)


# Explicit preflight rejection is the atomic-load contract.
# gdlint: disable=max-returns
func _restore_world(state: Dictionary) -> bool:
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
	if not _compatible_world_state(state):
		return false
	if not ForestWorldState.restore(_world_models(), _world_configuration(), state):
		return false
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
	observation.selected = scene.selection.duplicate()
	groundcover.bind_plants(trees)
	vegetation.membership_count = -1
	vegetation.refresh_trees(_display_climate())
	fungi.sync_fields()
	fungi_view.refresh()
	animals_view.refresh(clampf(ecology_clock.pending_s / settings.ecology_step_s, 0, 1))
	water_view.refresh()
	dam_view.visible = barrier_enabled
	atmosphere.set_rain(water.raining)
	hud.set_paused(paused)
	speed_window_wall = 0
	speed_window_clock = water.clock
	achieved_speed = 0
	_refresh_hud()
	return true


func _compatible_world_state(state: Dictionary) -> bool:
	# Reject cross-model inconsistencies before applying any participant.
	var models: Variant = state.get("models")
	if not models is Dictionary:
		return false
	for key in _world_models():
		if not models.get(key) is Dictionary:
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
		if (
			not models[selected_model].get("positions") is PackedVector3Array
			or selection.id >= models[selected_model].positions.size()
		):
			return false
	if not models.clock.get("ticks") is int or models.clock.ticks < 0:
		return false
	var water_s: float = models.clock.ticks * settings.ecology_step_s
	var biological_s: float = water_s * settings.year_speed_multiplier
	for value in [models.water.get("time_s"), models.plants.get("water_elapsed_s")]:
		if not _same_time(value, water_s):
			return false
	for value in [
		models.soil.get("time_s"),
		models.plants.get("elapsed_s"),
		models.fungi.get("elapsed_s"),
		models.animals.get("elapsed_s")
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
			"Мир сохранён: растения, почва, грибы и заяц."
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
	for model in [soil, trees, fungi]:
		var metrics: Dictionary = model.metrics()
		total[0] += metrics.carbon_kg
		total[1] += metrics.nitrogen_kg
		total[2] += metrics.phosphorus_kg
	for i in animals.species.size():
		total[0] += animals.biomass_c[i]
		total[1] += animals.biomass_n[i]
		total[2] += animals.biomass_p[i]
	total[0] += (
		soil.metrics().respired_kg_c
		+ fungi.metrics().respired_kg_c
		+ animals.respired_c_kg
		- trees.photosynthesized_kg_c
	)
	return total


func _set_speed(value: float) -> void:
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
	# Find a genuinely visible face, then use the engine input/GUI path.
	var faces: PackedVector3Array = shape.faces
	var target := Vector2(-1, -1)
	for j in range(0, faces.size(), 3):
		var point: Vector3 = shape.transform * ((faces[j] + faces[j + 1] + faces[j + 2]) / 3)
		var pixel := camera.unproject_position(point)
		if pixel.x < 520 or pixel.x > 1000 or pixel.y < 100 or pixel.y > 800:
			continue
		var picked := observation.pick(
			camera.project_ray_origin(pixel), camera.project_ray_normal(pixel)
		)
		if picked == {"kind": kind, "id": id}:
			target = pixel
			break
	observation.selected.clear()
	if target.x < 0:
		return false
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = target
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
		"gpu_frame_ms":
		RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		"render_cpu_frame_ms":
		RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),
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
	assert(hud.calendar_label.text.contains("Сутки 0.1 с · год 1.0 с"))
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
	hud.toggle_map()
	assert(hud.hydro_map.visible)
	hud.toggle_map()
	assert(not hud.hydro_map.visible)
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
