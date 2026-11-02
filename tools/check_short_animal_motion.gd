extends "res://tools/check_animals.gd"


func _run() -> void:
	var world := chamber()
	var animals: ForestAnimals = world.animals
	var food: Vector3 = world.plants.positions[0]
	animals.positions[0] = food - Vector3(1.2, 0, 0)
	animals.positions[0].y = animals.land.height_at(animals.positions[0].x, animals.positions[0].z)
	animals.previous_positions[0] = animals.positions[0]
	animals.biomass_c[0] = 1.05
	animals.routines[0] = "forage"
	animals.step(animals.land.settings.ecology_step_s * animals.land.settings.year_speed_multiplier)
	assert(animals.actions[0] == "eat", "Fixture must arrive at nearby food within one tick")
	var frozen := animals.snapshot()
	var view := ForestAnimalsView.new()
	root.add_child(view)
	view.configure(animals)
	var frame := view.capture_frame()
	var body: Dictionary = frame.bodies[0]
	assert(body.clip == "feed")
	var moving_segments := 0
	var stopped_segments := 0
	for segment in range(1, body.points.size()):
		var alpha: float = (body.times[segment - 1] + body.times[segment]) * .5 / body.times[-1]
		view.advance_display(frame, alpha, true)
		var moved: bool = body.points[segment].distance_to(body.points[segment - 1]) > .00001
		var expected := "hop" if moved else "feed"
		assert(
			view.animation_clips[0] == expected,
			"Locomotion must follow the sampled path, not the final action"
		)
		assert(
			(
				view.displayed_transforms[0].origin.distance_to(animals.display_position(0, alpha))
				< .00001
			)
		)
		assert(
			view.animation_poses[0] == ForestAnimalMotion.sample(expected, view.animation_times[0])
		)
		assert(view.animation_players[0].current_animation == expected)
		moving_segments += int(moved)
		stopped_segments += int(not moved)
	assert(moving_segments > 0 and stopped_segments > 0)
	var previous: Vector3 = body.points[0]
	for sample in 101:
		view.advance_display(frame, sample / 100.0, true)
		var shown: Vector3 = view.displayed_transforms[0].origin
		assert(shown.distance_to(previous) < .015, "Short approach has no position teleport")
		previous = shown
		for channel in ForestAnimalMotion.curves.channels.size():
			var uniform: String = "pose_" + ForestAnimalMotion.curves.channels[channel]
			assert(
				(
					absf(
						(
							view.batches[0].get_instance_shader_parameter(uniform)
							- view.animation_poses[0][channel]
						)
					)
					< .00001
				)
			)
	if DisplayServer.get_name() != "headless":
		await _preview(view, frame, food)
	# Known-wrong old policy: the final feeding clip suppresses every moving hop.
	assert(body.clip != "hop", "Regression must reject final-action-only playback")
	# Resource-driven gait, not a hare identity exception; older buffers still load.
	body.travel_clip = "walk"
	assert(ForestAnimalsView._display_clip(body, .01) == "walk")
	assert(ForestAnimalsView.valid_frame(frame, 1))
	body.travel_clip = "not_a_clip"
	assert(not ForestAnimalsView.valid_frame(frame, 1))
	body.erase("travel_clip")
	assert(ForestAnimalsView.valid_frame(frame, 1))
	assert(animals.snapshot() == frozen)
	var report := {
		"passed": true,
		"moving_segments": moving_segments,
		"feeding_segments": stopped_segments,
		"negative_control_final_action_rejected": true,
		"unchanged_model": true
	}
	(
		FileAccess
		. open("res://artifacts/short-animal-motion-check.json", FileAccess.WRITE)
		. store_string(JSON.stringify(report, "  "))
	)
	print("SHORT_ANIMAL_MOTION ", JSON.stringify(report))
	view.free()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	quit()


func _preview(view: ForestAnimalsView, frame: Dictionary, food: Vector3) -> void:
	root.size = Vector2i(960, 600)
	Engine.max_fps = 15
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := ForestAtmosphere.new()
	stage.add_child(environment)
	environment.configure()
	environment.set_season(ForestClimate.sample(0, 155, 60, 12))
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_mesh.mesh = plane
	floor_mesh.position = food
	stage.add_child(floor_mesh)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.25, .32, .12)
	floor_mesh.material_override = material
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	environment.attach_observer(camera)
	camera.position = food + Vector3(1.1, 1.0, 2.0)
	camera.look_at(food + Vector3(-.7, .35, 0))
	DirAccess.make_dir_recursive_absolute("res://artifacts/short-animal-motion")
	var old_model: ForestAnimals = view.model
	view.model = null
	for alpha in [.08, .22, .40, .85]:
		view.advance_display(frame, alpha, true)
		var t: float = view.animation_times[0]
		for before in [true, false]:
			if before:
				view._animate(0, "feed", t)
			else:
				view.advance_display(frame, alpha, true)
			for draw in 4:
				await RenderingServer.frame_post_draw
			var filename := (
				"res://artifacts/short-animal-motion/%.2f-%s.png"
				% [alpha, "before" if before else "after"]
			)
			assert(root.get_texture().get_image().save_png(filename) == OK)
	view.model = old_model
	stage.free()
	await RenderingServer.frame_post_draw
