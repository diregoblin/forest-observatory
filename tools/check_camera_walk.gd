extends RefCounted


static func run(world) -> void:
	var original: Dictionary = world._world_snapshot()
	world.paused = true
	var camera := ForestObserverCamera.new()
	world.add_child(camera)
	camera.configure(world.land, world.barrier)
	camera.current = false
	camera.set_process(false)
	camera.surface_height = func(_point: Vector3): return 20.0
	camera.position = Vector3(100, 100, 100)
	assert(camera.set_walking(true))
	assert(is_equal_approx(camera.position.y, 21.7))
	# Independent expected displacement: 2.2 horizontal metres per observer second.
	for angle in [-1.4, 0.0, 1.4]:
		for axes in [Vector3(0, 0, -1), Vector3(1, 0, -1)]:
			camera.position = Vector3(100, 21.7, 100)
			camera.rotation = Vector3(angle, .4, 0)
			for frame in 10:
				camera.move_input(axes, false, .1)
			assert(
				(
					absf(Vector2(camera.position.x - 100, camera.position.z - 100).length() - 2.2)
					< .001
				)
			)
			assert(is_equal_approx(camera.position.y, 21.7))
	var before := camera.position
	camera.move_input(Vector3.UP, false, .1)
	assert(camera.position == before, "Walking does not fly when E is pressed")
	camera.rotation = Vector3.ZERO
	camera.position = Vector3(100, 21.7, 100)
	camera.move_input(Vector3(1, 0, 0), true, 8)
	assert(absf(camera.position.x - 100.5) < .0001, "A stalled frame cannot teleport")
	# Analytical plane: reject the wrong raw-height sampler, check exact eye clearance.
	camera.surface_height = func(p: Vector3): return 20 + p.x * .25
	camera.position = Vector3(100, 0, 100)
	assert(camera.set_walking(true))
	camera.move_input(Vector3(1, 0, 0), false, .1)
	assert(absf(camera.position.y - (20 + camera.position.x * .25 + 1.7)) < .00001)
	# A steep bank must not be crossed, in either direction or by a long frame.
	camera.surface_height = func(p: Vector3): return 20 + maxf(0, p.x - 100) * 3
	camera.position = Vector3(100, 21.7, 100)
	camera.move_input(Vector3(1, 0, 0), true, 8)
	assert(camera.position.x == 100)
	camera.surface_height = func(_p: Vector3): return 20.0
	camera.water_surface = func(p: Vector3): return Vector2(22, 1) if p.x > 100 else Vector2.ZERO
	camera.move_input(Vector3(1, 0, 0), false, .1)
	assert(camera.position.x == 100, "Cannot walk into deep displayed water")
	camera.set_walking(false)
	camera.position.x = 101
	before = camera.position
	assert(not camera.set_walking(true) and not camera.walking and camera.position == before)
	camera.water_surface = func(_p: Vector3): return Vector2(20.2, 1)
	assert(camera.set_walking(true), "Shallow water remains passable")
	camera.position.x = 4.01
	camera.move_input(Vector3(-1, 0, 0), true, .1)
	assert(camera.position.x >= 4)
	camera.follow(3, Vector3.ZERO)
	assert(not camera.walking and camera.followed_id == 3)
	camera.move_input(Vector3(1, 0, 0), false, .1)
	assert(camera.followed_id == -1 and not camera.moving, "WASD leaves follow without RMB")
	camera.moving = true
	camera._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	assert(camera.controls_blocked() and not camera.moving)
	camera._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
	camera.free()
	world.camera.current = true

	# Water-stage reference: one wet corner at stage 10.1, three dry high banks.
	# Dry beds must never tilt the reconstructed stage upwards.
	var water := ForestWaterView.new()
	water.display_extent = 2
	water.bed_image = Image.create(2, 2, false, Image.FORMAT_RF)
	water.bed_image.fill(Color(999, 0, 0))
	water.bed_image.set_pixel(0, 0, Color(9.8, 0, 0))
	water.previous_image = Image.create(2, 2, false, Image.FORMAT_RF)
	water.current_image = water.previous_image.duplicate()
	water.previous_image.set_pixel(0, 0, Color(.2, 0, 0))
	water.current_image.set_pixel(0, 0, Color(.4, 0, 0))
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	material.set_shader_parameter("display_alpha", .5)
	water.material_override = material
	var stage := water.display_stage_at(Vector3(1, 0, 1))
	assert(absf(stage.x - 10.1) < .00001 and is_equal_approx(stage.y, .25))
	assert(water.display_stage_at(Vector3(1.5, 0, 1.5)) == Vector2.ZERO)
	assert(absf(water.display_stage_at(Vector3.ZERO).x - 10.1) < .00001)
	water.free()

	# Presentation controls may not change any authoritative model state.
	var saved_sampler: Callable = world.camera.water_surface
	world.camera.water_surface = func(_p: Vector3): return Vector2.ZERO
	world._set_camera_walking(true)
	assert(world.camera.walking)
	assert(world._world_snapshot().models == original.models)
	var saved: Dictionary = world._world_snapshot()
	assert(world._restore_world(saved) and world._world_snapshot() == saved)
	for corrupt_value in [1, "true"]:
		var corrupt := saved.duplicate(true)
		corrupt.scene.camera_walking = corrupt_value
		assert(not world._restore_world(corrupt) and world._world_snapshot() == saved)
	var conflict := saved.duplicate(true)
	conflict.scene.camera_follow_id = 0
	assert(not world._restore_world(conflict) and world._world_snapshot() == saved)
	var legacy := saved.duplicate(true)
	legacy.scene.erase("camera_walking")
	assert(world._restore_world(legacy) and not world.camera.walking)
	assert(world._world_snapshot().models == saved.models)
	world.camera.water_surface = saved_sampler
	assert(world._restore_world(original))
	print(
		"CAMERA_WALK_CHECK passed: geometry, slopes, water, focus, modes, legacy saves, model invariance"
	)
