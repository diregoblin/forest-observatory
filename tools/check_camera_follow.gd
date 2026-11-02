extends RefCounted


static func run(world) -> void:
	var original: Dictionary = world._world_snapshot()
	world.paused = true
	world._view(5)
	var id: int = world.observation.selected.id
	assert(world.observation.selected.kind == &"animal")
	world.hud.observation_panel.follow_toggle.toggled.emit(true)
	assert(
		world.camera.followed_id == id and world.hud.observation_panel.follow_toggle.button_pressed
	)
	var before: Vector3 = world.camera.position
	var angle: Vector3 = world.camera.rotation
	# Change only a submitted display transform. Following must not read future model positions.
	var model_point: Vector3 = world.animals.positions[id]
	var offset := Vector3(.4, 0, .2)
	world.animals_view.displayed_transforms[id].origin += offset
	world._refresh_observation()
	assert(world.camera.position.distance_to(before + offset) < 1e-5)
	assert(world.camera.rotation == angle and world.animals.positions[id] == model_point)
	var saved: Dictionary = world._world_snapshot()
	assert(world._restore_world(saved))
	assert(world._world_snapshot() == saved, "Camera, target ID and follow anchor round-trip")
	for mode in ["target", "point", "selection"]:
		var corrupt := saved.duplicate(true)
		match mode:
			"target":
				corrupt.scene.camera_follow_id = 999999
			"point":
				corrupt.scene.camera_follow_point = Vector3(NAN, 0, 0)
			"selection":
				corrupt.scene.selection.clear()
		assert(not world._restore_world(corrupt) and world._world_snapshot() == saved)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.pressed = true
	world.camera._unhandled_input(mouse)
	assert(world.camera.followed_id == -1 and world.camera.moving)
	mouse.pressed = false
	world.camera._unhandled_input(mouse)
	world._set_camera_follow(true)
	world._view(1)
	assert(world.camera.followed_id == -1)
	world._view(5)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	key.pressed = true
	world._unhandled_input(key)
	assert(world.camera.followed_id >= 0)
	world.observation.selected = {"kind": &"plant", "id": 0}
	world._refresh_observation()
	assert(world.camera.followed_id == -1 and not world.hud.observation_panel.follow_toggle.visible)
	world._view(5)
	world._set_camera_follow(true)
	world.hud.observation_panel.close_requested.emit()
	assert(world.camera.followed_id == -1)
	world._view(5)
	world._set_camera_follow(true)
	id = world.camera.followed_id
	world.animals._die(id)
	world._refresh_observation()
	assert(world.camera.followed_id == -1, "Dead targets stop following")
	assert(world._restore_world(original))
	print(
		"CAMERA_FOLLOW_CHECK passed: display-only tracking, controls, save, cancellation and death"
	)
