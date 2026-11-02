extends "res://tools/preview_ground_turf.gd"

## Paused Forward+ A/B: native filter grain, not alpha-hashed coverage.
var rows := []


func edge_grain(image: Image) -> float:
	# High-frequency error on the independently constructed straight edge.
	# A local horizontal average follows its smooth ramp, not native tap data.
	var residual := 0.0
	var count := 0
	var radius := maxi(5, roundi(image.get_width() * 5.0 / 1440))
	for y in range(int(image.get_height() * .12), int(image.get_height() * .82), 2):
		for x in range(int(image.get_width() * .28), int(image.get_width() * .56), 2):
			var mean := 0.0
			for dx in range(-radius, radius + 1):
				var c := image.get_pixel(x + dx, y)
				mean += (c.r + c.g + c.b) / (3.0 * (2 * radius + 1))
			if mean > .15 and mean < .65:
				var c := image.get_pixel(x, y)
				residual += pow((c.r + c.g + c.b) / 3.0 - mean, 2)
				count += 1
	assert(count > 1000, "The known straight penumbra must be inside the measurement ROI")
	return sqrt(residual / count)


func _initialize() -> void:
	output = "res://artifacts/cloud-shadow-filter"
	create_timer(90).timeout.connect(func(): quit(1))
	_run.call_deferred()


func capture(label: String, quality: int) -> Image:
	if quality >= 0:
		scene.atmosphere.set_shadow_filter_quality(quality)
	scene.painterly_style._process(0)
	for frame in 8:
		await RenderingServer.frame_post_draw
	var gpu := []
	for frame in 20:
		await RenderingServer.frame_post_draw
		assert(DisplayServer.window_can_draw())
		gpu.append(scene.painterly_style.pixel_renderer.frame_times().gpu_ms)
	gpu.sort()
	var image := root.get_texture().get_image()
	assert(image.save_png(output.path_join(label + ".png")) == OK)
	rows.append(
		{
			"label": label,
			"quality": scene.atmosphere.shadow_filter_quality,
			"gpu_ms_p50": gpu[10],
			"gpu_ms_samples": gpu,
			"pixel_grid": scene.painterly_style.pixel_renderer.viewport.size,
			"image_size": image.get_size()
		}
	)
	print("SHADOW_FILTER ", JSON.stringify(rows[-1]))
	return image


func press_key(code: Key, target: Window) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.window_id = target.get_window_id()
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func select_quality(index: int) -> bool:
	scene.hud.visible = true
	scene.hud.set_options_open(true)
	for frame in 3:
		await RenderingServer.frame_post_draw
	var selector: OptionButton = scene.hud.shadow_quality_selector
	selector.grab_focus()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = root.get_final_transform() * selector.get_global_rect().get_center()
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	if not selector.get_popup().visible:
		push_error("Shadow quality popup must open through actual GUI input")
		return false
	# PopupMenu supports directional navigation, not the ui_home action.
	for step in selector.item_count + 1:
		if selector.get_popup().get_focused_item() == 0:
			break
		await press_key(KEY_DOWN, selector.get_popup())
	for step in index:
		await press_key(KEY_DOWN, selector.get_popup())
	await press_key(KEY_ENTER, selector.get_popup())
	print(
		"GUI_SHADOW_QUALITY ",
		index,
		" selected=",
		selector.selected,
		" applied=",
		scene.atmosphere.shadow_filter_quality
	)
	if (
		selector.selected != index
		or scene.atmosphere.shadow_filter_quality != selector.get_selected_id()
	):
		push_error("Selected shadow quality must reach the atmosphere")
		return false
	scene.hud.set_options_open(false)
	scene.hud.visible = false
	return true


