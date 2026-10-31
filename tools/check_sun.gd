extends SceneTree

## Isolated real Forward+ scene assay; no user save or shipped setting changes.
## ./tools/preview_isolated.sh --script res://tools/check_sun.gd
var world: Node3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	assert(RenderingServer.get_current_rendering_method() == "forward_plus")
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.capture_step = 8  # Disable the unrelated canned valley capture sequence.
	# Drive the actual composition root at a reproducible frame cadence; GPU draws
	# every frame. No shortened day or smaller ecological step can mask the bug.
	for frame in 40:
		await _frame()
	var previous: Vector3 = world.atmosphere.sun.basis.z
	var maximum_angle := 0.0
	var minimum_angle := INF
	for frame in 80:
		await _frame()
		var current: Vector3 = world.atmosphere.sun.basis.z
		var angle := previous.angle_to(current)
		minimum_angle = minf(minimum_angle, angle)
		maximum_angle = maxf(maximum_angle, angle)
		assert(
			angle > .0001 and angle < .004, "actual scene sun moves on EVERY frame, not each tick"
		)
		previous = current
	world._toggle_pause()
	var before := _states()
	var frozen: Vector3 = world.atmosphere.sun.rotation
	for frame in 10:
		await _frame()
	assert(_states() == before and world.atmosphere.sun.rotation == frozen)
	# Seasonal preview is immediate/read-only, then returns to the same frozen sun.
	for season in 5:
		world._cycle_season()
		await _frame()
		assert(_states() == before)
	assert(world.paused and world.atmosphere.sun.rotation == frozen)
	world._toggle_pause()
	await _frame()
	assert(world.atmosphere.sun.rotation != frozen, "resume continues without waiting for a tick")
	world.hud.speed_buttons[8.0].pressed.emit()
	var speed_start: float = world.water.clock
	for frame in 20:
		await _frame()
		world._check_clock_alignment()
	assert(absf(world.water.clock - speed_start - 4.0) < 1e-8, "x8 drives all models, not just UI")
	assert(world.hud.calendar_label.text.contains("Сутки 7.5 с · год 1.2 мин"))
	await world._save_frame("shared-speed-08.png")
	world.hud.speed_buttons[1.0].pressed.emit()
	world._toggle_rain()
	assert(is_equal_approx(world.atmosphere.sun.light_energy, world.atmosphere.solar_energy * .74))
	world._toggle_rain()
	assert(is_equal_approx(world.atmosphere.sun.light_energy, world.atmosphere.solar_energy))
	# Adjacent near-sunset images make the moving disk/sky inspectable as well.
	world.paused = true
	var dusk: Dictionary = world.ecology_clock.snapshot()
	dusk.ticks = 41
	dusk.pending_s = 0.0
	assert(world.ecology_clock.restore(dusk))
	world.camera.position = Vector3(256, 80, 256)
	world._process(0)
	world.camera.look_at(world.camera.position + world.atmosphere.sun.basis.z)
	for frame in 3:
		world.ecology_clock.request(.025)
		world._process(0)
		await world._save_frame("sun-smooth-%02d.png" % frame)
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"frames_checked": 80,
		"frame_step_s": .025,
		"ecology_step_s": world.settings.ecology_step_s,
		"day_water_s": world.settings.day_water_s(),
		"min_frame_angle_deg": rad_to_deg(minimum_angle),
		"max_frame_angle_deg": rad_to_deg(maximum_angle),
		"pause_freezes_models_and_sun": true,
		"preview_read_only_and_exact_return": true,
		"resume_moves_next_frame": true,
		"rain_preserves_solar_attenuation": true,
		"shared_speed_x8_water_calendar_trees_fungi": true
	}
	var file := FileAccess.open("res://artifacts/sun-check.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("SUN_CHECK ", JSON.stringify(report))
	quit()


func _frame() -> void:
	world._process(.025)
	await RenderingServer.frame_post_draw


func _states() -> Array:
	return [
		world.water.native.snapshot(),
		world.ecology_clock.snapshot(),
		world.trees.snapshot(),
		world.fungi.snapshot()
	]
