extends SceneTree

var scene
var output := "res://artifacts/smooth-motion"


func _initialize() -> void:
	_run.call_deferred()


func photo(label: String) -> void:
	scene.painterly_style._process(0)
	for frame in 4:
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.capture_step = 8
	# Prime completed paths using real coupled ticks, never invented animation.
	scene.use_model_worker = false
	for tick in 3:
		scene._advance_world(scene.settings.ecology_step_s)
		scene._capture_presentation()
	var frame: Dictionary = scene.presentation_frames[-1]
	var id := -1
	for i in frame.bodies.size():
		if frame.bodies[i].points[0].distance_to(frame.bodies[i].points[-1]) > .1:
			id = i
			break
	assert(id >= 0, "Fixture needs a genuinely moving animal")
	scene.use_model_worker = true
	scene.paused = false
	# Real model worker, held at its entry so every measured frame is busy.
	scene.ecology_clock.request(scene.settings.ecology_step_s)
	assert(scene.ecology_clock.step())
	var climate: Dictionary = scene.ecology_clock.sample()
	var gate := Semaphore.new()
	scene.model_work_active = true
	scene.presentation_dispatch_wall = scene.presentation_active_wall
	assert(scene.model_thread.start(_held_tick.bind(gate, climate)) == OK)
	scene._advance_presentation(1.0)
	var old_view_model: ForestAnimals = scene.animals_view.model
	var old_weather: ForestWeather = scene.weather
	scene.animals_view.model = null
	scene.weather = null
	var positions := []
	var sun_angles := []
	var poses := []
	var previous: Vector3 = scene.atmosphere.sun.basis.z
	for sample in 8:
		scene._process(.01)
		positions.append(scene.animals_view.displayed_transforms[id].origin)
		poses.append(scene.animals_view.animation_times[id])
		sun_angles.append(previous.angle_to(scene.atmosphere.sun.basis.z))
		previous = scene.atmosphere.sun.basis.z
		# Posed picking and follow must also use cached state, not model arrays.
		assert(not scene.animals_view.display_shape(id).is_empty())
		assert(not scene.animals_view.selection_shape(id).is_empty())
	var busy: bool = scene.model_work_active
	scene.animals_view.model = old_view_model
	scene.weather = old_weather
	gate.post()
	scene._finish_model_work(true)
	assert(busy)
	var moved := 0
	for i in range(1, positions.size()):
		moved += int(positions[i].distance_to(positions[i - 1]) > .00001)
		assert(poses[i] > poses[i - 1])
	assert(moved == 7, "An actual moving animal must move on every busy frame")
	for angle in sun_angles:
		assert(angle > .0001 and angle < .002, "Sun must move, without tick-sized jumps")
	scene.paused = true
	var frozen: Dictionary = scene._world_snapshot().models
	var point: Vector3 = scene.animals_view.displayed_transforms[id].origin
	var sun: Vector3 = scene.atmosphere.sun.rotation
	scene._process(.1)
	assert(scene._world_snapshot().models == frozen)
	assert(point == scene.animals_view.displayed_transforms[id].origin)
	assert(sun == scene.atmosphere.sun.rotation)
	# Loading a buffered live view must not jump the followed target or sun.
	scene.observation.selected = {"kind": &"animal", "id": id}
	scene._set_camera_follow(true)
	var saved: Dictionary = scene._world_snapshot()
	var save_path := output.path_join("buffered-roundtrip.bin")
	assert(ForestWorldState.write(save_path, saved) == OK)
	assert(ForestWorldState.read(save_path) == saved)
	assert(scene._restore_world(ForestWorldState.read(save_path)))
	assert(scene._world_snapshot() == saved)
	var corrupt: Dictionary = saved.duplicate(true)
	corrupt.scene.presentation.frames[0].bodies[0].points[0].x = NAN
	assert(not scene._restore_world(corrupt))
	assert(scene._world_snapshot() == saved)
	var report := {
		"passed": true,
		"busy_frames": 8,
		"moving_intervals": moved,
		"sun_frame_angles": sun_angles,
		"worker_views_need_no_model": true,
		"pause_freezes_models_and_display": true
	}
	if DisplayServer.get_name() != "headless":
		# Cross actual worker completions and dispatches, not only the held branch.
		scene.paused = false
		var previous_sun: Vector3 = scene.atmosphere.sun.basis.z
		var angles := []
		var busy_frames := 0
		for sample in 120:
			busy_frames += int(scene.model_work_active)
			scene._process(.025)
			await RenderingServer.frame_post_draw
			var direction: Vector3 = scene.atmosphere.sun.basis.z
			angles.append(previous_sun.angle_to(direction))
			previous_sun = direction
			assert(scene.presentation_s <= scene.presentation_frames[-1].end_s + 1e-8)
		scene._toggle_pause()
		for angle in angles:
			assert(
				angle > .0002 and angle < .001,
				"No stopped sun or jumps across real worker transitions at x1"
			)
		assert(busy_frames > 0)
		report.rendered_frames = 120
		report.real_worker_busy_frames = busy_frames
		report.real_worker_sun_min_angle = angles.min()
		report.real_worker_sun_max_angle = angles.max()
		scene.hud.visible = false
		Engine.max_fps = 30
		for plot in scene.fungi.plots.size():
			var p: Vector2 = scene.fungi.plots[plot].origin + Vector2.ONE * 16
			var target := Vector3(p.x, scene.land.height_at(p.x, p.y), p.y)
			scene.camera.position = target + Vector3(5, 5, 7)
			scene.camera.look_at(target)
			await photo("fungi-%d" % plot)
		# Show a bank boulder from opposite sides.
		var rock: MultiMeshInstance3D = scene.vegetation.rock_batch
		var rock_id := -1
		for k in 400:
			var candidate: Transform3D = rock.multimesh.get_instance_transform(k)
			var pos := candidate.origin
			var distance: float = absf(pos.x - scene.land.channel_x(pos.z))
			if (
				distance > 11
				and candidate.basis.x.length() > 1.2
				and scene.water.depth[scene.water.index_at(pos.x, pos.z)] < .001
			):
				rock_id = k
				break
		assert(rock_id >= 0)
		var target: Vector3 = rock.multimesh.get_instance_transform(rock_id).origin
		for mode in 3:
			scene.painterly_style.set_mode(mode)
			for side in [-1, 1]:
				scene.camera.position = target + Vector3(side * 4.0, 1.2, 4.0)
				scene.camera.position.y = maxf(
					scene.camera.position.y,
					scene.land.height_at(scene.camera.position.x, scene.camera.position.z) + 1.2
				)
				scene.camera.look_at(target + Vector3.UP * .3)
				await photo("rock-%d-%d" % [mode, side])
	(
		FileAccess
		. open(
			output.path_join(
				"headless-report.json" if DisplayServer.get_name() == "headless" else "report.json"
			),
			FileAccess.WRITE
		)
		. store_string(JSON.stringify(report, "  "))
	)
	print("SMOOTH_MOTION ", JSON.stringify(report))
	scene.free()
	quit()


func _held_tick(gate: Semaphore, climate: Dictionary) -> void:
	gate.wait()
	scene._coupled_tick(climate)
