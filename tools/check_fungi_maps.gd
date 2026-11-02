extends SceneTree

## Real Forward+ nearest-plot / sparse soil-map check, no user saves or live window.
var world
var output := "res://artifacts/fungi-maps"
var render := false


func _initialize() -> void:
	if (
		DisplayServer.get_name() == "headless"
		and not OS.get_cmdline_user_args().has("--check-fungi-maps")
	):
		push_error("Use -- --check-fungi-maps so the check, not the smoke scene, owns exit")
		quit(1)
		return
	create_timer(90).timeout.connect(func(): quit(1))
	_run.call_deferred()


func state_bytes() -> PackedByteArray:
	var state := {}
	for key in world._world_models():
		state[key] = world._world_models()[key].snapshot()
	return var_to_bytes(state)


func settle() -> void:
	for frame in 3:
		if render:
			await RenderingServer.frame_post_draw
		else:
			await process_frame


func photo(name: String) -> void:
	await settle()
	if render:
		assert(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK)


func _run() -> void:
	render = DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(output)
	world = load("res://scripts/forest.gd").new()
	world.paused = true
	root.add_child(world)
	world.set_process(false)
	world.camera.set_process(false)
	world.hud.set_paused(true)
	Engine.max_fps = 20
	var frozen := state_bytes()
	var map: ForestFungiMap = world.hud.fungi_map
	world._toggle_fungi_map()
	for index in world.fungi.plots.size():
		var plot: Dictionary = world.fungi.plots[index]
		var center: Vector2 = plot.origin + Vector2.ONE * 16
		var target := Vector3(center.x, world.land.height_at(center.x, center.y), center.y)
		world.camera.position = target + Vector3(0, 32, 8)
		world.camera.look_at(target)
		await photo("plot-%d" % index)
		assert(
			map.selected_plot == index, "Camera motion changes the plot on pause, without a tick"
		)
		assert(map.label.text.contains(plot.definition.display_name))
		var b: PackedFloat64Array = plot.fields.biomass
		var image := map.biomass_texture.get_image()
		var brightest := 0
		for k in b.size():
			if b[k] > b[brightest]:
				brightest = k
		var expected := Color(.035, .06, .07).lerp(
			Color(.95, .73, .30), clampf(b[brightest] / .025, 0, 1)
		)
		var pixel := image.get_pixel(brightest % map.resolution, int(brightest / map.resolution))
		if render:
			# Dummy ImageTexture.update does not submit/read back subsequent images.
			# GPU contents are checked in the real Forward+ lane, not asserted here.
			assert(absf(pixel.r - expected.r) <= 1.0 / 255)
	world._toggle_fungi_map()
	world._toggle_soil_layers()
	world._select_soil_layer(6)  # Labile C, the same actual soil resource as G.
	var layers: ForestSoilLayers = world.hud.soil_layers
	assert(layers.fine_patches.size() == 3)
	assert(layers.fine_texture.get_width() == 128 and layers.fine_texture.get_height() == 384)
	assert(layers.fine_layout.get_width() == 2)
	for patch in layers.fine_patches:
		assert(patch.dx == .25)
		var point: Vector2 = patch.origin + Vector2(.125, .125)
		var sample := layers.sample_at(point)
		var actual: Dictionary = world.soil.native.sample(Vector3(point.x, 0, point.y))
		assert(sample.dx == .25 and absf(sample.value - actual.labile_c_kg_m2 * 1000) < 1e-9)
	var origin: Vector2 = layers.fine_patches[0].origin
	var focus := origin + Vector2(1, 1)
	var target := Vector3(focus.x, world.land.height_at(focus.x, focus.y), focus.y)
	world.camera.position = target + Vector3(7, 16, 14)
	world.camera.look_at(target)
	layers.hovered_point = focus
	layers.hovered_cell = world.water.index_at(focus.x, focus.y)
	layers._show_sample()
	await photo("labile-c-multiscale")
	assert(layers.sample_label.text.contains("0.25"))
	world._select_soil_layer(12)
	assert(layers.fine_patches.is_empty())
	assert(layers.display_parameters().soil_fine_count == 0)
	if render:
		assert(world.terrain.material.get_shader_param("soil_fine_count") == 0)
	await photo("water-coarse-control")
	world._toggle_soil_layers()
	assert(state_bytes() == frozen, "Maps and camera must not change any model")
	# Camera-only remapping is safe while a real worker owns the models.
	world._toggle_fungi_map()
	world.use_model_worker = true
	world.paused = false
	world._process(world.settings.ecology_step_s)
	assert(world.model_work_active)
	var center: Vector2 = map.display_plots[0].origin + Vector2.ONE * 16
	world.camera.position.x = center.x
	world.camera.position.z = center.y
	map._process(0)
	assert(map.selected_plot == 0)
	world._finish_model_work(true)
	world.paused = true
	world._check_clock_alignment()
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"display_server": DisplayServer.get_name(),
		"gpu_texture_checks": render,
		"nearest_plot_on_pause": true,
		"all_species_labels_and_fields": true,
		"sparse_atlas_pixels": 128 * 384,
		"fine_cell_m": .25,
		"water_not_refined": true,
		"maps_read_only": true,
		"nearest_selection_during_busy_worker": true
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	var run_report := "render-report.json" if render else "headless-report.json"
	FileAccess.open(output.path_join(run_report), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("FUNGI_MAPS ", JSON.stringify(report))
	_shutdown.call_deferred()


func _shutdown() -> void:
	world.free()
	world = null
	quit()
