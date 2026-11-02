extends SceneTree

## Full-world Forward+ integration assay. No user save is read or written.
var output_dir := "res://artifacts/pixel-style"
var world
var report := {"passed": false, "captures": [], "resizes": []}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pixel-output="):
			output_dir = arg.trim_prefix("--pixel-output=")
	DirAccess.make_dir_recursive_absolute(output_dir)
	create_timer(45).timeout.connect(
		func():
			push_error("Pixel style integration assay timed out")
			quit(1)
	)
	_run.call_deferred()


func capture(label: String) -> void:
	for frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output_dir.path_join(label + ".png")) == OK)
	report.captures.append(label)


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = root.get_final_transform() * point
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _run() -> void:
	root.size = Vector2i(1440, 900)
	world = load("res://main.tscn").instantiate()
	root.add_child(world)
	world.capture_dir = ""
	world.paused = true
	world.hud.set_paused(true)
	world._finish_model_work(true)
	var style = world.painterly_style
	var renderer = style.pixel_renderer
	assert(RenderingServer.get_current_rendering_method() == "forward_plus")
	report.renderer = RenderingServer.get_current_rendering_method()
	assert(style.mode == style.Mode.PIXEL and root.disable_3d)
	assert(renderer.viewport.world_3d == root.world_3d)
	assert(renderer.viewport.size == Vector2i(480, 300))
	# Freeze only after the first completed draw, including scene _process callbacks.
	await RenderingServer.frame_post_draw
	world._finish_model_work(true)
	var original: Dictionary = world._world_snapshot()
	await capture("01-valley-pixel")
	# Real key routing and exact reversible model state, not direct shader calls.
	await key(KEY_F8)
	assert(style.mode == style.Mode.BASELINE and not root.disable_3d)
	await capture("02-valley-baseline")
	await key(KEY_F8)
	assert(style.mode == style.Mode.PAINTERLY and not root.disable_3d)
	await capture("03-valley-painterly")
	await click(world.hud.options_button.get_global_rect().get_center())
	assert(world.hud.options_overlay.visible)
	await click(world.hud.style_button.get_global_rect().get_center())
	await key(KEY_ESCAPE)
	assert(not world.hud.options_overlay.visible)
	assert(style.mode == style.Mode.PIXEL and root.disable_3d)
	assert(
		world._world_snapshot() == original,
		"Style switching must preserve all models and scene state"
	)

	report.switching_preserves_world = true
	world.camera.view(2)
	await capture("04-creek-pixel")
	style.set_mode(style.Mode.PAINTERLY)
	await capture("05-creek-painterly")
	style.set_mode(style.Mode.PIXEL)
	# A genuinely visible animal face through the actual GUI input path.
	assert(await world._showcase(&"animal", 0), "Pixel-grid mouse selects the shown animal")
	await capture("06-animal-picked")
	await key(KEY_C)
	assert(world.camera.followed_id == 0)
	assert(renderer.render_camera.global_transform.is_equal_approx(world.camera.global_transform))
	report.mouse_selection_and_follow = true
	await key(KEY_ESCAPE)
	assert(world.hud.options_overlay.visible and world.camera.followed_id == -1)
	await key(KEY_ESCAPE)
	world.observation.selected.clear()
	world._refresh_observation()
	# Odd-sized window forces letterboxing; test projection against the render pixel.
	for dimensions in [Vector2i(1381, 865), Vector2i(1920, 1080), Vector2i(1440, 900)]:
		root.size = dimensions
		for frame in 3:
			await process_frame
		var point: Vector3 = world.camera.position - world.camera.global_basis.z * 10
		var pixel: Vector2 = renderer.screen_position(point)
		assert(renderer.contains_screen_point(pixel))
		assert(
			(
				renderer.ray_normal(pixel).dot((point - renderer.ray_origin(pixel)).normalized())
				> .9999
			)
		)
		assert(Vector2i(renderer.image.size) == renderer.viewport.size * renderer.pixel_scale)
		assert(root.size == dimensions)
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().get_size() == dimensions)
		assert(
			(
				renderer.viewport.size
				== Vector2i(
					dimensions.x / renderer.pixel_scale, dimensions.y / renderer.pixel_scale
				)
			)
		)
		assert(
			(root.get_final_transform() * renderer.output.transform).is_equal_approx(
				Transform2D.IDENTITY
			)
		)
		assert(
			await world._showcase(&"animal", 0),
			"Mouse selection survives canvas stretch and letterboxing"
		)
		await capture("resize-%dx%d" % [dimensions.x, dimensions.y])
		report.resizes.append(
			{
				"window": str(root.size),
				"logical_canvas": str(root.get_visible_rect().size),
				"world": str(renderer.viewport.size),
				"scale": renderer.pixel_scale
			}
		)
	await capture("07-resize-restored")
	world.observation.selected.clear()
	world._refresh_observation()
	world.camera.view(2)
	await process_frame
	var before_position: Vector3 = world.camera.position
	var before_rotation: Vector3 = world.camera.rotation
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.position = Vector2(720, 480)
	mouse.pressed = true
	Input.parse_input_event(mouse)
	await process_frame
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(55, -12)
	Input.parse_input_event(move)
	var forward := InputEventKey.new()
	forward.keycode = KEY_W
	forward.physical_keycode = KEY_W
	forward.pressed = true
	Input.parse_input_event(forward)
	for frame in 24:
		await process_frame
		if frame % 4 == 0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(
				output_dir.path_join("motion-%02d.png" % (frame / 4))
			)
	forward = forward.duplicate()
	forward.pressed = false
	Input.parse_input_event(forward)
	mouse = mouse.duplicate()
	mouse.pressed = false
	Input.parse_input_event(mouse)
	await process_frame
	assert(world.camera.position.distance_to(before_position) > .1)
	assert(world.camera.rotation.distance_to(before_rotation) > .01)
	assert(renderer.render_camera.global_transform.is_equal_approx(world.camera.global_transform))
	report.camera_input_and_render_sync = true
	report.viewport_timings_ms = renderer.frame_times()
	world.camera.view(1)
	world.season_preview = 4
	world.atmosphere.set_season(world._display_climate())
	world.vegetation.refresh_trees(world._display_climate())
	await capture("08-autumn-pixel")
	world.season_preview = 1
	world.atmosphere.set_season(world._display_climate())
	world.vegetation.refresh_trees(world._display_climate())
	await capture("08b-winter-pixel")
	world.season_preview = 0
	world.set_process(false)
	var night := ForestClimate.sample(0, 180, world.settings.latitude_deg, 0)
	world.atmosphere.set_season(night)
	world.hud.calendar_label.text = "Превью освещения · 00:00"
	await capture("09-night-pixel")
	assert(world.atmosphere.solar_energy == 0)
	world.set_process(true)
	world.atmosphere.set_season(world._display_climate())
	# World reload rebuilds view batches; the style must follow those materials.
	assert(world._restore_world(original))
	await capture("10-reloaded-pixel")
	for material in style.original_shaders:
		assert(material.shader == style.pixel_shader)
	report.reload_keeps_style = true
	report.passed = true
	report.boundary = (
		"Full current forest, isolated Xvfb Forward+; input through Input.parse_input_event. "
		+ "No physical keyboard, population balance, identical RE:Skob rendering or performance claim."
	)
	FileAccess.open(output_dir.path_join("visual.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("PIXEL_STYLE_CHECK ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit()
