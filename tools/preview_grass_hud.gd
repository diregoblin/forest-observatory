extends SceneTree

## Actual GUI routing and paired, paused presentation checks. No user saves.
var world
var output := "res://artifacts/grass-hud-render"
var baseline_source := ""
var report := {"passed": false, "captures": [], "paired_render": []}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--grass-baseline-source="):
			baseline_source = arg.trim_prefix("--grass-baseline-source=")
	create_timer(70).timeout.connect(func(): quit(1))
	_run.call_deferred()


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


func native_popup_key(keysym: String) -> void:
	# PopupMenu handles native Window input, not root Viewport.push_input.
	# XTest is scoped to the disposable DISPLAY supplied by preview_isolated.sh.
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
for pressed in (1,0): t.XTestFakeKeyEvent(d,k,pressed,0)
x.XFlush(d); x.XCloseDisplay(d)
"""
	assert(OS.execute("python3", PackedStringArray(["-c", code, keysym])) == 0)
	for frame in 3:
		await RenderingServer.frame_post_draw


func click(point: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = root.get_final_transform() * point
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func models() -> PackedByteArray:
	var state := {}
	for name in world._world_models():
		state[name] = world._world_models()[name].snapshot()
	return var_to_bytes(state)


func capture(label: String) -> void:
	for frame in 8:
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)
	report.captures.append(label)


func timings(label: String) -> void:
	var samples := []
	for frame in 12:
		await RenderingServer.frame_post_draw
		samples.append(world.painterly_style.pixel_renderer.frame_times().gpu_ms)
	samples.sort()
	report.paired_render.append(
		{
			"label": label,
			"gpu_ms_median": samples[samples.size() / 2],
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		}
	)


func tab(index: int) -> void:
	var tabs: TabBar = world.hud.options_tabs.get_tab_bar()
	await click(tabs.global_position + tabs.get_tab_rect(index).get_center())
	assert(world.hud.options_tabs.current_tab == index)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1440, 900)
	world = load("res://main.tscn").instantiate()
	world.paused = true
	root.add_child(world)
	assert(not world.painterly_style.debug_controls_enabled and not world.hud.style_button.visible)
	var normal_mode: int = world.painterly_style.mode
	await key(KEY_F8)
	assert(world.painterly_style.mode == normal_mode, "Hidden renderer modes must ignore F8")
	world.painterly_style.debug_controls_enabled = true
	world.hud.style_button.show()  # Deliberate developer-only renderer exercise.
	world._finish_model_work(true)
	world.set_process(false)
	world.camera.set_process(false)
	world.hud.set_paused(true)
	Engine.max_fps = 30
	world._refresh_hud()
	var frozen := models()
	assert(not world.hud.options_overlay.visible)
	assert(not world.hud.info.is_visible_in_tree())
	assert(not world.hud.journal.is_visible_in_tree())
	assert(not world.hud.style_button.is_visible_in_tree())
	await capture("01-clean-valley")
	await click(world.hud.options_button.get_global_rect().get_center())
	assert(world.hud.options_overlay.visible)
	assert(world.hud.style_button.is_visible_in_tree())
	await capture("02-options-graphics")
	# Real menu clicks, not direct signal emission. World hotkeys stay modal.
	var old_mode: int = world.painterly_style.mode
	for index in 3:
		await click(world.hud.style_button.get_global_rect().get_center())
	assert(world.painterly_style.mode == old_mode)
	await click(world.hud.frame_limit_button.get_global_rect().get_center())
	assert(Engine.max_fps == 60)
	await click(world.hud.frame_limit_button.get_global_rect().get_center())
	assert(Engine.max_fps == 30)
	await key(KEY_SPACE)
	assert(world.paused)
	await key(KEY_B)
	assert(not world.barrier_enabled)
	var selection: Dictionary = world.observation.selected.duplicate()
	await click(Vector2(80, 240))
	assert(world.observation.selected == selection)
	await click(Vector2(80, 240), MOUSE_BUTTON_RIGHT)
	assert(not world.camera.moving and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	await tab(1)
	await capture("03-options-world")
	await tab(2)
	assert(world.hud.info.is_visible_in_tree())
	await capture("04-options-observations")
	await tab(3)
	await capture("05-options-controls")
	await key(KEY_ESCAPE)
	assert(not world.hud.options_overlay.visible)
	await key(KEY_ESCAPE)
	assert(world.hud.options_overlay.visible)
	await key(KEY_ESCAPE)
	assert(not world.hud.options_overlay.visible)
	assert(models() == frozen, "Menu must preserve all eight authoritative models")
	# The new viewpoint dropdown must work through its real popup keyboard path.
	world.camera.view(2)
	var creek_camera: Vector3 = world.camera.position
	await click(world.hud.view_selector.get_global_rect().get_center())
	var popup: PopupMenu = world.hud.view_selector.get_popup()
	assert(popup.visible)
	for item in popup.get_item_count():
		await native_popup_key("Down")
		if popup.get_item_id(popup.get_focused_item()) == 1:
			break
	assert(popup.get_item_id(popup.get_focused_item()) == 1)
	await native_popup_key("Return")
	assert(world.camera.position != creek_camera)
	assert(not popup.visible)
	await click(world.hud.view_selector.get_global_rect().get_center())
	# Arrow navigation also establishes native popup focus after reopening.
	for item in popup.get_item_count():
		await native_popup_key("Down")
		if popup.get_focused_item() == popup.get_item_count() - 1:
			break
	assert(popup.get_item_text(popup.get_focused_item()).ends_with("Тихий ключ"))
	await native_popup_key("Return")
	assert(not popup.visible and world.observation.selected.is_empty())
	var head: Vector2 = world.land.spring_position()
	assert(Vector2(world.camera.position.x, world.camera.position.z).distance_to(head) < 30)
	await key(KEY_M)
	assert(not world.hud.soil_layers.visible and not world.hud.fungi_map.visible)
	# Map buttons close the modal menu and reveal the requested overlay.
	for index in 2:
		await click(world.hud.options_button.get_global_rect().get_center())
		await tab(2)
		var page: ScrollContainer = world.hud.options_tabs.get_tab_control(2)
		var map_buttons: HBoxContainer = page.get_child(0).get_child(0)
		var button: Button = map_buttons.get_child(index)
		await click(button.get_global_rect().get_center())
		assert(not world.hud.options_overlay.visible)
		var layers := [world.hud.fungi_map, world.hud.soil_layers]
		assert(layers[index].visible)
		await key([KEY_G, KEY_V][index])
		assert(not layers[index].visible)
	assert(models() == frozen)
	report.menu_input = "mouse, tab clicks, Esc, no world picking/flight/hotkey leakage"
	# Same live masks, camera, wind and models; previous card implementation is
	# loaded only from our task rollback, without registering a second class_name.
	var old_cards
	if not baseline_source.is_empty():
		var previous := GDScript.new()
		previous.source_code = FileAccess.get_file_as_string(baseline_source).replace(
			"class_name ForestTurfCards\n", ""
		)
		assert(previous.reload() == OK)
		old_cards = previous.new()
		world.add_child(old_cards)
		old_cards.configure(
			world.terrain, world.camera, world.vegetation, world.water_view, world.painterly_style
		)
		old_cards.material.set_shader_parameter("view_distance", 18.0)
		old_cards.set_process(false)
	world.turf_cards.set_process(false)
	var point := Vector3(200, world.terrain.data.get_surface_height(Vector3(200, 0, 196)), 196)
	world.camera.position = point + Vector3(1.5, 1.1, 2.5)
	world.camera.look_at(point + Vector3(0, .24, 0))
	var build_us := []
	for frame in 45:
		if old_cards != null:
			old_cards._process(0)
		var before: int = world.turf_cards.patches.size()
		var started := Time.get_ticks_usec()
		world.turf_cards._process(0)
		build_us.append(Time.get_ticks_usec() - started)
		assert(world.turf_cards.patches.size() - before <= 3)
	for key_offset in world.turf_cards.tile_offsets:
		var center := Vector2i(
			floori(world.camera.position.x / 8), floori(world.camera.position.z / 8)
		)
		var candidate: Vector2i = center + key_offset
		assert(
			(
				not world.turf_cards._tile_in_range(candidate)
				or world.turf_cards.patches.has(candidate)
			)
		)
	assert(world.turf_cards.patches.size() <= 121)
	var nearest: MultiMesh = world.turf_cards.patches.values()[0].multimesh
	assert(nearest.instance_count == 676)
	assert(is_equal_approx(world.turf_cards.card_mesh.get_aabb().size.y, .4))
	var fixed_buffer := nearest.buffer.duplicate()
	world.camera.rotate_y(.1)
	world.turf_cards._process(0)
	assert(nearest.buffer == fixed_buffer, "Camera never turns anchored grass into billboards")
	world.camera.look_at(point + Vector3(0, .24, 0))
	if old_cards != null:
		world.turf_cards.hide()
		old_cards.show()
		await capture("06-grass-previous")
		await timings("previous-density18-height32-distance18")
		old_cards.hide()
	world.turf_cards.show()
	await capture("07-grass-denser")
	await timings("new-density26-height40-distance36")
	var steady_us := []
	for frame in 20:
		var started := Time.get_ticks_usec()
		world.turf_cards._process(0)
		steady_us.append(Time.get_ticks_usec() - started)
	steady_us.sort()
	for mode in [0, 1]:
		world.painterly_style.set_mode(mode)
		await capture("08-grass-style-%d" % mode)
	world.painterly_style.set_mode(2)
	# Options remain on screen with a smaller/wide window, not clipped panels.
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dimensions
		world.hud.set_options_open(true)
		await capture("09-options-%dx%d" % [dimensions.x, dimensions.y])
		var menu: Rect2 = world.hud.options_tabs.get_global_rect()
		assert(root.get_visible_rect().encloses(menu))
	world.hud.set_options_open(false)
	root.size = Vector2i(1440, 900)
	assert(models() == frozen)
	build_us.sort()
	report.grass = {
		"density_ratio": 676.0 / 324.0,
		"height_ratio": .4 / .32,
		"draw_distance_m": 36,
		"loaded_patches": world.turf_cards.patches.size(),
		"patch_build_max_us": build_us[-1],
		"tile_load_frame_median_us": build_us[build_us.size() / 2],
		"steady_process_median_us": steady_us[steady_us.size() / 2],
		"fixed_world_cards": true,
		"models_unchanged": true
	}
	report.passed = true
	report.boundary = (
		"Short paused Forward+ preview; not sustained FPS or thermal validation."
		+ " No user saves."
	)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("GRASS_HUD_RENDER ", JSON.stringify(report))
	world.free()
	quit()
