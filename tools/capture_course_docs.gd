extends SceneTree

## Reproducible screenshots of the real Forward+ scene. Never writes user saves.
var scene
var output := "res://docs/images"
var shots := []


func _initialize() -> void:
	create_timer(120).timeout.connect(func(): quit(1))
	_run.call_deferred()


func model_bytes() -> PackedByteArray:
	var state := {}
	for key in scene._world_models():
		state[key] = scene._world_models()[key].snapshot()
	return var_to_bytes(state)


func photo(label: String) -> void:
	scene.painterly_style._process(0)
	for frame in 8:
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.get_width() == 1440 and image.get_height() == 900)
	assert(image.save_png(output.path_join(label + ".png")) == OK)
	shots.append(label)
	print("COURSE_PHOTO ", label)


func clear_card() -> void:
	scene.observation.selected.clear()
	scene.camera.stop_following()
	scene._refresh_observation()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	scene.camera.set_process(false)
	Engine.max_fps = 20
	scene._refresh_hud()
	scene.hud.set_paused(true)
	var frozen := model_bytes()
	assert(not scene.painterly_style.debug_controls_enabled)
	assert(not scene.hud.style_button.visible)
	scene._view(1)
	await photo("valley")
	scene._view(5 + scene.animals.definitions.size())
	await photo("spring")
	var head: Vector2 = scene.land.spring_position()
	var mouth: Vector2 = scene.land.spring_mouth()
	var center := (head + mouth) * .5
	var target := Vector3(center.x, scene.land.height_at(center.x, center.y), center.y)
	scene.camera.position = target + Vector3(-20, 45, 40)
	scene.camera.look_at(target)
	await photo("ravine")
	scene._view(1)
	scene._toggle_soil_layers()
	for layer in [12, 2, 13, 14, 3, 9]:
		scene._select_soil_layer(layer)
		var label: String = {
			12: "water",
			2: "groundwater",
			13: "seepage",
			14: "sources",
			3: "soil-carbon",
			9: "soil-nitrogen"
		}[layer]
		if layer == 14:
			scene.hud.soil_layers.hovered_cell = scene.water.index_at(head.x, head.y)
			scene.hud.soil_layers._show_sample()
		await photo(label)
	scene._toggle_soil_layers()
	scene.hud.soil_layers.hovered_cell = -1
	scene._view(4)
	scene._toggle_fungi_map()
	await photo("fungi")
	scene._toggle_fungi_map()
	# Cards display actual selected model state; geometry/input has separate checks.
	var plant_id := 0
	for id in scene.trees.positions.size():
		if (
			scene.trees.alive[id]
			and scene.settings.plants[scene.trees.species[id]].growth_form == &"tree"
		):
			plant_id = id
			break
	assert(
		await scene._showcase(&"plant", plant_id),
		"Plant card must be selected through a visible face"
	)
	scene.hud.observation_panel.details_toggle.button_pressed = true
	await photo("plant")
	scene.hud.observation_panel.details_toggle.button_pressed = false
	clear_card()
	scene._view(5)
	await photo("hare")
	clear_card()
	scene._view(9)
	await photo("boar")
	clear_card()
	scene._view(1)
	scene._cycle_season()  # Explicit read-only seasonal preview, not evolved biology.
	await photo("winter-preview")
	for i in 4:
		scene._cycle_season()
	assert(scene.season_preview == 0)
	scene.hud.toast.hide()
	scene.hud.set_options_open(true)
	await photo("options")
	scene.hud.set_options_open(false)
	assert(
		model_bytes() == frozen, "Capturing documentation must never advance authoritative models"
	)
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"model_snapshots_unchanged": true,
		"screenshots": shots,
		"size": "1440x900",
		"scenario_seed": scene.settings.seed,
		"spring_m3_s": scene.settings.spring_flow_m3_s
	}
	assert(report.renderer == "forward_plus")
	FileAccess.open("res://artifacts/course-screenshots.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("COURSE_SCREENSHOTS ", JSON.stringify(report))
	scene.free()
	await process_frame
	quit()
