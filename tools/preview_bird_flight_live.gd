extends "res://tools/preview_ground_turf.gd"


func _initialize() -> void:
	output = "res://artifacts/bird-flight-live"
	super._initialize()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene._finish_model_work(true)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.hud.visible = false
	scene.camera.near = .02
	scene.use_model_worker = false
	Engine.max_fps = 20
	for tick in 3:
		scene._advance_world(scene.settings.ecology_step_s)
		scene._capture_presentation()
	var frame: Dictionary = scene.presentation_frames[-1]
	var bird := -1
	for id in frame.bodies.size():
		var b: Dictionary = frame.bodies[id]
		if b.travel_clip == "fly" and b.points[0].distance_to(b.points[-1]) > .01:
			bird = id
			break
	assert(bird >= 0, "Need a real committed moving bird, not a fabricated trajectory")
	var frozen := model_bytes()
	var view = scene.animals_view
	var model = view.model
	view.model = null  # Exercise the same detached read path used while worker is busy.
	var poses := []
	for sample in 5:
		view.advance_display(frame, sample / 4.0, true)
		var shape: Dictionary = view.selection_shape(bird)
		var bounds: AABB = shape.bounds
		var point := bounds.get_center()
		scene.camera.position = point + Vector3(.75, .25, .95)
		scene.camera.look_at(point)
		poses.append(
			{
				"clip": view.animation_clips[bird],
				"flight": view.animation_poses[bird][7],
				"position": str(view.displayed_transforms[bird].origin)
			}
		)
		await photo("flight-%d" % sample, true)
	view.model = model
	assert(poses.any(func(p): return p.clip == "fly" and p.flight > .99))
	assert(model_bytes() == frozen)
	var report := {
		"passed": true,
		"real_committed_path": true,
		"view_detached_from_model": true,
		"unchanged_models_during_display": true,
		"id": bird,
		"samples": poses
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("BIRD_FLIGHT_LIVE PASS ", JSON.stringify(report))
	scene.free()
	quit()
