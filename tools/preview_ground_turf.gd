extends SceneTree

var scene
var output := "res://artifacts/ground-turf-render"
var phases := []


func _initialize() -> void:
	create_timer(60).timeout.connect(func(): quit(1))
	_run.call_deferred()


func photo(label: String, enabled: bool) -> Image:
	scene.terrain.material.set_shader_param("turf_enabled", enabled)
	scene.painterly_style._process(0)
	for frame in 5:
		await RenderingServer.frame_post_draw
	var gpu := 0.0
	for frame in 8:
		await RenderingServer.frame_post_draw
		gpu += scene.painterly_style.pixel_renderer.frame_times().gpu_ms
	var image := root.get_texture().get_image()
	assert(image.save_png(output.path_join(label + ".png")) == OK)
	phases.append(
		{
			"label": label,
			"turf": enabled,
			"gpu_ms_mean": gpu / 8,
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		}
	)
	return image


func model_bytes() -> PackedByteArray:
	var state := {}
	for key in scene._world_models():
		state[key] = scene._world_models()[key].snapshot()
	return var_to_bytes(state)


func difference(a: Image, b: Image) -> float:
	var total := 0.0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
	return total / (ceilf(a.get_width() / 4.0) * ceilf(a.get_height() / 4.0) * 3)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.hud.visible = false
	scene.turf_cards.visible = false
	scene.turf_cards.set_process(false)
	Engine.max_fps = 30
	scene.terrain.advance_ecology_display(1)
	var frozen := model_bytes()
	var best := -INF
	var point := Vector3.ZERO
	for z in range(64, 448, 4):
		for x in range(64, 448, 4):
			var site: Vector4 = scene.land.habitat_at(x, z)
			var score: float = site.y - Vector2(x - 256, z - 256).length() * .0007
			if scene.water.depth[scene.water.index_at(x, z)] < .001 and score > best:
				best = score
				point = Vector3(x, scene.land.height_at(x, z), z)
	scene.vegetation.visible = false
	scene.habitat_view.visible = false
	scene.animals_view.visible = false
	scene.fungi_view.visible = false
	scene.camera.position = point + Vector3(0, 1.5, 2.2)
	scene.camera.look_at(point)
	var visible_change := []
	for mode in 3:
		scene.painterly_style.set_mode(mode)
		var before := await photo("01-surface-%d-before" % mode, false)
		var after := await photo("02-surface-%d-after" % mode, true)
		var change := difference(before, after)
		assert(change > .001, "Known-wrong disabled turf must differ from the new material")
		visible_change.append(change)
		assert(phases[-1].primitives == phases[-2].primitives, "No new geometry")
		assert(phases[-1].draw_calls == phases[-2].draw_calls, "No overlay draw pass")
	# Diagnostics must not be contaminated by decorative maps.
	var diagnostic := Image.create(2, 2, false, Image.FORMAT_RGB8)
	diagnostic.fill(Color(.2, .45, .8))
	scene.terrain.set_soil_layer(ImageTexture.create_from_image(diagnostic), true)
	var diagnostic_before := await photo("03-diagnostic-before", false)
	var diagnostic_after := await photo("03-diagnostic-after", true)
	var diagnostic_change := difference(diagnostic_before, diagnostic_after)
	assert(diagnostic_change < .0001)
	scene.terrain.set_soil_layer(null, false)
	scene.terrain.material.set_shader_param("snow_water_m", .03)
	var snow_before := await photo("04-snow-before", false)
	var snow_after := await photo("04-snow-after", true)
	var snow_change := difference(snow_before, snow_after)
	assert(snow_change < .0001, "Snow must replace both turf colour and its normals")
	scene.terrain.material.set_shader_param("snow_water_m", 0.0)
	scene.vegetation.visible = true
	scene.habitat_view.visible = true
	scene.animals_view.visible = true
	scene.fungi_view.visible = true
	scene.camera.position = point + Vector3(5, 3, 7)
	scene.camera.look_at(point + Vector3(0, .6, 0))
	await photo("05-in-the-forest-before", false)
	await photo("05-in-the-forest-after", true)
	scene.camera.view(1)
	await photo("06-valley-before", false)
	await photo("06-valley-after", true)
	# Fixed crossed planes, not camera-facing billboards, at eye level.
	scene.camera.position = point + Vector3(1.5, .65, 2.5)
	scene.camera.look_at(point + Vector3(0, .18, 0))
	await photo("07-upright-grass-before", true)
	scene.turf_cards.set_process(true)
	await photo("07-upright-grass-after", true)
	assert(scene.turf_cards.patches.size() <= pow(2 * scene.turf_cards.TILE_RADIUS + 1, 2))
	var tile: Vector2i = scene.turf_cards.patches.keys()[0]
	var mm: MultiMesh = scene.turf_cards.patches[tile].multimesh
	var cards_buffer := mm.buffer.duplicate()
	var pose: Transform3D = scene.camera.transform
	scene.camera.rotate_y(.4)
	scene.turf_cards._process(0)
	assert(mm.buffer == cards_buffer, "Cards do not rotate with the camera")
	scene.camera.transform = pose
	scene.turf_cards._process(0)
	# A view rebuild at the same tile must reproduce the same positions.
	var duplicate: MultiMeshInstance3D = scene.turf_cards._patch(tile)
	assert(duplicate.multimesh.buffer == cards_buffer)
	duplicate.free()
	assert(model_bytes() == frozen, "All authoritative model snapshots must stay byte-identical")
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"point": point,
		"surface_mean_rgb_difference": visible_change,
		"diagnostic_difference": diagnostic_change,
		"snow_difference": snow_change,
		"unchanged_models": true,
		"fixed_world_cards": true,
		"card_patches": scene.turf_cards.patches.size(),
		"phases": phases,
		"boundary":
		(
			"Short paused Forward+ presentation comparison, not a native FPS or ecosystem validation. "
			+ "No user saves written."
		)
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("GROUND_TURF_RENDER ", JSON.stringify(report))
	scene.free()
	quit()
