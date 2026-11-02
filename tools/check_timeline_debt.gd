extends SceneTree

const ANIMAL_DEFINITION = preload("res://scripts/animal_definition.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var baseline := assay(false)
	var current := assay(true)
	assert(baseline.stopped > 80, "Negative control must reproduce debt-driven stepping")
	assert(current.stopped == 0, "No stopped sun between controlled worker completions")
	assert(current.maximum < baseline.maximum * .25, "Reject tick-sized solar jumps")
	assert(baseline.ripple_stopped > 80 and current.ripple_stopped == 0)
	var report := {
		"passed": true,
		"baseline": baseline,
		"current": current,
		"boundary":
		(
			"Real coupled model ticks and held workers; fixture accelerates only solar period "
			+ "to 2 s, injects 100 s request debt. Not a GPU soak or aged-ecosystem benchmark."
		)
	}
	FileAccess.open("res://artifacts/timeline-debt-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("TIMELINE_DEBT ", JSON.stringify(report))
	quit()


func assay(fixed: bool) -> Dictionary:
	var scene = (
		load("res://scripts/forest.gd" if fixed else "res://tools/fixtures/debt_playback.gd").new()
	)
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.capture_dir = ""
	scene.settings.day_speed_multiplier = ForestClimate.DAY_S / 2.0
	scene.use_model_worker = false
	for tick in 3:
		scene._advance_world(scene.settings.ecology_step_s)
		scene._capture_presentation()
	scene.use_model_worker = true
	scene.paused = false
	scene._advance_presentation(1.0)
	scene.ecology_clock.pending_s = 100.0
	var angles := []
	var phases := []
	var previous: Vector3 = scene.atmosphere.sun.basis.z
	var initial_ripple = scene.water_view.material_override.get_shader_parameter("weather_time")
	var previous_ripple := float(initial_ripple) if initial_ripple != null else 0.0
	scene.water_view.material_override.set_shader_parameter("weather_time", previous_ripple)
	for tick in 8:
		assert(scene.ecology_clock.step())
		var gate := Semaphore.new()
		scene.model_work_active = true
		scene.presentation_dispatch_wall = scene.presentation_active_wall
		assert(
			(
				scene.model_thread.start(_held_tick.bind(gate, scene, scene.ecology_clock.sample()))
				== OK
			)
		)
		var view_model = scene.animals_view.model
		var weather = scene.weather
		scene.animals_view.model = null
		scene.weather = null
		var dt: float = [.8, 1.0, .9, .85][tick % 4] / 20.0
		for frame in 20:
			scene._process(dt)
			var direction: Vector3 = scene.atmosphere.sun.basis.z
			angles.append(previous.angle_to(direction))
			previous = direction
			var ripple: float = scene.water_view.material_override.get_shader_parameter(
				"weather_time"
			)
			phases.append(ripple - previous_ripple)
			previous_ripple = ripple
			assert(scene.presentation_s <= scene.presentation_frames[-1].end_s + 1e-8)
		scene.animals_view.model = view_model
		scene.weather = weather
		gate.post()
		scene._finish_model_work(true)
	var stopped := 0
	var ripple_stopped := 0
	for value in angles:
		stopped += int(value < .000001)
	for value in phases:
		ripple_stopped += int(value < .000001)
	scene.paused = true
	var frozen: float = scene.presentation_s
	scene._process(.2)
	assert(scene.presentation_s == frozen)
	var result := {
		"frames": angles.size(),
		"stopped": stopped,
		"ripple_stopped": ripple_stopped,
		"maximum": angles.max(),
		"minimum": angles.min(),
		"angles_rad": angles,
		"ripple_steps_s": phases,
		"solar_days": scene.presentation_s / 2.0
	}
	if fixed:
		assert(check_buffer_and_rate(scene))
	scene.free()
	return result


func check_buffer_and_rate(scene) -> bool:
	# Backpressure idle is not worker cost: otherwise accelerating after x1
	# would lock playback to the old rate despite a fast producer.
	scene.paused = false
	scene.presentation_active_wall += 10.0
	scene.presentation_dispatch_wall = scene.presentation_active_wall
	assert(scene.ecology_clock.step())
	var gate := Semaphore.new()
	scene.model_work_active = true
	assert(
		scene.model_thread.start(_held_tick.bind(gate, scene, scene.ecology_clock.sample())) == OK
	)
	for frame in 20:
		scene._process(.01)
	gate.post()
	scene._finish_model_work(true)
	assert(is_equal_approx(scene.presentation_rate, 2.5), "Do not count buffer-full idle as work")
	# Build a real, full submitted buffer. Dispatch must wait for display room,
	# rather than evict a path whose beginning is still on screen.
	scene.paused = true
	scene.use_model_worker = false
	for tick in 2:
		scene._advance_world(scene.settings.ecology_step_s)
		scene._capture_presentation()
	scene.use_model_worker = true
	scene.paused = false
	scene._set_speed(8.0)
	scene.ecology_clock.pending_s = 100.0
	var before: int = scene.ecology_clock.ticks
	scene._process(.01)
	assert(not scene.model_work_active and scene.ecology_clock.ticks == before)
	for frame in 200:
		scene._process(.01)
		if scene.model_work_active:
			break
	assert(scene.model_work_active, "Backpressure must release when the display has room")
	scene._finish_model_work(true)
	var first: Dictionary = scene.presentation_frames[0]
	assert(scene.presentation_s >= first.end_s - first.step_s - 1e-8)
	scene.paused = true
	return true


func _held_tick(gate: Semaphore, scene, climate: Dictionary) -> void:
	gate.wait()
	scene._coupled_tick(climate)