func _run() -> void:
	assert(RenderingServer.get_current_rendering_method() == "forward_plus")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1200, 750)
	Engine.max_fps = 30
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene._finish_model_work(true)
	scene.capture_dir = ""
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.atmosphere.set_process(false)
	scene.hud.visible = false
	var frozen := model_bytes()
	var default_quality: int = ProjectSettings.get_setting(
		"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"
	)
	print("DEFAULT_DIRECTIONAL_SHADOW_QUALITY ", default_quality)
	assert(scene.hud.shadow_quality_selector.get_selected_id() == default_quality)
	var climate := ForestClimate.sample(0, 155, 60, 12)
	climate.cloud_cover = .65
	climate.weather_time_s = 180.0
	climate.sun_elevation = deg_to_rad(45)
	scene.atmosphere.set_season(climate)
	scene.atmosphere.rain_particles.emitting = false
	scene.painterly_style.set_mode(2)
	for view in [] if OS.get_cmdline_user_args().has("--ui-only") else [1, 0]:
		if view == 1:
			scene.camera.view(1)
		else:
			var point := Vector3(200, scene.land.height_at(200, 196), 196)
			scene.camera.position = point + Vector3(3, 2, 4)
			scene.camera.look_at(point + Vector3(0, .5, 0))
		for q in [2, 5, 2, 5, 2, 5]:
			await capture("forest-%d-q%d-%d" % [view, q, rows.size()], q)
	for index in 4:
		if not await select_quality(index):
			quit(1)
			return
		var selected: int = scene.atmosphere.shadow_filter_quality
		scene.atmosphere.set_cloud_shadows_enabled(false)
		scene.atmosphere.set_cloud_shadows_enabled(true)
		scene.painterly_style.set_mode(1)
		scene.painterly_style.set_mode(2)
		assert(scene.atmosphere.shadow_filter_quality == selected)
	scene.hud.visible = true
	scene.hud.set_options_open(true)
	await capture("options", -1)
	if OS.get_cmdline_user_args().has("--ui-only"):
		assert(model_bytes() == frozen)
		scene.free()
		quit()
		return
	scene.hud.set_options_open(false)
	scene.hud.visible = false
	# Known straight edge: no material/noise/vegetation texture can hide grain.
	scene.atmosphere.set_volumetric_enabled(false)
	var env: Environment = scene.atmosphere.world_env
	env.ambient_light_energy = 0
	env.fog_enabled = false
	env.glow_enabled = false
	env.ssao_enabled = false
	scene.atmosphere.sun.light_energy = 1
	for view in [
		scene.terrain,
		scene.vegetation,
		scene.animals_view,
		scene.turf_cards,
		scene.habitat_view,
		scene.fungi_view,
		scene.water_view,
		scene.dam_view
	]:
		view.visible = false
	scene.turf_cards.set_process(false)
	scene.painterly_style.set_process(false)
	var cloud = scene.atmosphere.cloud_deck
	var edge := Image.create(2, 2, false, Image.FORMAT_RF)
	edge.fill(Color.BLACK)
	for y in 2:
		edge.set_pixel(1, y, Color.WHITE)
	cloud.shadow_material.set_shader_parameter(
		"cloud_field_map", ImageTexture.create_from_image(edge)
	)
	cloud.shadow_material.set_shader_parameter("cloud_cover", .65625)
	var receiver := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 48
	receiver.mesh = plane
	var neutral := StandardMaterial3D.new()
	neutral.albedo_color = Color(.9, .9, .9)
	receiver.material_override = neutral
	receiver.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(receiver)
	var direction: Vector3 = scene.atmosphere.sun.global_basis.z
	receiver.position = cloud.position - direction * ((cloud.height - 20.0) / direction.y)
	scene.camera.position = receiver.position + Vector3(0, 24, 12)
	scene.camera.look_at(receiver.position)
	var grains := []
	for q in [2, 5]:
		if not await select_quality(q - 2):
			quit(1)
			return
		grains.append(edge_grain(await capture("edge-q%d" % q, -1)))
	assert(grains[1] < grains[0] * .6, "Dense native filtering must reject the old peppered edge")
	print("EDGE_GRAIN_RMS ", grains)
	# Short motion exposes screen-space grain/crawl.
	for step in 3:
		scene.camera.position += scene.camera.basis.x * .2
		await capture("edge-ultra-motion-%d" % step, 5)
	assert(model_bytes() == frozen)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(
			{
				"rows": rows,
				"default_quality": default_quality,
				"model_unchanged": true,
				"edge_grain_rms_low_ultra": grains,
				"actual_gui_quality_selection": true,
				"quality_survives_style_and_cloud_toggles": true,
				"boundary":
				"Short paused native Forward+ A/B, not active-world FPS or thermal stability."
			},
			"  "
		)
	)
	scene.free()
	quit()
