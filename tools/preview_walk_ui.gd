extends SceneTree

var world
var output := "res://artifacts/walk-ui"
var report := {"passed": false, "captures": [], "busy_worker_frames": 0}


func _initialize() -> void:
	create_timer(100).timeout.connect(func(): quit(1))
	_run.call_deferred()


func native_key(name: String, down: bool) -> void:
	# OS input on preview_isolated.sh's disposable X server, never Pavel's desktop.
	var code := """
import ctypes as c, sys
x=c.CDLL('libX11.so.6'); t=c.CDLL('libXtst.so.6')
x.XOpenDisplay.restype=c.c_void_p
x.XStringToKeysym.argtypes=[c.c_char_p]; x.XStringToKeysym.restype=c.c_ulong
x.XKeysymToKeycode.argtypes=[c.c_void_p,c.c_ulong]; x.XKeysymToKeycode.restype=c.c_uint
x.XFlush.argtypes=[c.c_void_p]; x.XCloseDisplay.argtypes=[c.c_void_p]
t.XTestFakeKeyEvent.argtypes=[c.c_void_p,c.c_uint,c.c_int,c.c_ulong]
d=x.XOpenDisplay(None); assert d
k=x.XKeysymToKeycode(d,x.XStringToKeysym(sys.argv[1].encode())); assert k
t.XTestFakeKeyEvent(d,k,int(sys.argv[2]),0); x.XFlush(d); x.XCloseDisplay(d)
"""
	assert(OS.execute("python3", PackedStringArray(["-c", code, name, str(int(down))])) == 0)
	for frame in 3:
		await process_frame


func key(name: String) -> void:
	await native_key(name, true)
	await native_key(name, false)


func mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = root.get_final_transform() * point
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame


func click(point: Vector2) -> void:
	await mouse(point, MOUSE_BUTTON_LEFT, true)
	await mouse(point, MOUSE_BUTTON_LEFT, false)


func capture(label: String) -> void:
	for frame in 8:
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)
	report.captures.append(label)


func models() -> PackedByteArray:
	var state := {}
	for name in world._world_models():
		state[name] = world._world_models()[name].snapshot()
	return var_to_bytes(state)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1440, 900)
	world = load("res://main.tscn").instantiate()
	world.paused = true
	root.add_child(world)
	world.capture_dir = ""  # Disable preview.sh's unrelated automated camera tour.
	world._process(0)  # Publish the initial committed frame before freezing the fixture.
	world.set_process(false)
	world.hud.set_paused(true)
	Engine.max_fps = 30
	world._finish_model_work(true)
	var frozen := models()
	await capture("01-clean-interface")
	# Native held W moves without any mouse capture or RMB modifier.
	var before: Vector3 = world.camera.position
	await native_key("w", true)
	await create_timer(.25).timeout
	await native_key("w", false)
	assert(world.camera.position.distance_to(before) > .3)
	assert(not world.camera.moving and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	report["wasd_without_rmb"] = true
	var text_entry := LineEdit.new()
	text_entry.position = Vector2(450, 250)
	text_entry.size = Vector2(220, 34)
	root.add_child(text_entry)
	text_entry.grab_focus()
	before = world.camera.position
	await key("w")
	assert(text_entry.text == "w" and world.camera.position == before)
	text_entry.queue_free()
	await process_frame
	report["text_entry_blocks_navigation"] = true

	# Menus stop physical polling, not just unhandled key events.
	await click(world.hud.options_button.get_global_rect().get_center())
	assert(world.hud.options_overlay.visible)
	before = world.camera.position
	await native_key("w", true)
	await create_timer(.2).timeout
	await native_key("w", false)
	assert(world.camera.position == before)
	await key("Escape")
	assert(not world.hud.options_overlay.visible)
	world._view(2)
	await click(world.hud.view_selector.get_global_rect().get_center())
	assert(world.hud.view_selector.get_popup().visible)
	before = world.camera.position
	await native_key("w", true)
	await native_key("w", false)
	assert(world.camera.position == before)
	for item in world.hud.view_selector.get_popup().get_item_count():
		await key("Down")
		var focused: int = world.hud.view_selector.get_popup().get_focused_item()
		if focused >= 0 and world.hud.view_selector.get_popup().get_item_id(focused) == 1002:
			break
	await key("Return")
	assert(world.camera.walking, "Native camera menu selects walking")
	assert(
		absf(world.camera.position.y - world.camera.ground_at(world.camera.position) - 1.7) < .0001
	)
	await capture("02-walking-at-stream")
	before = world.camera.position
	await native_key("d", true)
	await create_timer(.2).timeout
	await native_key("d", false)
	assert(world.camera.position.distance_to(before) > .1)
	assert(
		absf(world.camera.position.y - world.camera.ground_at(world.camera.position) - 1.7) < .0001
	)
	report["walking_and_modal_input"] = true

	# Escape opens the modal and releases a held look capture; release is not lost.
	await mouse(Vector2(600, 400), MOUSE_BUTTON_RIGHT, true)
	assert(world.camera.moving)
	await key("Escape")
	assert(world.hud.options_overlay.visible and not world.camera.moving)
	await mouse(Vector2(700, 400), MOUSE_BUTTON_RIGHT, false)
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	await capture("03-menu")
	await key("Escape")
	var saved: Dictionary = world._world_snapshot()
	await key("p")
	assert(not world.camera.walking)
	assert(world._restore_world(saved) and world.camera.walking)
	assert(models() == frozen, "All paused UI interactions preserve authoritative model bytes")
	report["model_bytes_unchanged"] = true

	# Selection detail is scroll-bounded, not a full-height obstruction.
	world._view(5)
	var panel = world.hud.observation_panel
	for frame in 3:
		await process_frame
	await click(panel.details_toggle.get_global_rect().get_center())
	await capture("04-observation-detail")
	assert(panel.details.visible)
	assert(panel.get_global_rect().end.y <= root.get_visible_rect().size.y - 99)
	root.size = Vector2i(1050, 680)
	await capture("05-small-window")
	assert(panel.get_global_rect().end.y <= root.get_visible_rect().size.y - 99)
	assert(panel.scroll.get_v_scroll_bar().visible)
	report["bounded_detail_at_two_sizes"] = true
	# Restore the scene before running actual busy-worker frames.
	root.size = Vector2i(1440, 900)
	assert(world._restore_world(saved))
	world.paused = false
	world.set_process(true)
	world.hud.set_paused(false)
	await native_key("a", true)
	for frame in 50:
		await process_frame
		if world.model_work_active:
			report.busy_worker_frames += 1
	await native_key("a", false)
	world._finish_model_work(true)
	world.paused = true
	world.hud.set_paused(true)
	assert(report.busy_worker_frames > 0)
	await capture("06-live-walk")
	report.passed = true
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("WALK_UI ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit()
